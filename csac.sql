-- phpMyAdmin SQL Dump
-- version 5.2.3
-- https://www.phpmyadmin.net/
--
-- 生成日期： 2026-05-31 14:00:47
-- 服务器版本： 11.8.7-MariaDB-ubu2404
-- PHP 版本： 8.3.31

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- 表的结构 `admin_tokens`
--

CREATE TABLE `admin_tokens` (
  `id` int(11) NOT NULL,
  `token` varchar(512) NOT NULL,
  `created_at` int(11) NOT NULL,
  `expires_at` int(11) NOT NULL,
  `used` tinyint(1) DEFAULT 0,
  `ip_address` varchar(45) DEFAULT NULL,
  `user_agent` varchar(500) DEFAULT NULL
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- 表的结构 `chat_essence`
--

CREATE TABLE `chat_essence` (
  `id` int(11) NOT NULL,
  `msg_id` int(11) NOT NULL,
  `room_id` int(11) NOT NULL,
  `set_uid` int(11) NOT NULL,
  `set_nick` varchar(30) NOT NULL,
  `set_time` datetime NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

-- --------------------------------------------------------

--
-- 表的结构 `chat_group_admin`
--

CREATE TABLE `chat_group_admin` (
  `id` int(11) NOT NULL,
  `room_id` int(11) NOT NULL,
  `uid` int(11) NOT NULL,
  `add_time` int(11) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

-- --------------------------------------------------------

--
-- 表的结构 `chat_group_user`
--

CREATE TABLE `chat_group_user` (
  `id` int(11) NOT NULL,
  `room_id` int(11) NOT NULL,
  `uid` int(11) NOT NULL,
  `join_time` datetime NOT NULL DEFAULT current_timestamp(),
  `mute_until` int(11) DEFAULT 0,
  `last_read_msg_id` int(11) DEFAULT 0,
  `title` varchar(30) NOT NULL DEFAULT '青铜' COMMENT '头衔',
  `level` int(11) NOT NULL DEFAULT 1 COMMENT '等级',
  `title_custom` tinyint(1) NOT NULL DEFAULT 0,
  `level_custom` tinyint(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

-- --------------------------------------------------------

--
-- 表的结构 `chat_msg`
--

CREATE TABLE `chat_msg` (
  `id` int(11) NOT NULL,
  `reply_to` int(11) DEFAULT NULL,
  `mention_uids` varchar(200) DEFAULT NULL,
  `room_id` int(11) NOT NULL,
  `uid` int(11) NOT NULL,
  `nickname` varchar(30) NOT NULL COMMENT '发送人昵称',
  `content` text NOT NULL,
  `add_time` datetime NOT NULL,
  `msg_type` tinyint(1) DEFAULT 1 COMMENT '1=文字,2=图片,3=语音，4=拍一拍,5=表情包',
  `is_essence` tinyint(1) NOT NULL DEFAULT 0,
  `voice_duration` int(11) DEFAULT 0 COMMENT '语音时长(秒)',
  `was_replied` int(11) NOT NULL DEFAULT 0 COMMENT '0-未撤回；1-自己撤回；2-被管理员撤回；3-被群主撤回'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

-- --------------------------------------------------------

--
-- 表的结构 `chat_report`
--

CREATE TABLE `chat_report` (
  `id` int(11) NOT NULL,
  `reporter_uid` int(11) NOT NULL,
  `report_type` enum('user','group') NOT NULL,
  `target_id` int(11) NOT NULL,
  `target_name` varchar(100) DEFAULT NULL,
  `reason` text NOT NULL,
  `is_anonymous` tinyint(1) DEFAULT 0,
  `status` enum('pending','processing','resolved') DEFAULT 'pending',
  `admin_reply` text DEFAULT NULL,
  `add_time` int(11) NOT NULL,
  `process_time` int(11) DEFAULT 0
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- 表的结构 `chat_room`
--

CREATE TABLE `chat_room` (
  `id` int(11) NOT NULL,
  `room_name` varchar(50) NOT NULL,
  `owner_uid` int(11) NOT NULL COMMENT '群主ID',
  `intro` text DEFAULT '' COMMENT '群组简介',
  `notice` varchar(500) DEFAULT '',
  `invite_code` varchar(32) NOT NULL COMMENT '字母+数字邀请码',
  `show_in_list` tinyint(1) NOT NULL DEFAULT 1 COMMENT '是否在群组列表显示（1=显示，0=隐藏）',
  `join_type` tinyint(1) DEFAULT 2 COMMENT '1直接加入 2自动换码 3固定邀请码 4问答审核',
  `fixed_code` varchar(32) DEFAULT '' COMMENT '固定邀请码',
  `ask_question` varchar(100) DEFAULT '' COMMENT '入群问题',
  `ask_answer` varchar(100) DEFAULT '' COMMENT '入群答案',
  `owner_transfer_cd` int(11) DEFAULT 0 COMMENT '转让冷静期截止时间戳',
  `is_disband` tinyint(1) DEFAULT 0 COMMENT '0正常 1已解散',
  `disband_time` int(11) DEFAULT 0 COMMENT '解散时间戳',
  `allow_invite` tinyint(1) DEFAULT 1,
  `ban_until` int(11) DEFAULT 0 COMMENT '封禁截止时间戳，0表示未封禁',
  `ban_reason` varchar(500) DEFAULT '' COMMENT '封禁原因',
  `avatar` varchar(255) DEFAULT ''
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

-- --------------------------------------------------------

--
-- 表的结构 `chat_room_apply`
--

CREATE TABLE `chat_room_apply` (
  `id` int(11) NOT NULL,
  `room_id` int(11) NOT NULL,
  `uid` int(11) NOT NULL,
  `apply_type` tinyint(1) NOT NULL,
  `answer_content` varchar(200) DEFAULT '',
  `apply_time` datetime NOT NULL DEFAULT current_timestamp(),
  `status` tinyint(1) DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

-- --------------------------------------------------------

--
-- 表的结构 `chat_room_transfer`
--

CREATE TABLE `chat_room_transfer` (
  `id` int(11) NOT NULL,
  `room_id` int(11) NOT NULL,
  `old_owner` int(11) NOT NULL,
  `new_owner` int(11) NOT NULL,
  `create_time` datetime NOT NULL DEFAULT current_timestamp(),
  `status` tinyint(1) DEFAULT 0 COMMENT '0待同意 1同意 2拒绝 3过期'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

-- --------------------------------------------------------

--
-- 表的结构 `chat_user`
--

CREATE TABLE `chat_user` (
  `id` int(11) NOT NULL,
  `username` varchar(30) NOT NULL,
  `nickname` varchar(30) NOT NULL,
  `pwd` varchar(64) NOT NULL,
  `add_time` int(11) NOT NULL,
  `avatar` varchar(255) DEFAULT '',
  `email` varchar(255) DEFAULT NULL,
  `is_first_login` tinyint(1) DEFAULT 1 COMMENT '1=首次登录需看教程 0=已看过',
  `last_active` int(11) NOT NULL DEFAULT 0 COMMENT '最后活跃时间戳',
  `platform` varchar(100) NOT NULL DEFAULT 'none',
  `ban_until` int(11) DEFAULT 0 COMMENT '封禁截止时间戳，0表示未封禁',
  `ban_reason` varchar(500) DEFAULT '' COMMENT '封禁原因',
  `theme_color` varchar(7) NOT NULL DEFAULT '#409eff',
  `allow_auto_join` int(11) NOT NULL DEFAULT 0 COMMENT '是否允许邀请后自动入群',
  `pat_action` varchar(32) NOT NULL DEFAULT '拍了拍'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

-- --------------------------------------------------------

--
-- 表的结构 `register_email_codes`
--

CREATE TABLE `register_email_codes` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `email` varchar(255) NOT NULL,
  `code_hash` varchar(255) NOT NULL,
  `ip_hash` char(64) NOT NULL DEFAULT '',
  `attempts` tinyint(3) UNSIGNED NOT NULL DEFAULT 0,
  `used_at` int(11) NOT NULL DEFAULT 0,
  `expires_at` int(11) NOT NULL,
  `created_at` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- 表的结构 `chat_user_notice`
--

CREATE TABLE `chat_user_notice` (
  `id` int(11) NOT NULL,
  `uid` int(11) NOT NULL,
  `title` varchar(100) NOT NULL,
  `content` text DEFAULT NULL,
  `link` varchar(255) DEFAULT NULL,
  `is_read` tinyint(1) DEFAULT 0,
  `add_time` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

-- --------------------------------------------------------

--
-- 表的结构 `csac_channel`
--

CREATE TABLE `csac_channel` (
  `id` int(11) NOT NULL,
  `channel_name` varchar(50) NOT NULL,
  `channel_desc` varchar(200) DEFAULT '',
  `create_time` datetime DEFAULT current_timestamp()
) ENGINE=MyISAM DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- 表的结构 `csac_channel_msg`
--

CREATE TABLE `csac_channel_msg` (
  `id` int(11) NOT NULL,
  `channel_id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `username` varchar(30) NOT NULL,
  `msg` text NOT NULL,
  `send_time` varchar(30) NOT NULL
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- 表的结构 `csac_channel_user`
--

CREATE TABLE `csac_channel_user` (
  `id` int(11) NOT NULL,
  `channel_id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- 表的结构 `emoji_list`
--

CREATE TABLE `emoji_list` (
  `full_name` varchar(30) DEFAULT NULL COMMENT '全名，显示给用户',
  `abbr` varchar(5) NOT NULL COMMENT '缩写，用于快速输入',
  `address` varchar(255) DEFAULT NULL COMMENT '地址'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- --------------------------------------------------------

--
-- 表的结构 `friend_relation`
--

CREATE TABLE `friend_relation` (
  `id` int(11) NOT NULL,
  `uid1` int(11) NOT NULL COMMENT '用户1',
  `uid2` int(11) NOT NULL COMMENT '用户2',
  `status` tinyint(1) NOT NULL DEFAULT 1 COMMENT '1:正常好友 2:删除中(3天恢复期) 3:已删除 4:拉黑',
  `remark1` varchar(50) DEFAULT NULL COMMENT 'uid1对uid2的备注',
  `remark2` varchar(50) DEFAULT NULL COMMENT 'uid2对uid1的备注',
  `create_time` datetime NOT NULL,
  `update_time` datetime NOT NULL,
  `delete_time` datetime DEFAULT NULL COMMENT '删除时间',
  `delete_by` int(11) DEFAULT NULL COMMENT '操作者UID',
  `deleted_by` int(11) DEFAULT NULL,
  `remark` varchar(50) DEFAULT ''
) ENGINE=MyISAM DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- 表的结构 `friend_request`
--

CREATE TABLE `friend_request` (
  `id` int(11) NOT NULL,
  `from_uid` int(11) NOT NULL COMMENT '申请人',
  `to_uid` int(11) NOT NULL COMMENT '接收人',
  `type` tinyint(1) NOT NULL DEFAULT 1 COMMENT '1:加好友 2:恢复关系',
  `status` tinyint(1) NOT NULL DEFAULT 0 COMMENT '0:待处理 1:已同意 2:已拒绝',
  `content` varchar(255) DEFAULT NULL COMMENT '附加消息',
  `create_time` datetime NOT NULL,
  `handle_time` datetime DEFAULT NULL COMMENT '处理时间'
) ENGINE=MyISAM DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- 表的结构 `private_msg`
--

CREATE TABLE `private_msg` (
  `id` int(11) NOT NULL,
  `reply_to` int(11) DEFAULT NULL,
  `from_uid` int(11) NOT NULL COMMENT '发送者UID',
  `to_uid` int(11) NOT NULL DEFAULT 0 COMMENT '接收者UID',
  `content` text DEFAULT NULL,
  `type` varchar(20) NOT NULL DEFAULT 'private' COMMENT 'private=私聊, system=系统消息',
  `room_id` int(11) NOT NULL DEFAULT 0,
  `created_at` int(11) NOT NULL COMMENT 'Unix时间戳',
  `is_read` tinyint(1) NOT NULL DEFAULT 0,
  `image_url` varchar(500) DEFAULT NULL,
  `voice_url` varchar(500) DEFAULT NULL,
  `duration` int(11) DEFAULT 0,
  `is_recalled` tinyint(1) DEFAULT 0,
  `msg_type` tinyint(4) NOT NULL DEFAULT 1 COMMENT '消息类型：1文本 2图片 3语音 5表情包'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- 转储表的索引
--

--
-- 表的索引 `admin_tokens`
--
ALTER TABLE `admin_tokens`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `token` (`token`),
  ADD KEY `idx_token` (`token`),
  ADD KEY `idx_expires` (`expires_at`);

--
-- 表的索引 `chat_essence`
--
ALTER TABLE `chat_essence`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `msg_id` (`msg_id`);

--
-- 表的索引 `chat_group_admin`
--
ALTER TABLE `chat_group_admin`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_room_admin` (`room_id`,`uid`),
  ADD UNIQUE KEY `idx_room_uid` (`room_id`,`uid`);

--
-- 表的索引 `chat_group_user`
--
ALTER TABLE `chat_group_user`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_room_uid` (`room_id`,`uid`);

--
-- 表的索引 `chat_msg`
--
ALTER TABLE `chat_msg`
  ADD PRIMARY KEY (`id`);

--
-- 表的索引 `chat_report`
--
ALTER TABLE `chat_report`
  ADD PRIMARY KEY (`id`);

--
-- 表的索引 `chat_room`
--
ALTER TABLE `chat_room`
  ADD PRIMARY KEY (`id`);

--
-- 表的索引 `chat_room_apply`
--
ALTER TABLE `chat_room_apply`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_room_uid` (`room_id`,`uid`);

--
-- 表的索引 `chat_room_transfer`
--
ALTER TABLE `chat_room_transfer`
  ADD PRIMARY KEY (`id`);

--
-- 表的索引 `chat_user`
--
ALTER TABLE `chat_user`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uniq_csac_chat_user_email` (`email`);

--
-- 表的索引 `register_email_codes`
--
ALTER TABLE `register_email_codes`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_csac_register_email_created` (`email`,`created_at`),
  ADD KEY `idx_csac_register_ip_created` (`ip_hash`,`created_at`);

--
-- 表的索引 `chat_user_notice`
--
ALTER TABLE `chat_user_notice`
  ADD PRIMARY KEY (`id`);

--
-- 表的索引 `csac_channel`
--
ALTER TABLE `csac_channel`
  ADD PRIMARY KEY (`id`);

--
-- 表的索引 `csac_channel_msg`
--
ALTER TABLE `csac_channel_msg`
  ADD PRIMARY KEY (`id`);

--
-- 表的索引 `csac_channel_user`
--
ALTER TABLE `csac_channel_user`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `cid_uid` (`channel_id`,`user_id`);

--
-- 表的索引 `emoji_list`
--
ALTER TABLE `emoji_list`
  ADD PRIMARY KEY (`abbr`),
  ADD KEY `idx_abbr` (`abbr`);

--
-- 表的索引 `friend_relation`
--
ALTER TABLE `friend_relation`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_pair` (`uid1`,`uid2`),
  ADD UNIQUE KEY `unique_friend_pair` (`uid1`,`uid2`),
  ADD KEY `idx_uid1` (`uid1`),
  ADD KEY `idx_uid2` (`uid2`),
  ADD KEY `idx_status` (`status`),
  ADD KEY `idx_friend_relation_uid1_uid2` (`uid1`,`uid2`),
  ADD KEY `idx_friend_relation_status` (`status`),
  ADD KEY `idx_friend_relation_uid1` (`uid1`),
  ADD KEY `idx_friend_relation_uid2` (`uid2`);

--
-- 表的索引 `friend_request`
--
ALTER TABLE `friend_request`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_to_uid` (`to_uid`,`status`),
  ADD KEY `idx_from_uid` (`from_uid`),
  ADD KEY `idx_status` (`status`);

--
-- 表的索引 `private_msg`
--
ALTER TABLE `private_msg`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_from_to` (`from_uid`,`to_uid`),
  ADD KEY `idx_created` (`created_at`);

--
-- 在导出的表使用AUTO_INCREMENT
--

--
-- 使用表AUTO_INCREMENT `admin_tokens`
--
ALTER TABLE `admin_tokens`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `chat_essence`
--
ALTER TABLE `chat_essence`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `chat_group_admin`
--
ALTER TABLE `chat_group_admin`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `chat_group_user`
--
ALTER TABLE `chat_group_user`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `chat_msg`
--
ALTER TABLE `chat_msg`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `chat_report`
--
ALTER TABLE `chat_report`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `chat_room`
--
ALTER TABLE `chat_room`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `chat_room_apply`
--
ALTER TABLE `chat_room_apply`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `chat_room_transfer`
--
ALTER TABLE `chat_room_transfer`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `chat_user`
--
ALTER TABLE `chat_user`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `register_email_codes`
--
ALTER TABLE `register_email_codes`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `chat_user_notice`
--
ALTER TABLE `chat_user_notice`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `csac_channel`
--
ALTER TABLE `csac_channel`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `csac_channel_msg`
--
ALTER TABLE `csac_channel_msg`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `csac_channel_user`
--
ALTER TABLE `csac_channel_user`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `friend_relation`
--
ALTER TABLE `friend_relation`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `friend_request`
--
ALTER TABLE `friend_request`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `private_msg`
--
ALTER TABLE `private_msg`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
