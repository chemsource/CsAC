package passwords

import (
	"database/sql"
	"errors"
	"fmt"

	"golang.org/x/crypto/bcrypt"
)

// EnsureSchema must succeed before writing the longer transitional credentials.
func EnsureSchema(db *sql.DB) error {
	var length int64
	err := db.QueryRow(`SELECT CHARACTER_MAXIMUM_LENGTH FROM information_schema.COLUMNS
		WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'chat_user' AND COLUMN_NAME = 'pwd'`).Scan(&length)
	if err != nil {
		return fmt.Errorf("inspect password column: %w", err)
	}
	if length >= 255 {
		return nil
	}
	_, err = db.Exec("ALTER TABLE chat_user MODIFY COLUMN pwd VARCHAR(255) NOT NULL")
	return err
}

// Authenticate upgrades verified credentials with a compare-and-swap update.
// If another writer wins, recheck its current credential before accepting login.
func Authenticate(db *sql.DB, id int64, username, stored, password string) (bool, error) {
	for attempt := 0; attempt < 3; attempt++ {
		if !Verify(stored, password, username) {
			return false, nil
		}
		replacement := stored
		var err error
		if len(password) > MaxPasswordBytes {
			// Older accounts allowed long passwords. Keep their full digest protected.
			replacement, err = WrapLegacy(stored)
		} else if cost, costErr := bcrypt.Cost([]byte(stored)); costErr != nil || cost < Cost {
			replacement, err = Hash(password)
		}
		if err != nil {
			return false, err
		}
		if replacement == stored {
			return true, nil
		}
		result, err := db.Exec("UPDATE chat_user SET pwd = ? WHERE id = ? AND BINARY pwd = BINARY ?", replacement, id, stored)
		if err != nil {
			return false, err
		}
		count, err := result.RowsAffected()
		if err != nil {
			return false, err
		}
		if count > 0 {
			return true, nil
		}
		err = db.QueryRow("SELECT username, pwd FROM chat_user WHERE id = ?", id).Scan(&username, &stored)
		if errors.Is(err, sql.ErrNoRows) {
			return false, nil
		}
		if err != nil {
			return false, err
		}
	}
	return false, errors.New("password changed repeatedly during authentication")
}

// MigrateLegacy batches rows and closes each cursor before doing bcrypt work.
// Conditional updates preserve concurrent logins, resets and previous migrations.
func MigrateLegacy(db *sql.DB) (int64, error) {
	const batchSize = 100
	type credential struct {
		id     int64
		stored string
	}
	var lastID, migrated int64
	for {
		rows, err := db.Query("SELECT id, pwd FROM chat_user WHERE id > ? AND CHAR_LENGTH(pwd) IN (32, 64) ORDER BY id LIMIT ?", lastID, batchSize)
		if err != nil {
			return migrated, err
		}
		batch := make([]credential, 0, batchSize)
		for rows.Next() {
			var id int64
			var stored string
			if err := rows.Scan(&id, &stored); err != nil {
				rows.Close()
				return migrated, err
			}
			batch = append(batch, credential{id, stored})
			lastID = id
		}
		err = rows.Err()
		rows.Close()
		if err != nil {
			return migrated, err
		}
		if len(batch) == 0 {
			return migrated, nil
		}
		for _, credential := range batch {
			wrapped, err := WrapLegacy(credential.stored)
			if err != nil {
				return migrated, err
			}
			if wrapped == credential.stored {
				continue
			}
			result, err := db.Exec("UPDATE chat_user SET pwd = ? WHERE id = ? AND BINARY pwd = BINARY ?", wrapped, credential.id, credential.stored)
			if err != nil {
				return migrated, err
			}
			count, err := result.RowsAffected()
			if err != nil {
				return migrated, err
			}
			migrated += count
		}
	}
}
