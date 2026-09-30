-- phpMyAdmin SQL Dump
-- version 5.2.3
-- https://www.phpmyadmin.net/
--
-- 主机： 1Panel-mariadb-xk9r
-- 生成日期： 2026-06-24 14:38:33
-- 服务器版本： 11.8.8-MariaDB-ubu2404
-- PHP 版本： 8.3.31

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- 数据库： `csac`
--

-- --------------------------------------------------------

--
-- 表的结构 `acr_uploads`
--

CREATE TABLE `acr_uploads` (
  `id` int(11) NOT NULL,
  `dev_id` int(11) NOT NULL COMMENT '上传者open_dev_accounts.id',
  `file_name` varchar(255) NOT NULL COMMENT 'ACR文件名',
  `file_type` varchar(10) NOT NULL DEFAULT 'acr' COMMENT 'acr 或 acrg',
  `content` mediumtext NOT NULL COMMENT 'ACR文件内容',
  `status` tinyint(4) NOT NULL DEFAULT 0 COMMENT '0=待审 1=通过 2=拒绝',
  `admin_note` text DEFAULT NULL COMMENT '管理员备注',
  `created_at` int(11) NOT NULL,
  `reviewed_at` int(11) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

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
-- 表的结构 `bot_accounts`
--

CREATE TABLE `bot_accounts` (
  `id` int(11) NOT NULL,
  `uid` int(11) NOT NULL COMMENT '关联chat_user.id',
  `dev_id` int(11) NOT NULL COMMENT '关联开发者ID',
  `bot_token` varchar(128) NOT NULL,
  `bot_name` varchar(50) NOT NULL,
  `bot_desc` varchar(500) DEFAULT '' COMMENT 'Bot描述',
  `bot_avatar` varchar(255) DEFAULT '',
  `status` tinyint(4) NOT NULL DEFAULT 1 COMMENT '1=正常 0=禁用',
  `can_notify` tinyint(4) NOT NULL DEFAULT 0 COMMENT '通知权限',
  `online` tinyint(4) NOT NULL DEFAULT 0 COMMENT '是否在线',
  `last_online` int(11) NOT NULL DEFAULT 0,
  `created_at` int(11) NOT NULL,
  `can_http` tinyint(4) NOT NULL DEFAULT 0 COMMENT '是否允许HTTP请求'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- --------------------------------------------------------

--
-- 表的结构 `bot_libs`
--

CREATE TABLE `bot_libs` (
  `id` int(11) NOT NULL,
  `name` varchar(100) NOT NULL COMMENT '库名',
  `version` varchar(50) NOT NULL DEFAULT '1.0.0' COMMENT '版本号',
  `content` mediumtext NOT NULL COMMENT 'JavaScript代码',
  `signature` varchar(256) NOT NULL DEFAULT '' COMMENT '签名',
  `author` varchar(100) NOT NULL DEFAULT '' COMMENT '作者',
  `desc` varchar(500) NOT NULL DEFAULT '' COMMENT '描述',
  `dev_id` int(11) NOT NULL COMMENT '上传者开发者ID',
  `status` tinyint(4) NOT NULL DEFAULT 0 COMMENT '0=待审核 1=已通过 2=已拒绝',
  `admin_note` text DEFAULT NULL COMMENT '管理员备注',
  `created_at` int(11) NOT NULL,
  `reviewed_at` int(11) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- 表的结构 `bot_logs`
--

CREATE TABLE `bot_logs` (
  `id` int(11) NOT NULL,
  `bot_id` int(11) NOT NULL,
  `script_id` int(11) NOT NULL DEFAULT 0,
  `level` enum('log','error','warn') NOT NULL DEFAULT 'log',
  `content` text NOT NULL,
  `created_at` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- --------------------------------------------------------

--
-- 表的结构 `bot_perm_requests`
--

CREATE TABLE `bot_perm_requests` (
  `id` int(11) NOT NULL,
  `bot_id` int(11) NOT NULL,
  `perm_type` varchar(50) NOT NULL COMMENT 'notify, http, etc.',
  `reason` text NOT NULL,
  `status` tinyint(4) NOT NULL DEFAULT 0 COMMENT '0=待审 1=通过 2=拒绝',
  `admin_reply` text DEFAULT NULL,
  `created_at` int(11) NOT NULL,
  `handled_at` int(11) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- --------------------------------------------------------

--
-- 表的结构 `bot_scripts`
--

CREATE TABLE `bot_scripts` (
  `id` int(11) NOT NULL,
  `bot_id` int(11) NOT NULL,
  `script_name` varchar(100) NOT NULL,
  `script_content` mediumtext NOT NULL,
  `enabled` tinyint(4) NOT NULL DEFAULT 1,
  `version` int(11) NOT NULL DEFAULT 1,
  `created_at` int(11) NOT NULL,
  `updated_at` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- --------------------------------------------------------

--
-- 表的结构 `bot_storage`
--

CREATE TABLE `bot_storage` (
  `id` int(11) NOT NULL,
  `bot_id` int(11) NOT NULL,
  `skey` varchar(128) NOT NULL,
  `value` mediumtext NOT NULL,
  `updated_at` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
  `level` int(11) NOT NULL DEFAULT 1,
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
  `nickname` varchar(30) DEFAULT NULL,
  `content` mediumtext DEFAULT NULL,
  `add_time` datetime NOT NULL,
  `msg_type` tinyint(1) DEFAULT 1 COMMENT '1=文字,2=图片,3=语音，4=拍一拍,5=表情包',
  `is_essence` tinyint(1) NOT NULL DEFAULT 0,
  `voice_duration` int(11) DEFAULT 0 COMMENT '语音时长(秒)',
  `was_replied` int(11) NOT NULL DEFAULT 0 COMMENT '0-未撤回；1-自己撤回；2-被管理员撤回；3-被群主撤回',
  `file_meta` text DEFAULT NULL COMMENT '文件消息元数据JSON'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
  `reason` mediumtext NOT NULL,
  `is_anonymous` tinyint(1) DEFAULT 0,
  `status` enum('pending','processing','resolved') DEFAULT 'pending',
  `admin_reply` mediumtext DEFAULT NULL,
  `add_time` int(11) NOT NULL,
  `process_time` int(11) DEFAULT 0
) ENGINE=MyISAM DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- 表的结构 `chat_room`
--

CREATE TABLE `chat_room` (
  `id` int(11) NOT NULL,
  `room_name` varchar(50) NOT NULL,
  `owner_uid` int(11) NOT NULL COMMENT '群主ID',
  `intro` mediumtext DEFAULT '' COMMENT '群组简介',
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
  `avatar` varchar(255) DEFAULT '',
  `allow_search` tinyint(1) NOT NULL DEFAULT 1 COMMENT '是否允许被搜索：1=允许 0=不允许（只能邀请/扫码加入）',
  `file_groups` text NOT NULL DEFAULT '[]' COMMENT '群文件分组列表JSON'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
  `is_first_login` tinyint(1) DEFAULT 1 COMMENT '1=首次登录需看教程 0=已看过',
  `last_active` int(11) NOT NULL DEFAULT 0 COMMENT '最后活跃时间戳',
  `ban_until` int(11) DEFAULT 0 COMMENT '封禁截止时间戳，0表示未封禁',
  `ban_reason` varchar(500) DEFAULT '' COMMENT '封禁原因',
  `theme_color` varchar(7) NOT NULL DEFAULT '#409eff',
  `allow_auto_join` int(11) NOT NULL DEFAULT 0 COMMENT '是否允许邀请后自动入群',
  `pat_action` varchar(32) NOT NULL DEFAULT '拍了拍',
  `platform` varchar(100) NOT NULL DEFAULT 'none',
  `email` varchar(255) DEFAULT NULL,
  `hide_conv` text NOT NULL DEFAULT '',
  `status` tinyint(1) NOT NULL DEFAULT 1 COMMENT '1=正常 2=注销冷静期 3=已注销删除',
  `delete_time` int(11) NOT NULL DEFAULT 0 COMMENT '注销时间戳',
  `restore_token` varchar(128) NOT NULL DEFAULT '' COMMENT '找回账号token',
  `restore_token_expires` int(11) NOT NULL DEFAULT 0 COMMENT '找回token过期时间戳',
  `is_bot` tinyint(1) NOT NULL DEFAULT 0 COMMENT '是否为Bot账号：0=普通用户 1=Bot'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- 表的结构 `chat_user_notice`
--

CREATE TABLE `chat_user_notice` (
  `id` int(11) NOT NULL,
  `uid` int(11) NOT NULL,
  `title` varchar(100) DEFAULT NULL,
  `content` mediumtext DEFAULT NULL,
  `link` varchar(255) DEFAULT NULL,
  `is_read` tinyint(1) DEFAULT 0,
  `add_time` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
-- 表的结构 `csac_sessions`
--

CREATE TABLE `csac_sessions` (
  `sid` varchar(128) NOT NULL,
  `uid` bigint(20) NOT NULL DEFAULT 0,
  `nickname` varchar(255) NOT NULL DEFAULT '',
  `platform` varchar(100) NOT NULL DEFAULT '',
  `sx` tinyint(1) NOT NULL DEFAULT 0,
  `se` bigint(20) NOT NULL DEFAULT 0,
  `last_touch` bigint(20) NOT NULL DEFAULT 0,
  `expires_at` bigint(20) NOT NULL,
  `updated_at` bigint(20) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- --------------------------------------------------------

--
-- 表的结构 `emoji_list`
--

CREATE TABLE `emoji_list` (
  `full_name` varchar(30) DEFAULT NULL COMMENT '全名，显示给用户',
  `abbr` varchar(5) NOT NULL COMMENT '缩写，用于快速输入',
  `address` varchar(255) DEFAULT NULL COMMENT '地址'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- 转存表中的数据 `emoji_list`
--

INSERT INTO `emoji_list` (`full_name`, `abbr`, `address`) VALUES
('拜谢', 'bax', 'emojis/gif/baixie.gif'),
('把持不住啊', 'bc', 'emojis/bc.jpg'),
('比心', 'bixin', 'emojis/gif/bixin.gif'),
('冰鼠疑惑', 'bs', 'emojis/bs.jpg'),
('不说', 'bsh', 'emojis/gif/bushuo.gif'),
('抱歉，今天不行', 'bx', 'emojis/bx.png'),
('变形', 'bxx', 'emojis/gif/bianxing.gif'),
('这扯不扯', 'cbc', 'emojis/cb.jpg'),
('雌二醇', 'cec', 'emojis/ce.jpg'),
('菜狗', 'cg', 'emojis/gif/caigou.gif'),
('馋', 'chn', 'emojis/gif/chan.gif'),
('吹', 'chu', 'emojis/gif/chui.gif'),
('掉线', 'dx', 'emojis/gif/diaoxian.gif'),
('大怨种', 'dyz', 'emojis/gif/dyz.gif'),
('恶心', 'ex', 'emojis/gif/exin.gif'),
('高潮', 'gc', 'emojis/gc.jpg'),
('尴尬', 'gg', 'emojis/gif/ganga.gif'),
('跪哭', 'gk', 'emojis/gif/guiku.gif'),
('乖', 'gu', 'emojis/gif/guai.gif'),
('好吃', 'hc', 'emojis/chi.jpg'),
('好吃', 'hch', 'emojis/gif/ch.gif'),
('哈哈', 'hh', 'emojis/gif/haha.gif'),
('滑稽', 'hj', 'emojis/huaji.png'),
('坏男娘', 'hnn', 'emojis/hn.jpg'),
('害怕', 'hp', 'emojis/gif/haipa.gif'),
('憨笑', 'hx', 'emojis/gif/hanxiao.gif'),
('jinsu', 'js', 'emojis/js.jpg'),
('开花', 'kah', 'emojis/gif/kaihua.gif'),
('开盒', 'kh', 'emojis/kh.jpg'),
('哭可怜', 'kkl', 'emojis/gif/kukelian.gif'),
('可怜', 'kl', 'emojis/gif/kelian.gif'),
('口水', 'ks', 'emojis/ks.jpg'),
('哭', 'ku', 'emojis/gif/ku.gif'),
('狂笑', 'kux', 'emojis/gif/kuangxiao.gif'),
('可以', 'ky', 'emojis/ky.png'),
('6', 'liu', 'emojis/liu.jpg'),
('喵', 'm', 'emojis/m.jpg'),
('男娘', 'nn', 'emojis/nn.jpg'),
('哦', 'o', 'emojis/gif/o.gif'),
('0酱', 'oj', 'emojis/oj.jpg'),
('期待', 'qd', 'emojis/gif/qidai.gif'),
('强', 'qi', 'emojis/qi.jpg'),
('色', 'se', 'emojis/gif/se.gif'),
('睡觉', 'sj', 'emojis/gif/shuijiao.gif'),
('生气', 'sq', 'emojis/gif/shengqi.gif'),
('涩涩', 'st', 'emojis/st.jpg'),
('逃', 't', 'emojis/gif/t.gif'),
('糖', 'ta', 'emojis/gif/tang.gif'),
('舔屏', 'tp', 'emojis/gif/tian.gif'),
('秃头', 'tt', 'emojis/gif/tutou.gif'),
('万盛', 'ws', 'emojis/ws.jpg'),
('捏楼上下巴', 'xb', 'emojis/xb.jpg'),
('续标识', 'xbs', 'emojis/gif/chuo.gif'),
('香草', 'xc', 'emojis/gif/xiangcao.gif'),
('笑哭', 'xk', 'emojis/gif/my.gif'),
('羡慕', 'xm', 'emojis/gif/xianmu.gif'),
('旋笑', 'xux', 'emojis/gif/wlss.gif'),
('性欲上升', 'xy', 'emojis/xy.jpg'),
('阴笑', 'yix', 'emojis/gif/yinxiao.gif'),
('阴险', 'yx', 'emojis/yinxian.png'),
('服务器炸咯', 'zl', 'emojis/zl.jpg'),
('真名泄露', 'zm', 'emojis/zm.jpg'),
('睁眼', 'zy', 'emojis/gif/zhengyan.gif');

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
  `remark` varchar(50) DEFAULT '',
  `notice_read` tinyint(1) NOT NULL DEFAULT 0 COMMENT '好友变动通知是否已读'
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
-- 表的结构 `group_commands`
--

CREATE TABLE `group_commands` (
  `id` int(11) NOT NULL,
  `room_id` int(11) NOT NULL COMMENT '群ID',
  `command` varchar(100) NOT NULL COMMENT '命令名',
  `content` text NOT NULL COMMENT '命令对应的消息内容',
  `created_by` int(11) NOT NULL COMMENT '创建者UID',
  `created_at` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- 表的结构 `group_files`
--

CREATE TABLE `group_files` (
  `id` int(11) NOT NULL,
  `room_id` int(11) NOT NULL COMMENT '群ID',
  `uploader_uid` int(11) NOT NULL COMMENT '上传者UID',
  `file_name` varchar(255) NOT NULL COMMENT '文件名',
  `file_size` int(11) NOT NULL DEFAULT 0 COMMENT '文件大小(字节)',
  `file_type` varchar(20) NOT NULL DEFAULT '' COMMENT '文件扩展名',
  `file_path` varchar(500) NOT NULL DEFAULT '' COMMENT '文件存储路径',
  `file_group` varchar(100) NOT NULL DEFAULT '' COMMENT '文件分组',
  `expires_at` int(11) NOT NULL DEFAULT 0 COMMENT '过期时间戳(0=永不过期)',
  `created_at` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- 表的结构 `open_dev_accounts`
--

CREATE TABLE `open_dev_accounts` (
  `id` int(11) NOT NULL,
  `email` varchar(255) NOT NULL,
  `pwd` varchar(64) NOT NULL,
  `dev_name` varchar(50) NOT NULL COMMENT '开发者名称',
  `api_key` varchar(128) NOT NULL COMMENT '开发者API Key',
  `status` tinyint(4) NOT NULL DEFAULT 1 COMMENT '1=正常 0=封禁',
  `created_at` int(11) NOT NULL,
  `uid` int(11) NOT NULL DEFAULT 0 COMMENT '关联chat_user.id',
  `allow_ajl_upload` tinyint(4) NOT NULL DEFAULT 0 COMMENT '是否允许上传AJL库：0=不允许 1=允许'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

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
  `msg_type` tinyint(4) NOT NULL DEFAULT 1 COMMENT '消息类型：1文本 2图片 3语音 5表情包',
  `file_meta` text DEFAULT NULL COMMENT '文件消息元数据JSON'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- 表的结构 `register_email_codes`
--

CREATE TABLE `register_email_codes` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `email` varchar(255) NOT NULL,
  `code_hash` varchar(255) NOT NULL,
  `ip_hash` varchar(80) NOT NULL DEFAULT '',
  `attempts` tinyint(3) UNSIGNED NOT NULL DEFAULT 0,
  `used_at` int(11) NOT NULL DEFAULT 0,
  `expires_at` int(11) NOT NULL,
  `created_at` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

-- --------------------------------------------------------

--
-- 表的结构 `space_shc`
--

CREATE TABLE `space_shc` (
  `cont_id` int(11) NOT NULL COMMENT '动态唯一ID（主键）',
  `sender_uid` int(11) NOT NULL COMMENT '发送者用户ID',
  `likes_num` int(11) NOT NULL DEFAULT 0 COMMENT '点赞数量',
  `likes_uid` text NOT NULL COMMENT '点赞用户ID列表，逗号分隔（无点赞时为空字符串）',
  `is_reply` tinyint(1) NOT NULL DEFAULT 0 COMMENT '是否为回复：1=是，0=否',
  `reply_id` int(11) DEFAULT NULL COMMENT '回复的目标动态ID（若is_reply=0，则此字段为NULL）',
  `content` text NOT NULL COMMENT '文字内容（若无文字但有图片，自动填“分享图片”）',
  `img_conts` text DEFAULT NULL COMMENT '图片内容（存储上传到云端后的url）',
  `created_at` datetime NOT NULL DEFAULT current_timestamp() COMMENT '创建时间'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='空间动态表';

--
-- 触发器 `space_shc`
--
DELIMITER $$
CREATE TRIGGER `trg_space_shc_before_insert` BEFORE INSERT ON `space_shc` FOR EACH ROW BEGIN
    -- 处理 content 为空的情况
    IF (NEW.content IS NULL OR NEW.content = '') THEN
        IF (NEW.img_conts IS NOT NULL AND NEW.img_conts != '') THEN
            SET NEW.content = '分享图片';
        ELSE
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'content 不能为空：无图片时必须提供文字内容';
        END IF;
    END IF;
    
    -- 可选：保证 likes_uid 为空字符串而非 NULL（防止出现 NULL）
    IF NEW.likes_uid IS NULL THEN
        SET NEW.likes_uid = '';
    END IF;
    
    -- 可选：如果 is_reply=0，自动将 reply_id 置为 NULL（保持数据干净）
    IF NEW.is_reply = 0 THEN
        SET NEW.reply_id = NULL;
    END IF;
END
$$
DELIMITER ;

--
-- 转储表的索引
--

--
-- 表的索引 `acr_uploads`
--
ALTER TABLE `acr_uploads`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_dev_id` (`dev_id`),
  ADD KEY `idx_status` (`status`);

--
-- 表的索引 `admin_tokens`
--
ALTER TABLE `admin_tokens`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `token` (`token`),
  ADD KEY `idx_token` (`token`),
  ADD KEY `idx_expires` (`expires_at`),
  ADD KEY `idx_csac_admin_tokens_token_expiry` (`token`,`expires_at`,`used`);

--
-- 表的索引 `bot_accounts`
--
ALTER TABLE `bot_accounts`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `bot_token` (`bot_token`),
  ADD KEY `dev_id` (`dev_id`),
  ADD KEY `uid` (`uid`);

--
-- 表的索引 `bot_libs`
--
ALTER TABLE `bot_libs`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_name_version` (`name`,`version`),
  ADD KEY `idx_dev_id` (`dev_id`),
  ADD KEY `idx_status` (`status`);

--
-- 表的索引 `bot_logs`
--
ALTER TABLE `bot_logs`
  ADD PRIMARY KEY (`id`),
  ADD KEY `bot_id` (`bot_id`,`created_at`),
  ADD KEY `bot_id_2` (`bot_id`,`level`);

--
-- 表的索引 `bot_perm_requests`
--
ALTER TABLE `bot_perm_requests`
  ADD PRIMARY KEY (`id`),
  ADD KEY `bot_id` (`bot_id`),
  ADD KEY `status` (`status`);

--
-- 表的索引 `bot_scripts`
--
ALTER TABLE `bot_scripts`
  ADD PRIMARY KEY (`id`),
  ADD KEY `bot_id` (`bot_id`);

--
-- 表的索引 `bot_storage`
--
ALTER TABLE `bot_storage`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_bot_key` (`bot_id`,`skey`),
  ADD KEY `idx_bot_id` (`bot_id`);

--
-- 表的索引 `chat_essence`
--
ALTER TABLE `chat_essence`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `msg_id` (`msg_id`),
  ADD KEY `idx_csac_essence_room_msg` (`room_id`,`msg_id`);

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
  ADD UNIQUE KEY `uk_room_uid` (`room_id`,`uid`),
  ADD KEY `idx_csac_group_user_uid_room` (`uid`,`room_id`),
  ADD KEY `idx_csac_group_user_room_uid_read` (`room_id`,`uid`,`last_read_msg_id`);

--
-- 表的索引 `chat_msg`
--
ALTER TABLE `chat_msg`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_csac_chat_msg_room_id_id` (`room_id`,`id`),
  ADD KEY `idx_csac_chat_msg_room_uid_time` (`room_id`,`uid`,`add_time`),
  ADD KEY `idx_csac_chat_msg_reply_to` (`reply_to`);

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
-- 表的索引 `chat_user_notice`
--
ALTER TABLE `chat_user_notice`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_csac_notice_uid_read_time` (`uid`,`is_read`,`add_time`);

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
-- 表的索引 `csac_sessions`
--
ALTER TABLE `csac_sessions`
  ADD PRIMARY KEY (`sid`),
  ADD KEY `idx_csac_sessions_expires` (`expires_at`),
  ADD KEY `idx_csac_sessions_uid` (`uid`);

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
  ADD KEY `idx_friend_relation_uid2` (`uid2`),
  ADD KEY `idx_csac_friend_rel_uid1_status` (`uid1`,`status`),
  ADD KEY `idx_csac_friend_rel_uid2_status` (`uid2`,`status`);

--
-- 表的索引 `friend_request`
--
ALTER TABLE `friend_request`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_to_uid` (`to_uid`,`status`),
  ADD KEY `idx_from_uid` (`from_uid`),
  ADD KEY `idx_status` (`status`),
  ADD KEY `idx_csac_friend_req_to_status` (`to_uid`,`status`,`from_uid`),
  ADD KEY `idx_csac_friend_req_from_to_status` (`from_uid`,`to_uid`,`status`);

--
-- 表的索引 `group_commands`
--
ALTER TABLE `group_commands`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_room_command` (`room_id`,`command`),
  ADD KEY `idx_room_id` (`room_id`);

--
-- 表的索引 `group_files`
--
ALTER TABLE `group_files`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_room_id` (`room_id`),
  ADD KEY `idx_room_group` (`room_id`,`file_group`),
  ADD KEY `idx_expires` (`expires_at`);

--
-- 表的索引 `open_dev_accounts`
--
ALTER TABLE `open_dev_accounts`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `email` (`email`),
  ADD UNIQUE KEY `api_key` (`api_key`),
  ADD UNIQUE KEY `uk_uid` (`uid`);

--
-- 表的索引 `private_msg`
--
ALTER TABLE `private_msg`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_from_to` (`from_uid`,`to_uid`),
  ADD KEY `idx_created` (`created_at`),
  ADD KEY `idx_csac_private_msg_read` (`to_uid`,`is_read`,`type`,`from_uid`),
  ADD KEY `idx_csac_private_msg_from_pair` (`from_uid`,`to_uid`,`type`,`id`),
  ADD KEY `idx_csac_private_msg_to_pair` (`to_uid`,`from_uid`,`type`,`id`);

--
-- 表的索引 `register_email_codes`
--
ALTER TABLE `register_email_codes`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_csac_register_email_created` (`email`,`created_at`),
  ADD KEY `idx_csac_register_ip_created` (`ip_hash`,`created_at`);

--
-- 表的索引 `space_shc`
--
ALTER TABLE `space_shc`
  ADD PRIMARY KEY (`cont_id`),
  ADD KEY `idx_sender_uid` (`sender_uid`),
  ADD KEY `idx_reply_id` (`reply_id`);

--
-- 在导出的表使用AUTO_INCREMENT
--

--
-- 使用表AUTO_INCREMENT `acr_uploads`
--
ALTER TABLE `acr_uploads`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `admin_tokens`
--
ALTER TABLE `admin_tokens`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `bot_accounts`
--
ALTER TABLE `bot_accounts`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `bot_libs`
--
ALTER TABLE `bot_libs`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `bot_logs`
--
ALTER TABLE `bot_logs`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `bot_perm_requests`
--
ALTER TABLE `bot_perm_requests`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `bot_scripts`
--
ALTER TABLE `bot_scripts`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `bot_storage`
--
ALTER TABLE `bot_storage`
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
-- 使用表AUTO_INCREMENT `group_commands`
--
ALTER TABLE `group_commands`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `group_files`
--
ALTER TABLE `group_files`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `open_dev_accounts`
--
ALTER TABLE `open_dev_accounts`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `private_msg`
--
ALTER TABLE `private_msg`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `register_email_codes`
--
ALTER TABLE `register_email_codes`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `space_shc`
--
ALTER TABLE `space_shc`
  MODIFY `cont_id` int(11) NOT NULL AUTO_INCREMENT COMMENT '动态唯一ID（主键）';
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
