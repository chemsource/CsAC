-- CsAC realtime schema v1. Payloads contain explicit public identifiers only.

CREATE TABLE IF NOT EXISTS csac_realtime_outbox (
    id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    event_type VARCHAR(64) NOT NULL,
    audience VARCHAR(16) NOT NULL,
    owner_uid BIGINT NOT NULL DEFAULT 0,
    peer_uid BIGINT NOT NULL DEFAULT 0,
    room_id BIGINT NOT NULL DEFAULT 0,
    payload LONGTEXT NOT NULL,
    created_at BIGINT NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4

-- csac:statement

CREATE TABLE IF NOT EXISTS csac_realtime_events (
    seq BIGINT NOT NULL PRIMARY KEY,
    event_type VARCHAR(64) NOT NULL,
    audience VARCHAR(16) NOT NULL,
    owner_uid BIGINT NOT NULL DEFAULT 0,
    peer_uid BIGINT NOT NULL DEFAULT 0,
    room_id BIGINT NOT NULL DEFAULT 0,
    payload LONGTEXT NOT NULL,
    created_at BIGINT NOT NULL,
    INDEX idx_csac_events_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4

-- csac:statement

CREATE TABLE IF NOT EXISTS csac_realtime_state (
    id TINYINT NOT NULL PRIMARY KEY,
    last_seq BIGINT NOT NULL DEFAULT 0,
    retained_after BIGINT NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4

-- csac:statement

INSERT IGNORE INTO csac_realtime_state (id) VALUES (1)

-- csac:statement

CREATE TABLE IF NOT EXISTS csac_ws_requests (
    uid BIGINT NOT NULL,
    request_key VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    fingerprint CHAR(64) CHARACTER SET ascii NOT NULL,
    result_json LONGTEXT NULL,
    created_at BIGINT NOT NULL,
    PRIMARY KEY (uid, request_key),
    INDEX idx_csac_ws_requests_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_chat_msg_insert
AFTER INSERT ON chat_msg
FOR EACH ROW
BEGIN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('message.created', 'group', 0, 0, NEW.room_id,
        JSON_OBJECT('msg_id', NEW.id, 'room_id', NEW.room_id, 'uid', NEW.uid, 'msg_type', NEW.msg_type), UNIX_TIMESTAMP());
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_private_msg_insert
AFTER INSERT ON private_msg
FOR EACH ROW
BEGIN
    IF NEW.type = 'private' THEN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('message.created', 'pair', NEW.from_uid, NEW.to_uid, 0,
        JSON_OBJECT('msg_id', NEW.id, 'from_uid', NEW.from_uid, 'to_uid', NEW.to_uid, 'is_read', NEW.is_read, 'msg_type', NEW.msg_type), UNIX_TIMESTAMP());
    END IF;
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_chat_user_notice_insert
AFTER INSERT ON chat_user_notice
FOR EACH ROW
BEGIN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('notification.created', 'user', NEW.uid, 0, 0,
        JSON_OBJECT('notice_id', NEW.id, 'is_read', NEW.is_read, 'operation', 'insert'), UNIX_TIMESTAMP());
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_friend_request_insert
AFTER INSERT ON friend_request
FOR EACH ROW
BEGIN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('friend.request_changed', 'pair', NEW.from_uid, NEW.to_uid, 0,
        JSON_OBJECT('request_id', NEW.id, 'from_uid', NEW.from_uid, 'to_uid', NEW.to_uid, 'status', NEW.status, 'operation', 'insert'), UNIX_TIMESTAMP());
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_friend_relation_insert
AFTER INSERT ON friend_relation
FOR EACH ROW
BEGIN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('friend.changed', 'pair', NEW.uid1, NEW.uid2, 0,
        JSON_OBJECT('uid1', NEW.uid1, 'uid2', NEW.uid2, 'status', NEW.status, 'operation', 'insert'), UNIX_TIMESTAMP());
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_group_files_insert
AFTER INSERT ON group_files
FOR EACH ROW
BEGIN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('group.files_changed', 'group', 0, 0, NEW.room_id,
        JSON_OBJECT('room_id', NEW.room_id, 'entity_id', NEW.id, 'operation', 'insert'), UNIX_TIMESTAMP());
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_chat_essence_insert
AFTER INSERT ON chat_essence
FOR EACH ROW
BEGIN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('group.essence_changed', 'group', 0, 0, NEW.room_id,
        JSON_OBJECT('room_id', NEW.room_id, 'entity_id', NEW.msg_id, 'operation', 'insert'), UNIX_TIMESTAMP());
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_chat_group_admin_insert
AFTER INSERT ON chat_group_admin
FOR EACH ROW
BEGIN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('group.roles_changed', 'group', 0, 0, NEW.room_id,
        JSON_OBJECT('room_id', NEW.room_id, 'entity_id', NEW.uid, 'operation', 'insert'), UNIX_TIMESTAMP());
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_chat_room_apply_insert
AFTER INSERT ON chat_room_apply
FOR EACH ROW
BEGIN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('group.application_changed', 'group_admin', 0, 0, NEW.room_id,
        JSON_OBJECT('room_id', NEW.room_id, 'entity_id', NEW.id, 'operation', 'insert'), UNIX_TIMESTAMP());
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('group.application_changed', 'user', NEW.uid, 0, NEW.room_id,
        JSON_OBJECT('room_id', NEW.room_id, 'entity_id', NEW.id, 'status', NEW.status, 'operation', 'insert'), UNIX_TIMESTAMP());
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_chat_room_transfer_insert
AFTER INSERT ON chat_room_transfer
FOR EACH ROW
BEGIN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('group.transfer_changed', 'group', 0, 0, NEW.room_id,
        JSON_OBJECT('room_id', NEW.room_id, 'entity_id', NEW.id, 'operation', 'insert'), UNIX_TIMESTAMP());
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_space_shc_insert
AFTER INSERT ON space_shc
FOR EACH ROW
BEGIN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('space.changed', 'contacts', IF(NEW.is_reply = 1, COALESCE((SELECT sender_uid FROM space_shc WHERE cont_id = NEW.reply_id), NEW.sender_uid), NEW.sender_uid), 0, 0,
        JSON_OBJECT('post_id', IF(NEW.is_reply = 1, NEW.reply_id, NEW.cont_id), 'entity_id', NEW.cont_id, 'operation', 'insert'), UNIX_TIMESTAMP());
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_chat_msg_update
AFTER UPDATE ON chat_msg
FOR EACH ROW
BEGIN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('message.updated', 'group', 0, 0, NEW.room_id,
        JSON_OBJECT('msg_id', NEW.id, 'room_id', NEW.room_id, 'uid', NEW.uid, 'msg_type', NEW.msg_type), UNIX_TIMESTAMP());
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_private_msg_update
AFTER UPDATE ON private_msg
FOR EACH ROW
BEGIN
    IF NEW.type = 'private' THEN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('message.updated', 'pair', NEW.from_uid, NEW.to_uid, 0,
        JSON_OBJECT('msg_id', NEW.id, 'from_uid', NEW.from_uid, 'to_uid', NEW.to_uid, 'is_read', NEW.is_read, 'msg_type', NEW.msg_type), UNIX_TIMESTAMP());
    END IF;
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_chat_user_notice_update
AFTER UPDATE ON chat_user_notice
FOR EACH ROW
BEGIN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('notification.updated', 'user', NEW.uid, 0, 0,
        JSON_OBJECT('notice_id', NEW.id, 'is_read', NEW.is_read, 'operation', 'update'), UNIX_TIMESTAMP());
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_friend_request_update
AFTER UPDATE ON friend_request
FOR EACH ROW
BEGIN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('friend.request_changed', 'pair', NEW.from_uid, NEW.to_uid, 0,
        JSON_OBJECT('request_id', NEW.id, 'from_uid', NEW.from_uid, 'to_uid', NEW.to_uid, 'status', NEW.status, 'operation', 'update'), UNIX_TIMESTAMP());
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_friend_relation_update
AFTER UPDATE ON friend_relation
FOR EACH ROW
BEGIN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('friend.changed', 'pair', NEW.uid1, NEW.uid2, 0,
        JSON_OBJECT('uid1', NEW.uid1, 'uid2', NEW.uid2, 'status', NEW.status, 'operation', 'update'), UNIX_TIMESTAMP());
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_group_files_update
AFTER UPDATE ON group_files
FOR EACH ROW
BEGIN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('group.files_changed', 'group', 0, 0, NEW.room_id,
        JSON_OBJECT('room_id', NEW.room_id, 'entity_id', NEW.id, 'operation', 'update'), UNIX_TIMESTAMP());
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_chat_essence_update
AFTER UPDATE ON chat_essence
FOR EACH ROW
BEGIN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('group.essence_changed', 'group', 0, 0, NEW.room_id,
        JSON_OBJECT('room_id', NEW.room_id, 'entity_id', NEW.msg_id, 'operation', 'update'), UNIX_TIMESTAMP());
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_chat_group_admin_update
AFTER UPDATE ON chat_group_admin
FOR EACH ROW
BEGIN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('group.roles_changed', 'group', 0, 0, NEW.room_id,
        JSON_OBJECT('room_id', NEW.room_id, 'entity_id', NEW.uid, 'operation', 'update'), UNIX_TIMESTAMP());
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_chat_room_apply_update
AFTER UPDATE ON chat_room_apply
FOR EACH ROW
BEGIN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('group.application_changed', 'group_admin', 0, 0, NEW.room_id,
        JSON_OBJECT('room_id', NEW.room_id, 'entity_id', NEW.id, 'operation', 'update'), UNIX_TIMESTAMP());
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('group.application_changed', 'user', NEW.uid, 0, NEW.room_id,
        JSON_OBJECT('room_id', NEW.room_id, 'entity_id', NEW.id, 'status', NEW.status, 'operation', 'update'), UNIX_TIMESTAMP());
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_chat_room_transfer_update
AFTER UPDATE ON chat_room_transfer
FOR EACH ROW
BEGIN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('group.transfer_changed', 'group', 0, 0, NEW.room_id,
        JSON_OBJECT('room_id', NEW.room_id, 'entity_id', NEW.id, 'operation', 'update'), UNIX_TIMESTAMP());
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_space_shc_update
AFTER UPDATE ON space_shc
FOR EACH ROW
BEGIN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('space.changed', 'contacts', IF(NEW.is_reply = 1, COALESCE((SELECT sender_uid FROM space_shc WHERE cont_id = NEW.reply_id), NEW.sender_uid), NEW.sender_uid), 0, 0,
        JSON_OBJECT('post_id', IF(NEW.is_reply = 1, NEW.reply_id, NEW.cont_id), 'entity_id', NEW.cont_id, 'operation', 'update'), UNIX_TIMESTAMP());
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_chat_msg_delete
AFTER DELETE ON chat_msg
FOR EACH ROW
BEGIN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('message.deleted', 'group', 0, 0, OLD.room_id,
        JSON_OBJECT('msg_id', OLD.id, 'room_id', OLD.room_id, 'uid', OLD.uid, 'msg_type', OLD.msg_type), UNIX_TIMESTAMP());
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_private_msg_delete
AFTER DELETE ON private_msg
FOR EACH ROW
BEGIN
    IF OLD.type = 'private' THEN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('message.deleted', 'pair', OLD.from_uid, OLD.to_uid, 0,
        JSON_OBJECT('msg_id', OLD.id, 'from_uid', OLD.from_uid, 'to_uid', OLD.to_uid, 'is_read', OLD.is_read, 'msg_type', OLD.msg_type), UNIX_TIMESTAMP());
    END IF;
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_chat_user_notice_delete
AFTER DELETE ON chat_user_notice
FOR EACH ROW
BEGIN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('notification.deleted', 'user', OLD.uid, 0, 0,
        JSON_OBJECT('notice_id', OLD.id, 'is_read', OLD.is_read, 'operation', 'delete'), UNIX_TIMESTAMP());
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_friend_request_delete
AFTER DELETE ON friend_request
FOR EACH ROW
BEGIN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('friend.request_changed', 'pair', OLD.from_uid, OLD.to_uid, 0,
        JSON_OBJECT('request_id', OLD.id, 'from_uid', OLD.from_uid, 'to_uid', OLD.to_uid, 'status', OLD.status, 'operation', 'delete'), UNIX_TIMESTAMP());
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_friend_relation_delete
AFTER DELETE ON friend_relation
FOR EACH ROW
BEGIN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('friend.changed', 'pair', OLD.uid1, OLD.uid2, 0,
        JSON_OBJECT('uid1', OLD.uid1, 'uid2', OLD.uid2, 'status', OLD.status, 'operation', 'delete'), UNIX_TIMESTAMP());
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_group_files_delete
AFTER DELETE ON group_files
FOR EACH ROW
BEGIN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('group.files_changed', 'group', 0, 0, OLD.room_id,
        JSON_OBJECT('room_id', OLD.room_id, 'entity_id', OLD.id, 'operation', 'delete'), UNIX_TIMESTAMP());
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_chat_essence_delete
AFTER DELETE ON chat_essence
FOR EACH ROW
BEGIN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('group.essence_changed', 'group', 0, 0, OLD.room_id,
        JSON_OBJECT('room_id', OLD.room_id, 'entity_id', OLD.msg_id, 'operation', 'delete'), UNIX_TIMESTAMP());
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_chat_group_admin_delete
AFTER DELETE ON chat_group_admin
FOR EACH ROW
BEGIN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('group.roles_changed', 'group', 0, 0, OLD.room_id,
        JSON_OBJECT('room_id', OLD.room_id, 'entity_id', OLD.uid, 'operation', 'delete'), UNIX_TIMESTAMP());
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_chat_room_apply_delete
AFTER DELETE ON chat_room_apply
FOR EACH ROW
BEGIN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('group.application_changed', 'group_admin', 0, 0, OLD.room_id,
        JSON_OBJECT('room_id', OLD.room_id, 'entity_id', OLD.id, 'operation', 'delete'), UNIX_TIMESTAMP());
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('group.application_changed', 'user', OLD.uid, 0, OLD.room_id,
        JSON_OBJECT('room_id', OLD.room_id, 'entity_id', OLD.id, 'status', OLD.status, 'operation', 'delete'), UNIX_TIMESTAMP());
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_chat_room_transfer_delete
AFTER DELETE ON chat_room_transfer
FOR EACH ROW
BEGIN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('group.transfer_changed', 'group', 0, 0, OLD.room_id,
        JSON_OBJECT('room_id', OLD.room_id, 'entity_id', OLD.id, 'operation', 'delete'), UNIX_TIMESTAMP());
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_space_shc_delete
AFTER DELETE ON space_shc
FOR EACH ROW
BEGIN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('space.changed', 'contacts', IF(OLD.is_reply = 1, COALESCE((SELECT sender_uid FROM space_shc WHERE cont_id = OLD.reply_id), OLD.sender_uid), OLD.sender_uid), 0, 0,
        JSON_OBJECT('post_id', IF(OLD.is_reply = 1, OLD.reply_id, OLD.cont_id), 'entity_id', OLD.cont_id, 'operation', 'delete'), UNIX_TIMESTAMP());
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_chat_group_user_insert
AFTER INSERT ON chat_group_user
FOR EACH ROW
BEGIN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('group.members_changed', 'group', 0, 0, NEW.room_id,
        JSON_OBJECT('room_id', NEW.room_id, 'uid', NEW.uid, 'operation', 'joined'), UNIX_TIMESTAMP());
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_chat_group_user_delete
AFTER DELETE ON chat_group_user
FOR EACH ROW
BEGIN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('group.members_changed', 'group', 0, 0, OLD.room_id,
        JSON_OBJECT('room_id', OLD.room_id, 'uid', OLD.uid, 'operation', 'left'), UNIX_TIMESTAMP());
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('group.members_changed', 'user', OLD.uid, 0, OLD.room_id,
        JSON_OBJECT('room_id', OLD.room_id, 'uid', OLD.uid, 'operation', 'removed'), UNIX_TIMESTAMP());
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_chat_group_user_update
AFTER UPDATE ON chat_group_user
FOR EACH ROW
BEGIN
    IF NOT (OLD.last_read_msg_id <=> NEW.last_read_msg_id) THEN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('conversation.read', 'user', NEW.uid, 0, NEW.room_id,
        JSON_OBJECT('room_id', NEW.room_id, 'uid', NEW.uid, 'last_msg_id', NEW.last_read_msg_id), UNIX_TIMESTAMP());
    END IF;
    IF NOT (OLD.mute_until <=> NEW.mute_until) OR NOT (OLD.title <=> NEW.title) OR NOT (OLD.level <=> NEW.level) OR NOT (OLD.title_custom <=> NEW.title_custom) OR NOT (OLD.level_custom <=> NEW.level_custom) THEN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('group.members_changed', 'group', 0, 0, NEW.room_id,
        JSON_OBJECT('room_id', NEW.room_id, 'uid', NEW.uid, 'operation', 'updated'), UNIX_TIMESTAMP());
    END IF;
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_chat_room_insert
AFTER INSERT ON chat_room
FOR EACH ROW
BEGIN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('group.created', 'user', NEW.owner_uid, 0, NEW.id,
        JSON_OBJECT('room_id', NEW.id), UNIX_TIMESTAMP());
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_chat_room_update
AFTER UPDATE ON chat_room
FOR EACH ROW
BEGIN
    IF OLD.is_disband = 0 AND NEW.is_disband <> 0 THEN
    INSERT INTO csac_realtime_outbox (event_type, audience, owner_uid, room_id, payload, created_at)
    SELECT 'group.disbanded', 'user', uid, NEW.id, JSON_OBJECT('room_id', NEW.id), UNIX_TIMESTAMP()
    FROM chat_group_user WHERE room_id = NEW.id;
    ELSE
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('group.updated', 'group', 0, 0, NEW.id,
        JSON_OBJECT('room_id', NEW.id), UNIX_TIMESTAMP());
    END IF;
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_chat_room_delete
AFTER DELETE ON chat_room
FOR EACH ROW
BEGIN
    INSERT INTO csac_realtime_outbox (event_type, audience, owner_uid, room_id, payload, created_at)
    SELECT 'group.disbanded', 'user', uid, OLD.id, JSON_OBJECT('room_id', OLD.id), UNIX_TIMESTAMP()
    FROM chat_group_user WHERE room_id = OLD.id;
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_chat_user_update
AFTER UPDATE ON chat_user
FOR EACH ROW
BEGIN
    IF NOT (OLD.nickname <=> NEW.nickname) OR NOT (OLD.avatar <=> NEW.avatar) OR NOT (OLD.ban_until <=> NEW.ban_until) OR NOT (OLD.status <=> NEW.status) OR NOT (OLD.theme_color <=> NEW.theme_color) OR NOT (OLD.allow_auto_join <=> NEW.allow_auto_join) OR NOT (OLD.pat_action <=> NEW.pat_action) OR NOT (OLD.email <=> NEW.email) OR NOT (OLD.hide_conv <=> NEW.hide_conv) THEN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('user.updated', 'user', NEW.id, 0, 0,
        JSON_OBJECT('uid', NEW.id), UNIX_TIMESTAMP());
    END IF;
    IF NOT (OLD.nickname <=> NEW.nickname) OR NOT (OLD.avatar <=> NEW.avatar) THEN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('profile.updated', 'peers', NEW.id, 0, 0,
        JSON_OBJECT('uid', NEW.id), UNIX_TIMESTAMP());
    END IF;
END

-- csac:statement

CREATE TRIGGER IF NOT EXISTS csac_rt_v1_csac_sessions_delete
AFTER DELETE ON csac_sessions
FOR EACH ROW
BEGIN
    IF OLD.uid > 0 THEN
    INSERT INTO csac_realtime_outbox
        (event_type, audience, owner_uid, peer_uid, room_id, payload, created_at)
    VALUES ('session.revoked', 'user', OLD.uid, 0, 0,
        JSON_OBJECT('session_hash', SHA2(OLD.sid, 256)), UNIX_TIMESTAMP());
    END IF;
END
