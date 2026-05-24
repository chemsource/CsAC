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
-- 管理员令牌表
CREATE TABLE IF NOT EXISTS `admin_tokens` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `token` varchar(512) NOT NULL,
  `created_at` int(11) NOT NULL,
  `expires_at` int(11) NOT NULL,
  `used` tinyint(1) DEFAULT 0,
  `ip_address` varchar(45) DEFAULT NULL,
  `user_agent` varchar(500) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `token` (`token`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8mb4;

-- 精华消息表
CREATE TABLE IF NOT EXISTS `chat_essence` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `msg_id` int(11) NOT NULL,
  `room_id` int(11) NOT NULL,
  `set_uid` int(11) NOT NULL,
  `set_nick` varchar(30) NOT NULL,
  `set_time` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `msg_id` (`msg_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 群管理员表
CREATE TABLE IF NOT EXISTS `chat_group_admin` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `room_id` int(11) NOT NULL,
  `uid` int(11) NOT NULL,
  `add_time` int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_room_admin` (`room_id`,`uid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 群成员表
CREATE TABLE IF NOT EXISTS `chat_group_user` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `room_id` int(11) NOT NULL,
  `uid` int(11) NOT NULL,
  `join_time` datetime NOT NULL DEFAULT current_timestamp(),
  `mute_until` int(11) DEFAULT 0,
  `last_read_msg_id` int(11) DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_room_uid` (`room_id`,`uid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 群聊消息表
CREATE TABLE IF NOT EXISTS `chat_msg` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `reply_to` int(11) DEFAULT NULL,
  `mention_uids` varchar(200) DEFAULT NULL,
  `room_id` int(11) NOT NULL,
  `uid` int(11) NOT NULL,
  `nickname` varchar(30) NOT NULL,
  `content` text NOT NULL,
  `add_time` datetime NOT NULL,
  `msg_type` tinyint(1) DEFAULT 1 COMMENT '1文字 2图片 3语音',
  `is_essence` tinyint(1) NOT NULL DEFAULT 0,
  `voice_duration` int(11) DEFAULT 0,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 举报表
CREATE TABLE IF NOT EXISTS `chat_report` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `reporter_uid` int(11) NOT NULL,
  `report_type` enum('user','group') NOT NULL,
  `target_id` int(11) NOT NULL,
  `target_name` varchar(100) DEFAULT NULL,
  `reason` text NOT NULL,
  `is_anonymous` tinyint(1) DEFAULT 0,
  `status` enum('pending','processing','resolved') DEFAULT 'pending',
  `admin_reply` text DEFAULT NULL,
  `add_time` int(11) NOT NULL,
  `process_time` int(11) DEFAULT 0,
  PRIMARY KEY (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8mb4;

-- 群组表
CREATE TABLE IF NOT EXISTS `chat_room` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `room_name` varchar(50) NOT NULL,
  `owner_uid` int(11) NOT NULL,
  `intro` text DEFAULT '',
  `notice` varchar(500) DEFAULT '',
  `invite_code` varchar(32) NOT NULL,
  `show_in_list` tinyint(1) NOT NULL DEFAULT 1,
  `join_type` tinyint(1) DEFAULT 2 COMMENT '1直接 2邀请码 3固定码 4审核',
  `fixed_code` varchar(32) DEFAULT '',
  `ask_question` varchar(100) DEFAULT '',
  `ask_answer` varchar(100) DEFAULT '',
  `owner_transfer_cd` int(11) DEFAULT 0,
  `is_disband` tinyint(1) DEFAULT 0,
  `disband_time` int(11) DEFAULT 0,
  `allow_invite` tinyint(1) DEFAULT 1,
  `ban_until` int(11) DEFAULT 0,
  `ban_reason` varchar(500) DEFAULT '',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 入群申请表
CREATE TABLE IF NOT EXISTS `chat_room_apply` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `room_id` int(11) NOT NULL,
  `uid` int(11) NOT NULL,
  `apply_type` tinyint(1) NOT NULL,
  `answer_content` varchar(200) DEFAULT '',
  `apply_time` datetime NOT NULL DEFAULT current_timestamp(),
  `status` tinyint(1) DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_room_uid` (`room_id`,`uid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 群转让记录表
CREATE TABLE IF NOT EXISTS `chat_room_transfer` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `room_id` int(11) NOT NULL,
  `old_owner` int(11) NOT NULL,
  `new_owner` int(11) NOT NULL,
  `create_time` datetime NOT NULL DEFAULT current_timestamp(),
  `status` tinyint(1) DEFAULT 0 COMMENT '0待同意 1同意 2拒绝 3过期',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 用户表
CREATE TABLE IF NOT EXISTS `chat_user` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `username` varchar(30) NOT NULL,
  `nickname` varchar(30) NOT NULL,
  `pwd` varchar(64) NOT NULL,
  `add_time` int(11) NOT NULL,
  `avatar` varchar(255) DEFAULT '',
  `is_first_login` tinyint(1) DEFAULT 1,
  `last_active` int(11) NOT NULL DEFAULT 0,
  `ban_until` int(11) DEFAULT 0,
  `ban_reason` varchar(500) DEFAULT '',
  `theme_color` varchar(7) NOT NULL DEFAULT '#409eff',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 用户通知表
CREATE TABLE IF NOT EXISTS `chat_user_notice` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `uid` int(11) NOT NULL,
  `title` varchar(100) NOT NULL,
  `content` text DEFAULT NULL,
  `link` varchar(255) DEFAULT NULL,
  `is_read` tinyint(1) DEFAULT 0,
  `add_time` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 好友关系表
CREATE TABLE IF NOT EXISTS `friend_relation` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `uid1` int(11) NOT NULL,
  `uid2` int(11) NOT NULL,
  `status` tinyint(1) NOT NULL DEFAULT 1 COMMENT '1好友 2删除中 3已删 4拉黑',
  `remark1` varchar(50) DEFAULT NULL,
  `remark2` varchar(50) DEFAULT NULL,
  `create_time` datetime NOT NULL,
  `update_time` datetime NOT NULL,
  `delete_time` datetime DEFAULT NULL,
  `delete_by` int(11) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_pair` (`uid1`,`uid2`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8mb4;

-- 好友请求表
CREATE TABLE IF NOT EXISTS `friend_request` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `from_uid` int(11) NOT NULL,
  `to_uid` int(11) NOT NULL,
  `type` tinyint(1) NOT NULL DEFAULT 1 COMMENT '1加好友 2恢复',
  `status` tinyint(1) NOT NULL DEFAULT 0 COMMENT '0待处理 1同意 2拒绝',
  `content` varchar(255) DEFAULT NULL,
  `create_time` datetime NOT NULL,
  `handle_time` datetime DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8mb4;

-- 私聊消息表
CREATE TABLE IF NOT EXISTS `private_msg` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `reply_to` int(11) DEFAULT NULL,
  `from_uid` int(11) NOT NULL,
  `to_uid` int(11) NOT NULL DEFAULT 0,
  `content` text DEFAULT NULL,
  `type` varchar(20) NOT NULL DEFAULT 'private',
  `created_at` int(11) NOT NULL,
  `is_read` tinyint(1) NOT NULL DEFAULT 0,
  `image_url` varchar(500) DEFAULT NULL,
  `voice_url` varchar(500) DEFAULT NULL,
  `duration` int(11) DEFAULT 0,
  `is_recalled` tinyint(1) DEFAULT 0,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```