package main

import (
	"context"
	"database/sql"
	_ "embed"
	"encoding/json"
	"fmt"
	"strings"
	"time"
)

//go:embed realtime_schema.sql
var realtimeSchema string

type realtimeEvent struct {
	Seq       int64
	Type      string
	Audience  string
	OwnerUID  int64
	PeerUID   int64
	RoomID    int64
	Payload   json.RawMessage
	CreatedAt int64
}

func (a *App) prepareRealtime() error {
	ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
	defer cancel()
	connection, err := a.db.Conn(ctx)
	if err != nil {
		return err
	}
	defer connection.Close()
	var acquired int
	lockName := "csac:realtime:schema:" + a.config.DBName
	if err := connection.QueryRowContext(ctx, "SELECT GET_LOCK(?, 30)", lockName).Scan(&acquired); err != nil {
		return fmt.Errorf("acquire realtime migration lock: %w", err)
	}
	if acquired != 1 {
		return fmt.Errorf("realtime migration lock timed out")
	}
	defer connection.ExecContext(context.Background(), "SELECT RELEASE_LOCK(?)", lockName)
	if _, err := connection.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS csac_realtime_migrations (
        version INT NOT NULL PRIMARY KEY, applied_at BIGINT NOT NULL
    ) ENGINE=InnoDB`); err != nil {
		return err
	}
	var applied int
	err = connection.QueryRowContext(ctx, "SELECT version FROM csac_realtime_migrations WHERE version = 1").Scan(&applied)
	if err == nil {
		return nil
	}
	if err != sql.ErrNoRows {
		return err
	}
	// These imported tables used MyISAM. Transactional triggers require the
	// business row and its outbox record to commit or roll back together.
	for _, table := range []string{"friend_relation", "friend_request"} {
		var engine string
		if err := connection.QueryRowContext(ctx, `SELECT ENGINE FROM information_schema.TABLES
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?`, table).Scan(&engine); err != nil {
			return err
		}
		if !strings.EqualFold(engine, "InnoDB") {
			if _, err := connection.ExecContext(ctx, "ALTER TABLE `"+table+"` ENGINE=InnoDB"); err != nil {
				return err
			}
		}
	}
	for index, statement := range strings.Split(realtimeSchema, "-- csac:statement") {
		if _, err := connection.ExecContext(ctx, statement); err != nil {
			return fmt.Errorf("apply realtime schema statement %d: %w", index+1, err)
		}
	}
	_, err = connection.ExecContext(ctx, "INSERT INTO csac_realtime_migrations VALUES (1, UNIX_TIMESTAMP())")
	return err
}

func (a *App) realtimeBounds(ctx context.Context) (latest, retainedAfter int64, err error) {
	err = a.db.QueryRowContext(ctx, "SELECT last_seq, retained_after FROM csac_realtime_state WHERE id = 1").Scan(&latest, &retainedAfter)
	return
}

func scanRealtimeEvents(rows *sql.Rows, published bool) ([]realtimeEvent, error) {
	defer rows.Close()
	events := make([]realtimeEvent, 0, 128)
	for rows.Next() {
		var event realtimeEvent
		var payload []byte
		if err := rows.Scan(&event.Seq, &event.Type, &event.Audience, &event.OwnerUID,
			&event.PeerUID, &event.RoomID, &payload, &event.CreatedAt); err != nil {
			return nil, err
		}
		event.Payload = append(json.RawMessage(nil), payload...)
		if !published && !json.Valid(event.Payload) {
			return nil, fmt.Errorf("invalid realtime outbox payload")
		}
		events = append(events, event)
	}
	return events, rows.Err()
}

func (a *App) readRealtimeEvents(ctx context.Context, after int64, limit int) ([]realtimeEvent, error) {
	rows, err := a.db.QueryContext(ctx, `SELECT seq, event_type, audience, owner_uid, peer_uid, room_id, payload, created_at
        FROM csac_realtime_events WHERE seq > ? ORDER BY seq LIMIT ?`, after, limit)
	if err != nil {
		return nil, err
	}
	return scanRealtimeEvents(rows, true)
}

func (a *App) publishRealtimeEvents(ctx context.Context) error {
	var pending int
	if err := a.db.QueryRowContext(ctx, "SELECT EXISTS(SELECT 1 FROM csac_realtime_outbox LIMIT 1)").Scan(&pending); err != nil || pending == 0 {
		return err
	}
	tx, err := a.db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted})
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var sequence, timestamp int64
	// The state row serializes publishers across processes. Sequence numbers are
	// assigned after reading committed outbox rows, so a late transaction cannot
	// disappear behind a cursor that already advanced past its auto-increment ID.
	if err := tx.QueryRowContext(ctx, "SELECT last_seq, UNIX_TIMESTAMP() FROM csac_realtime_state WHERE id = 1 FOR UPDATE").Scan(&sequence, &timestamp); err != nil {
		return err
	}
	rows, err := tx.QueryContext(ctx, `SELECT id, event_type, audience, owner_uid, peer_uid, room_id, payload, created_at
        FROM csac_realtime_outbox ORDER BY id LIMIT 256 FOR UPDATE SKIP LOCKED`)
	if err != nil {
		return err
	}
	events, err := scanRealtimeEvents(rows, false)
	if err != nil || len(events) == 0 {
		return err
	}
	values := make([]string, 0, len(events))
	arguments := make([]any, 0, len(events)*8)
	ids := make([]any, 0, len(events))
	placeholders := make([]string, 0, len(events))
	for _, event := range events {
		sequence++
		values = append(values, "(?, ?, ?, ?, ?, ?, ?, ?)")
		arguments = append(arguments, sequence, event.Type, event.Audience, event.OwnerUID,
			event.PeerUID, event.RoomID, string(event.Payload), timestamp)
		ids = append(ids, event.Seq)
		placeholders = append(placeholders, "?")
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO csac_realtime_events
        (seq, event_type, audience, owner_uid, peer_uid, room_id, payload, created_at) VALUES `+strings.Join(values, ","), arguments...); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, "DELETE FROM csac_realtime_outbox WHERE id IN ("+strings.Join(placeholders, ",")+")", ids...); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, "UPDATE csac_realtime_state SET last_seq = ? WHERE id = 1", sequence); err != nil {
		return err
	}
	return tx.Commit()
}

func (a *App) pruneRealtime(ctx context.Context) error {
	cutoff := time.Now().Add(-time.Duration(a.config.WSRetentionDays) * 24 * time.Hour).Unix()
	tx, err := a.db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted})
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var retainedAfter int64
	if err := tx.QueryRowContext(ctx, "SELECT retained_after FROM csac_realtime_state WHERE id = 1 FOR UPDATE").Scan(&retainedAfter); err != nil {
		return err
	}
	rows, err := tx.QueryContext(ctx, "SELECT seq, created_at FROM csac_realtime_events ORDER BY seq LIMIT 10000")
	if err != nil {
		return err
	}
	for rows.Next() {
		var sequence, createdAt int64
		if err := rows.Scan(&sequence, &createdAt); err != nil {
			rows.Close()
			return err
		}
		if createdAt >= cutoff {
			break
		}
		retainedAfter = sequence
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, "DELETE FROM csac_realtime_events WHERE seq <= ?", retainedAfter); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, "UPDATE csac_realtime_state SET retained_after = ? WHERE id = 1", retainedAfter); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, "DELETE FROM csac_ws_requests WHERE created_at < ? LIMIT 10000", cutoff); err != nil {
		return err
	}
	return tx.Commit()
}
