package main

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/base32"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"
	"time"
)

const registrationCodePrefix = "CSAC-"

var errInvalidRegistrationCode = errors.New("invalid registration code")

type registrationCodeStore struct {
	db     *sql.DB
	cipher cipher.AEAD
}

func newRegistrationCodeCipher(encoded string) (cipher.AEAD, error) {
	if encoded == "" {
		return nil, nil
	}
	key, err := base64.StdEncoding.Strict().DecodeString(encoded)
	if err != nil || len(key) != 32 {
		return nil, errors.New("CSAC_REGISTRATION_CODE_KEY must be 32 bytes encoded as standard Base64")
	}
	defer clear(key)
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	return cipher.NewGCMWithRandomNonce(block)
}

func (s registrationCodeStore) prepare() error {
	for _, stmt := range []string{
		`CREATE TABLE IF NOT EXISTS csac_registration_codes (
			id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
			code_hash BINARY(32) NOT NULL UNIQUE,
			code_ciphertext VARBINARY(128) NOT NULL,
			max_uses INT NOT NULL,
			used_count INT NOT NULL DEFAULT 0,
			created_at BIGINT NOT NULL,
			created_by BIGINT NOT NULL,
			expires_at BIGINT NULL,
			revoked_at BIGINT NULL,
			revoked_by BIGINT NULL
		) ENGINE=InnoDB`,
		`CREATE TABLE IF NOT EXISTS csac_registration_code_redemptions (
			uid BIGINT NOT NULL PRIMARY KEY,
			code_id BIGINT NOT NULL,
			registered_at BIGINT NOT NULL,
			INDEX (code_id, uid),
			FOREIGN KEY (code_id) REFERENCES csac_registration_codes (id) ON DELETE RESTRICT
		) ENGINE=InnoDB`,
		// Some legacy databases do not have a unique index for chat_user.username.
		// Serialize RPC registrations for equivalent usernames without rewriting old accounts.
		`CREATE TABLE IF NOT EXISTS csac_registration_name_locks (
			username VARCHAR(32) NOT NULL PRIMARY KEY
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
	} {
		if _, err := s.db.Exec(stmt); err != nil {
			return err
		}
	}
	var count int
	err := s.db.QueryRow(`SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE()
		AND ENGINE = 'InnoDB' AND TABLE_NAME IN ('chat_user', 'csac_sessions', 'register_email_codes',
		'csac_registration_codes', 'csac_registration_code_redemptions', 'csac_registration_name_locks')`).Scan(&count)
	if err == nil && count != 6 {
		err = errors.New("account, session and registration tables must use InnoDB")
	}
	return err
}

type registrationCodeInfo struct {
	ID            int64  `json:"id"`
	MaxUses       int64  `json:"max_uses"`
	UsedCount     int64  `json:"used_count"`
	RemainingUses int64  `json:"remaining_uses"`
	CreatedAt     int64  `json:"created_at"`
	CreatedBy     int64  `json:"created_by"`
	ExpiresAt     *int64 `json:"expires_at"`
	RevokedAt     *int64 `json:"revoked_at"`
	RevokedBy     *int64 `json:"revoked_by"`
	Status        string `json:"status"`
}

type registrationCodeSecret struct {
	registrationCodeInfo
	Code string `json:"code"`
}

const registrationCodeColumns = "id, max_uses, used_count, created_at, created_by, expires_at, revoked_at, revoked_by"

type registrationRowScanner interface {
	Scan(...any) error
}

func (r *registrationCodeInfo) scan(scanner registrationRowScanner, extra ...any) error {
	return scanner.Scan(append([]any{&r.ID, &r.MaxUses, &r.UsedCount, &r.CreatedAt, &r.CreatedBy, &r.ExpiresAt, &r.RevokedAt, &r.RevokedBy}, extra...)...)
}

func (r *registrationCodeInfo) describe(now int64) {
	r.RemainingUses = r.MaxUses - r.UsedCount
	switch {
	case r.RevokedAt != nil:
		r.Status = "revoked"
	case r.ExpiresAt != nil && *r.ExpiresAt <= now:
		r.Status = "expired"
	case r.RemainingUses <= 0:
		r.Status = "exhausted"
	default:
		r.Status = "active"
	}
}

func (s registrationCodeStore) create(ctx context.Context, adminUID, maxUses int64, expiresAt *int64) (registrationCodeSecret, error) {
	var random [20]byte
	if _, err := rand.Read(random[:]); err != nil {
		return registrationCodeSecret{}, err
	}
	code := registrationCodePrefix + base32.StdEncoding.EncodeToString(random[:])
	hash := sha256.Sum256([]byte(code))
	sealed := s.cipher.Seal(nil, nil, []byte(code), hash[:])
	now := time.Now().Unix()
	res, err := s.db.ExecContext(ctx, `INSERT INTO csac_registration_codes
		(code_hash, code_ciphertext, max_uses, created_at, created_by, expires_at) VALUES (?, ?, ?, ?, ?, ?)`,
		hash[:], sealed, maxUses, now, adminUID, expiresAt)
	if err != nil {
		return registrationCodeSecret{}, err
	}
	id, err := res.LastInsertId()
	info := registrationCodeInfo{ID: id, MaxUses: maxUses, CreatedAt: now, CreatedBy: adminUID, ExpiresAt: expiresAt}
	info.describe(now)
	return registrationCodeSecret{registrationCodeInfo: info, Code: code}, err
}

func (s registrationCodeStore) list(ctx context.Context, beforeID int64, limit int) ([]registrationCodeInfo, *int64, error) {
	query := "SELECT " + registrationCodeColumns + " FROM csac_registration_codes"
	args := make([]any, 0, 2)
	if beforeID > 0 {
		query += " WHERE id < ?"
		args = append(args, beforeID)
	}
	rows, err := s.db.QueryContext(ctx, query+" ORDER BY id DESC LIMIT ?", append(args, limit+1)...)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()
	codes := make([]registrationCodeInfo, 0, limit+1)
	now := time.Now().Unix()
	for rows.Next() {
		var info registrationCodeInfo
		if err := info.scan(rows); err != nil {
			return nil, nil, err
		}
		info.describe(now)
		codes = append(codes, info)
	}
	if len(codes) > limit {
		return codes[:limit], &codes[limit-1].ID, rows.Err()
	}
	return codes, nil, rows.Err()
}

type registrationCodeRedemption struct {
	UID          int64  `json:"uid"`
	Username     string `json:"username"`
	Nickname     string `json:"nickname"`
	RegisteredAt int64  `json:"registered_at"`
}

type registrationCodeDetail struct {
	RegistrationCode registrationCodeSecret       `json:"registration_code"`
	Redemptions      []registrationCodeRedemption `json:"redemptions"`
	NextBeforeUID    *int64                       `json:"next_before_uid"`
}

func (s registrationCodeStore) detail(ctx context.Context, id, beforeUID int64, limit int) (registrationCodeDetail, error) {
	tx, err := s.db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelRepeatableRead, ReadOnly: true})
	if err != nil {
		return registrationCodeDetail{}, err
	}
	defer tx.Rollback()
	var info registrationCodeInfo
	var hash, sealed []byte
	if err := info.scan(tx.QueryRowContext(ctx, "SELECT "+registrationCodeColumns+", code_hash, code_ciphertext FROM csac_registration_codes WHERE id = ?", id), &hash, &sealed); err != nil {
		return registrationCodeDetail{}, err
	}
	plain, err := s.cipher.Open(nil, nil, sealed, hash)
	if err != nil {
		return registrationCodeDetail{}, fmt.Errorf("decrypt registration code: %w", err)
	}
	info.describe(time.Now().Unix())
	result := registrationCodeDetail{
		RegistrationCode: registrationCodeSecret{registrationCodeInfo: info, Code: string(plain)},
		Redemptions:      make([]registrationCodeRedemption, 0, limit+1),
	}
	query := `SELECT r.uid, COALESCE(u.username, ''), COALESCE(u.nickname, ''), r.registered_at
		FROM csac_registration_code_redemptions r LEFT JOIN chat_user u ON u.id = r.uid WHERE r.code_id = ?`
	args := []any{id}
	if beforeUID > 0 {
		query += " AND r.uid < ?"
		args = append(args, beforeUID)
	}
	rows, err := tx.QueryContext(ctx, query+" ORDER BY r.uid DESC LIMIT ?", append(args, limit+1)...)
	if err != nil {
		return registrationCodeDetail{}, err
	}
	defer rows.Close()
	for rows.Next() {
		var use registrationCodeRedemption
		if err := rows.Scan(&use.UID, &use.Username, &use.Nickname, &use.RegisteredAt); err != nil {
			return registrationCodeDetail{}, err
		}
		result.Redemptions = append(result.Redemptions, use)
	}
	if len(result.Redemptions) > limit {
		result.Redemptions = result.Redemptions[:limit]
		result.NextBeforeUID = &result.Redemptions[limit-1].UID
	}
	return result, rows.Err()
}

func (s registrationCodeStore) revoke(ctx context.Context, id, adminUID int64) error {
	res, err := s.db.ExecContext(ctx, `UPDATE csac_registration_codes SET revoked_at = UNIX_TIMESTAMP(), revoked_by = ?
		WHERE id = ? AND revoked_at IS NULL`, adminUID, id)
	if err != nil {
		return err
	}
	changed, err := res.RowsAffected()
	if err != nil || changed > 0 {
		return err
	}
	var exists int
	return s.db.QueryRowContext(ctx, "SELECT 1 FROM csac_registration_codes WHERE id = ?", id).Scan(&exists)
}

func registrationCodeDigest(code string) ([]byte, bool) {
	part, found := strings.CutPrefix(code, registrationCodePrefix)
	if !found || len(part) != 32 {
		return nil, false
	}
	for _, b := range part {
		if !(b >= 'A' && b <= 'Z' || b >= '2' && b <= '7') {
			return nil, false
		}
	}
	digest := sha256.Sum256([]byte(code))
	return digest[:], true
}

type registrationQueryer interface {
	QueryRowContext(context.Context, string, ...any) *sql.Row
}

// The precheck rejects unusable codes before password hashing. The same check
// inside the account transaction takes the row lock and is authoritative.
func lookupUsableRegistrationCode(ctx context.Context, q registrationQueryer, digest []byte, lock bool) (int64, error) {
	query := "SELECT " + registrationCodeColumns + " FROM csac_registration_codes WHERE code_hash = ?"
	if lock {
		query += " FOR UPDATE"
	}
	var info registrationCodeInfo
	if err := info.scan(q.QueryRowContext(ctx, query, digest)); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return 0, errInvalidRegistrationCode
		}
		return 0, err
	}
	info.describe(time.Now().Unix())
	if info.Status != "active" {
		return 0, errInvalidRegistrationCode
	}
	return info.ID, nil
}
