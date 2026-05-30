# CsAC — Chemsource AtsukaCIT Chatting Online

**CsAC** 是一个开源的 Web 即时通讯系统，提供群聊、私聊、好友管理、精华消息、管理员封禁等完整功能。前端采用响应式设计，同时支持桌面端经典布局与移动端 Telegram 风格界面，后端基于 PHP + MySQL 实现，所有 API 通过统一入口 `/rpc/UniCsAC.php` 调用。

## ? 特性

- 用户注册 / 登录 / 资料管理
- 群组功能：创建群组、邀请码/口令/审核加入、成员管理、禁言、踢出、设置管理员
- 好友系统：添加好友、备注、拉黑、删除与恢复
- 即时消息：文字、图片、语音消息；支持回复和 @ 提及
- 精华消息：群主/管理员可设置/取消精华，自动统计排行
- 系统通知：好友请求、群组申请、举报反馈等
- 深色/浅色主题自适应，移动端独立样式
- 管理员后台：用户/群组封禁管理（临时令牌机制）
- 完整的 RESTful API，便于第三方客户端接入

## ?? 技术栈

| 层         | 技术                                 |
|-----------|--------------------------------------|
| 前端       | HTML5, CSS3, 原生 JavaScript (ES6)   |
| 后端       | PHP 7.2+ (原生 MySQLi)               |
| 数据库     | MySQL / MariaDB                      |
| 会话管理   | PHP Session + Cookie                 |
| 文件存储   | 本地目录 (`upload/`, `uploads/chat`) |

## ?? 安装部署

### 环境要求
- PHP 7.2 或更高版本（需启用 `mysqli`、`session`、`fileinfo`、`json` 扩展）
- MySQL 5.7 或 MariaDB 10.2+
- 服务器需支持 `.htaccess` 或可配置 PATH_INFO（用于路由）

### 快速安装

1. 将项目所有文件上传至网站根目录（例如 `/csac/`）。
2. 确保以下目录可写：
   - `/rpc/`
   - `/upload/` 及其子目录
   - `/uploads/chat/`
3. 按照文档末尾附录中的命令创建数据库
4. 修改core.php中的数据库配置为自己的数据库，跨域请求为自己的地址
5. 注册管理员账号，确保管理员账号uid为1

## ?? 文档

- **API 文档（开发者）**  
  - HTML 格式：`/doc/UniCsAC_API.html`  
  - Markdown 格式：`/docs/UniCsAC_API.md`
- **安装指南**：参见本文档“安装部署”章节
- **前端代码说明**：`/css/` 和 `/js/` 内已添加必要注释

## ?? 使用许可与著作权

本程序是 **Chemsource AtsukaCIT Chatting Online (CsAC)** 的 Web 版本。

- 你可以自由使用、修改、复制、分发本软件。
- 允许将本软件用于商业用途，也允许将其包含在闭源的商业产品中。
- **唯一限制**：你必须在软件的显著位置（如关于页面、文档或源代码注释中）保留原始作者信息（例如 “Powered by CsAC” 或 “Original author: Chemsource AtsukaCIT”）。

建议在代码仓库中保留 `LICENSE` 文件（如 MIT + 署名声明），以明确法律条款。

## ?? 贡献

欢迎提交 Issue、Pull Request 或功能建议。请确保代码风格与现有项目保持一致，并更新相关文档。

## ?? 联系方式

- 项目主页：https://csac.ccccocccc.cc
- 官方版本：https://cschat.ccccocccc.cc
- 作者 / 维护者：Chemsource Studio
- 问题反馈：
    1. 通过 GitHub Issues 
    2. 网站内的“Bug反馈”功能
    3. 邮箱 swcsstudio@126.com
    4. B站@Chemsource化源工作室
    5. QQ群：1103519538

---

