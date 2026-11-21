package main

import (
	"context"
	"database/sql"
	"errors"
	"time"

	"github.com/go-sql-driver/mysql"
)

var (
	errRegistrationUsernameTaken = errors.New("username already registered")
	errRegistrationEmailTaken    = errors.New("email already registered")
	errRegistrationEmailCodeUsed = errors.New("email verification code unavailable")
)

type accountRegistration struct {
	username    string
	nickname    string
	password    string // already hashed
	email       string
	avatar      string
	emailCodeID int64
	codeDigest  []byte
}

// A registration and its initial session are visible only after a successful
// commit. In particular, an account or session write failure must not use quota.
func (a *App) registerAccount(ctx context.Context, account accountRegistration) (*Session, error) {
	tx, err := a.db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted})
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	// The temporary row is deleted in this same transaction. A second request
	// for an equivalent username must wait until this transaction completes.
	if _, err := tx.ExecContext(ctx, `INSERT INTO csac_registration_name_locks (username) VALUES (?)
		ON DUPLICATE KEY UPDATE username = VALUES(username)`, account.username); err != nil {
		return nil, err
	}
	var exists int
	err = tx.QueryRowContext(ctx, "SELECT 1 FROM chat_user WHERE username = ? LIMIT 1", account.username).Scan(&exists)
	if err == nil {
		return nil, errRegistrationUsernameTaken
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return nil, err
	}

	var registrationCodeID int64
	if account.codeDigest != nil {
		registrationCodeID, err = lookupUsableRegistrationCode(ctx, tx, account.codeDigest, true)
		if err != nil {
			return nil, err
		}
	}
	now := time.Now().Unix()
	if account.emailCodeID > 0 {
		res, err := tx.ExecContext(ctx, "UPDATE register_email_codes SET used_at = ? WHERE id = ? AND used_at = 0 AND expires_at >= ?", now, account.emailCodeID, now)
		if err != nil {
			return nil, err
		}
		if changed, err := res.RowsAffected(); err != nil || changed != 1 {
			if err != nil {
				return nil, err
			}
			return nil, errRegistrationEmailCodeUsed
		}
	}

	res, err := tx.ExecContext(ctx, `INSERT INTO chat_user (username, nickname, email, pwd, add_time, avatar, hide_conv, is_first_login, last_active)
		VALUES (?, ?, ?, ?, ?, ?, '', 1, ?)`, account.username, account.nickname, nullableString(account.email), account.password, now, account.avatar, now)
	if err != nil {
		// The existing schema enforces a unique index for non-NULL emails.
		var dbErr *mysql.MySQLError
		if account.email != "" && errors.As(err, &dbErr) && dbErr.Number == 1062 {
			return nil, errRegistrationEmailTaken
		}
		return nil, err
	}
	uid, err := res.LastInsertId()
	if err != nil {
		return nil, err
	}
	if uid <= 0 || uid == a.config.AdminUID {
		return nil, errors.New("cannot allocate reserved user ID for public registration")
	}
	if registrationCodeID != 0 {
		if _, err := tx.ExecContext(ctx, "UPDATE csac_registration_codes SET used_count = used_count + 1 WHERE id = ?", registrationCodeID); err != nil {
			return nil, err
		}
		if _, err := tx.ExecContext(ctx, "INSERT INTO csac_registration_code_redemptions (uid, code_id, registered_at) VALUES (?, ?, ?)", uid, registrationCodeID, now); err != nil {
			return nil, err
		}
	}
	session := &Session{SID: randomSessionID(), UID: uid, Nickname: account.nickname, LastTouch: now, ExpiresAt: now + a.config.SessionLifetimeSeconds}
	if _, err := tx.ExecContext(ctx, insertSessionSQL, session.storageArgs(now)...); err != nil {
		return nil, err
	}
	if _, err := tx.ExecContext(ctx, "DELETE FROM csac_registration_name_locks WHERE username = ?", account.username); err != nil {
		return nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return session, nil
}