## 附录：SQL创建命令
```
-- 设置字符集和时区
SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

-- 创建数据库（如果不存在）
CREATE DATABASE IF NOT EXISTS `csac` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci;
USE `csac`;

-- 表结构：admin_tokens
CREATE TABLE `admin_tokens` (
  `id` int(11) NOT NULL,
  `token` varchar(512) NOT NULL,
  `created_at` int(11) NOT NULL,
  `expires_at` int(11) NOT NULL,
  `used` tinyint(1) DEFAULT 0,
  `ip_address` varchar(45) DEFAULT NULL,
  `user_agent` varchar(500) DEFAULT NULL
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- 表结构：chat_essence
CREATE TABLE `chat_essence` (
  `id` int(11) NOT NULL,
  `msg_id` int(11) NOT NULL,
  `room_id` int(11) NOT NULL,
  `set_uid` int(11) NOT NULL,
  `set_nick` varchar(30) NOT NULL,
  `set_time` datetime NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

-- 表结构：chat_group_admin
CREATE TABLE `chat_group_admin` (
  `id` int(11) NOT NULL,
  `room_id` int(11) NOT NULL,
  `uid` int(11) NOT NULL,
  `add_time` int(11) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

-- 表结构：chat_group_user
CREATE TABLE `chat_group_user` (
  `id` int(11) NOT NULL,
  `room_id` int(11) NOT NULL,
  `uid` int(11) NOT NULL,
  `join_time` datetime NOT NULL DEFAULT current_timestamp(),
  `mute_until` int(11) DEFAULT 0,
  `last_read_msg_id` int(11) DEFAULT 0,
  `title` varchar(30) NOT NULL DEFAULT '青铜' COMMENT '头衔',
  `level` int(11) NOT NULL DEFAULT 1 COMMENT '等级',
  `title_custom` tinyint(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

-- 表结构：chat_msg
CREATE TABLE `chat_msg` (
  `id` int(11) NOT NULL,
  `reply_to` int(11) DEFAULT NULL,
  `mention_uids` varchar(200) DEFAULT NULL,
  `room_id` int(11) NOT NULL,
  `uid` int(11) NOT NULL,
  `nickname` varchar(30) NOT NULL COMMENT '发送人昵称',
  `content` text NOT NULL,
  `add_time` datetime NOT NULL,
  `msg_type` tinyint(1) DEFAULT 1 COMMENT '1=文字,2=图片,3=语音，4=拍一拍',
  `is_essence` tinyint(1) NOT NULL DEFAULT 0,
  `voice_duration` int(11) DEFAULT 0 COMMENT '语音时长(秒)',
  `was_replied` int(11) NOT NULL DEFAULT 0 COMMENT '0-未撤回；1-自己撤回；2-被管理员撤回；3-被群主撤回'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

-- 表结构：chat_report
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

-- 表结构：chat_room
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

-- 表结构：chat_room_apply
CREATE TABLE `chat_room_apply` (
  `id` int(11) NOT NULL,
  `room_id` int(11) NOT NULL,
  `uid` int(11) NOT NULL,
  `apply_type` tinyint(1) NOT NULL,
  `answer_content` varchar(200) DEFAULT '',
  `apply_time` datetime NOT NULL DEFAULT current_timestamp(),
  `status` tinyint(1) DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

-- 表结构：chat_room_transfer
CREATE TABLE `chat_room_transfer` (
  `id` int(11) NOT NULL,
  `room_id` int(11) NOT NULL,
  `old_owner` int(11) NOT NULL,
  `new_owner` int(11) NOT NULL,
  `create_time` datetime NOT NULL DEFAULT current_timestamp(),
  `status` tinyint(1) DEFAULT 0 COMMENT '0待同意 1同意 2拒绝 3过期'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

-- 表结构：chat_user
CREATE TABLE `chat_user` (
  `id` int(11) NOT NULL,
  `username` varchar(30) NOT NULL,
  `nickname` varchar(30) NOT NULL,
  `pwd` varchar(64) NOT NULL,
  `add_time` int(11) NOT NULL,
  `avatar` varchar(255) DEFAULT '',
  `is_first_login` tinyint(1) DEFAULT 1 COMMENT '1=首次登录需看教程 0=已看过',
  `last_active` int(11) NOT NULL DEFAULT 0 COMMENT '最后活动时间戳',
  `ban_until` int(11) DEFAULT 0 COMMENT '封禁截止时间戳，0表示未封禁',
  `ban_reason` varchar(500) DEFAULT '' COMMENT '封禁原因',
  `theme_color` varchar(7) NOT NULL DEFAULT '#409eff',
  `allow_auto_join` int(11) NOT NULL DEFAULT 0 COMMENT '是否允许邀请后自动入群',
  `pat_action` varchar(32) NOT NULL DEFAULT '拍了拍'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

-- 表结构：chat_user_notice
CREATE TABLE `chat_user_notice` (
  `id` int(11) NOT NULL,
  `uid` int(11) NOT NULL,
  `title` varchar(100) NOT NULL,
  `content` text DEFAULT NULL,
  `link` varchar(255) DEFAULT NULL,
  `is_read` tinyint(1) DEFAULT 0,
  `add_time` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

-- 表结构：csac_channel
CREATE TABLE `csac_channel` (
  `id` int(11) NOT NULL,
  `channel_name` varchar(50) NOT NULL,
  `channel_desc` varchar(200) DEFAULT '',
  `create_time` datetime DEFAULT current_timestamp()
) ENGINE=MyISAM DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- 表结构：csac_channel_msg
CREATE TABLE `csac_channel_msg` (
  `id` int(11) NOT NULL,
  `channel_id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `username` varchar(30) NOT NULL,
  `msg` text NOT NULL,
  `send_time` varchar(30) NOT NULL
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- 表结构：csac_channel_user
CREATE TABLE `csac_channel_user` (
  `id` int(11) NOT NULL,
  `channel_id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- 表结构：friend_relation
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

-- 表结构：friend_request
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

-- 表结构：private_msg
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
  `is_recalled` tinyint(1) DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- 添加所有表的索引和主键
ALTER TABLE `admin_tokens` ADD PRIMARY KEY (`id`), ADD UNIQUE KEY `token` (`token`), ADD KEY `idx_token` (`token`), ADD KEY `idx_expires` (`expires_at`);
ALTER TABLE `chat_essence` ADD PRIMARY KEY (`id`), ADD UNIQUE KEY `msg_id` (`msg_id`);
ALTER TABLE `chat_group_admin` ADD PRIMARY KEY (`id`), ADD UNIQUE KEY `uk_room_admin` (`room_id`,`uid`), ADD UNIQUE KEY `idx_room_uid` (`room_id`,`uid`);
ALTER TABLE `chat_group_user` ADD PRIMARY KEY (`id`), ADD UNIQUE KEY `uk_room_uid` (`room_id`,`uid`);
ALTER TABLE `chat_msg` ADD PRIMARY KEY (`id`);
ALTER TABLE `chat_report` ADD PRIMARY KEY (`id`);
ALTER TABLE `chat_room` ADD PRIMARY KEY (`id`);
ALTER TABLE `chat_room_apply` ADD PRIMARY KEY (`id`), ADD UNIQUE KEY `uk_room_uid` (`room_id`,`uid`);
ALTER TABLE `chat_room_transfer` ADD PRIMARY KEY (`id`);
ALTER TABLE `chat_user` ADD PRIMARY KEY (`id`);
ALTER TABLE `chat_user_notice` ADD PRIMARY KEY (`id`);
ALTER TABLE `csac_channel` ADD PRIMARY KEY (`id`);
ALTER TABLE `csac_channel_msg` ADD PRIMARY KEY (`id`);
ALTER TABLE `csac_channel_user` ADD PRIMARY KEY (`id`), ADD UNIQUE KEY `cid_uid` (`channel_id`,`user_id`);
ALTER TABLE `friend_relation` ADD PRIMARY KEY (`id`), ADD UNIQUE KEY `unique_pair` (`uid1`,`uid2`), ADD UNIQUE KEY `unique_friend_pair` (`uid1`,`uid2`), ADD KEY `idx_uid1` (`uid1`), ADD KEY `idx_uid2` (`uid2`), ADD KEY `idx_status` (`status`), ADD KEY `idx_friend_relation_uid1_uid2` (`uid1`,`uid2`), ADD KEY `idx_friend_relation_status` (`status`), ADD KEY `idx_friend_relation_uid1` (`uid1`), ADD KEY `idx_friend_relation_uid2` (`uid2`);
ALTER TABLE `friend_request` ADD PRIMARY KEY (`id`), ADD KEY `idx_to_uid` (`to_uid`,`status`), ADD KEY `idx_from_uid` (`from_uid`), ADD KEY `idx_status` (`status`);
ALTER TABLE `private_msg` ADD PRIMARY KEY (`id`), ADD KEY `idx_from_to` (`from_uid`,`to_uid`), ADD KEY `idx_created` (`created_at`);

-- 设置 AUTO_INCREMENT（初始为当前最大值，这里按原文件设为自动递增，无具体起始值则从1开始）
ALTER TABLE `admin_tokens` MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
ALTER TABLE `chat_essence` MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
ALTER TABLE `chat_group_admin` MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
ALTER TABLE `chat_group_user` MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
ALTER TABLE `chat_msg` MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
ALTER TABLE `chat_report` MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
ALTER TABLE `chat_room` MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
ALTER TABLE `chat_room_apply` MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
ALTER TABLE `chat_room_transfer` MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
ALTER TABLE `chat_user` MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
ALTER TABLE `chat_user_notice` MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
ALTER TABLE `csac_channel` MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
ALTER TABLE `csac_channel_msg` MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
ALTER TABLE `csac_channel_user` MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
ALTER TABLE `friend_relation` MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
ALTER TABLE `friend_request` MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
ALTER TABLE `private_msg` MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
```
