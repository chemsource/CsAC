# UniCsAC API 文档

本文档按当前后端实现整理，统一入口为：

```text
/rpc/UniCsAC.php
```

调用方式：

```text
GET  /rpc/UniCsAC.php?route=user/get_info
POST /rpc/UniCsAC.php?route=message/send_group_msg
GET  /rpc/UniCsAC.php/user/get_info
```

第三方客户端只应调用 `UniCsAC.php`。旧的散文件入口、`rpc.php`、`x.php` 和 `.php` 后缀 route 不再是公共 API。

## 通用约定

- API 名称：`UniCsAC`
- 路由参数：`route`，例如 `auth/login`、`message/get_group_msg`
- 响应格式：JSON，成功时 `success: true`，失败时 `success: false`
- 认证方式：PHP Session Cookie。第三方客户端必须保存并携带 Cookie。
- 查询类接口主要使用 `GET`，写入类接口使用 `POST`。
- `POST` 支持 `application/json`、`application/x-www-form-urlencoded`、`multipart/form-data`。
- 文件上传必须使用 `multipart/form-data`。
- 未登录通常返回 HTTP `401`。
- 无权限、账号封禁或群组封禁通常返回 HTTP `403`；账号封禁会带 `ban_info`，群组封禁会带 `room_ban_info`。
- 无效 route 返回 HTTP `404`。
- `OPTIONS` 预检返回 HTTP `204`。

典型成功响应：

```json
{
  "success": true,
  "message": "操作成功"
}
```

典型失败响应：

```json
{
  "success": false,
  "message": "未登录"
}
```

封禁响应：

```json
{
  "success": false,
  "message": "账号已封禁",
  "ban_info": {
    "banned": true,
    "until": 1770000000,
    "reason": "违反相关规定"
  }
}
```

群组封禁响应：

```json
{
  "success": false,
  "message": "群组已被封禁至 2026-05-11 18:30:00，暂不可使用",
  "room_ban_info": {
    "banned": true,
    "until": 1770000000,
    "until_text": "2026-05-11 18:30:00",
    "reason": "违反相关规定"
  }
}
```

## 字段说明

### 用户 `user`

常见字段：

- `uid`：用户 ID
- `username`：登录账号
- `nickname`：昵称
- `avatar`：头像路径，默认 `default.png`
- `last_active`：最后活跃时间
- `online_status`：在线状态展示文本，后端可能返回少量 HTML，客户端应按不可信内容处理
- `is_self`：是否为当前登录用户
- `remark`：好友备注
- `is_friend`：是否为好友
- `friend_request_sent`：是否已发出好友请求
- `friend_request_received`：是否收到对方好友请求
- `is_blocked`：是否存在拉黑关系
- `can_add_friend`：当前是否可添加好友

### 群组 `room/group`

常见字段：

- `id` / `room_id`：群组 ID
- `room_name`：群组名称
- `intro`：简介
- `notice`：公告
- `invite_code`：一次性邀请码
- `join_type`：加入方式，`1` 自由加入，`2` 一次性邀请码，`3` 固定口令，`4` 审核加入
- `owner_uid`：群主 UID
- `owner_name`：群主昵称
- `member_count`：成员数
- `unread_count`：未读群消息数
- `ask_question`：审核问题
- `fixed_code`：固定口令
- `show_in_list`：是否公开展示
- `allow_invite`：成员是否可见邀请码
- `is_banned`：群组当前是否封禁
- `ban_until` / `ban_until_text`：群组封禁截止时间
- `ban_reason`：群组封禁原因
- `room_ban_info`：群组封禁详情；未封禁时为 `null`

### 消息 `message`

常见字段：

- `id`：消息 ID
- `uid`：群聊发送者 UID
- `from_uid`：私聊发送者 UID
- `to_uid`：私聊接收者 UID
- `nickname` / `username` / `avatar`：发送者信息
- `content`：文本内容，图片/语音消息中也可能保存文件路径或占位文本
- `msg_type`：`1` 文本，`2` 图片，`3` 语音
- `image_url`：图片地址
- `voice_url`：语音地址
- `duration` / `voice_duration`：语音时长，秒
- `add_time`：群聊发送时间
- `created_at`：私聊发送时间戳
- `is_read`：私聊已读标记
- `reply_to`：被回复消息 ID
- `reply_content`：被回复消息内容
- `reply_from_uid`：被回复消息发送者 UID
- `reply_nickname`：被回复消息发送者昵称
- `can_recall`：当前用户是否可撤回，群聊消息返回
- `is_essence`：是否精华，群聊消息返回
- `is_mentioned`：是否 @ 当前用户，群聊消息返回
- `reply_to_me`：是否回复当前用户，群聊消息返回

## 认证

### 登录

`POST /rpc/UniCsAC.php?route=auth/login`

参数：

- `username`：账号
- `pwd`：密码

返回：

```json
{
  "success": true,
  "message": "登录成功",
  "need_guide": false,
  "user": {
    "uid": 1,
    "nickname": "昵称"
  }
}
```

### 注册

`POST /rpc/UniCsAC.php?route=auth/register`

参数：

- `username`：3-32 位，字母、数字、下划线、`@`、`.`、`-`
- `nickname`：昵称，最长 16 个字符
- `pwd`：密码，至少 6 位
- `confirm_pwd`：确认密码
- `avatar`：可选头像文件

返回登录后的用户信息。

### 退出登录

`POST /rpc/UniCsAC.php?route=auth/logout`

返回：

```json
{
  "success": true,
  "message": "已退出登录"
}
```

## 用户

### 获取用户信息

`GET /rpc/UniCsAC.php?route=user/get_info`

参数：

- `uid`：可选。省略时返回当前用户。

返回：

```json
{
  "success": true,
  "user": {}
}
```

### 更新资料

`POST /rpc/UniCsAC.php?route=user/update_profile`

参数按 `action` 区分：

- `action=nickname`，同时传 `nickname`
- `action=password`，同时传 `old_password`、`new_password`、`confirm_password`
- `action=avatar`，同时上传 `avatar` 文件

### 升级密码

`POST /rpc/UniCsAC.php?route=user/upgrade_password`

参数：

- `new_password`
- `confirm_password`
- `old_password` 可传，但当前实现不强制校验旧密码

### 注销账号

`POST /rpc/UniCsAC.php?route=user/delete_account`

会删除当前用户、其创建的群组、相关消息、通知、好友关系等数据，并销毁 Session。

### 获取好友列表

`GET /rpc/UniCsAC.php?route=user/get_friends`

返回：

```json
{
  "success": true,
  "friends": [
    {
      "friend_id": 2,
      "nickname": "昵称",
      "avatar": "default.png",
      "username": "account",
      "last_active": 1770000000,
      "online_status": "在线状态",
      "remark": "",
      "display_name": "昵称",
      "unread_count": 0
    }
  ]
}
```

### 获取已加入群组

`GET /rpc/UniCsAC.php?route=user/get_groups`

返回：

```json
{
  "success": true,
  "message": "群组加载成功",
  "count": 1,
  "groups": []
}
```

### 获取通知计数

`GET /rpc/UniCsAC.php?route=user/get_notifications`

返回字段：

- `system_notice_unread`
- `friend_request_unread`
- `deleted_friend_notices`
- `total_unread`

### 获取通知列表

`GET /rpc/UniCsAC.php?route=user/get_notice_list`

返回 `notices[]`：

- `id`
- `title`
- `content`
- `add_time`
- `is_read`
- `link`

### 标记通知已读

`POST /rpc/UniCsAC.php?route=user/mark_notice_read`

参数：

- `read_all=1`：全部已读
- 或 `notice_id`：标记单条通知

### 获取某用户创建的群组

`GET /rpc/UniCsAC.php?route=user/get_created_groups`

参数：

- `uid`：可选，默认当前用户

返回 `groups[]`。

## 好友

### 发送好友请求

`POST /rpc/UniCsAC.php?route=friend/send_request`

参数：

- `to_uid` 或 `friend_id`
- `message`：可选，默认 `请求添加你为好友`

### 处理好友请求

`POST /rpc/UniCsAC.php?route=friend/handle_request`

参数：

- `request_id`
- `action=agree|refuse`

### 删除好友

`POST /rpc/UniCsAC.php?route=friend/delete_friend`

参数：

- `friend_id`

### 拉黑好友

`POST /rpc/UniCsAC.php?route=friend/block_friend`

参数：

- `friend_id`

### 恢复好友

`POST /rpc/UniCsAC.php?route=friend/recover_friend`

参数：

- `friend_id`
- `direct=1`：当前用户主动删除且仍在可恢复期时直接恢复
- `message`：申请恢复时的附言

### 修改好友备注

`POST /rpc/UniCsAC.php?route=friend/update_remark`

参数：

- `friend_id`
- `remark`

### 获取共同群组

`GET /rpc/UniCsAC.php?route=friend/get_common_groups`

参数：

- `friend_id`

返回 `groups[]`。

### 获取删除通知

`GET /rpc/UniCsAC.php?route=friend/get_deleted_notices`

返回 `notices[]`。

### 获取待处理好友请求

`GET /rpc/UniCsAC.php?route=friend/get_friend_requests`

返回 `requests[]`。

## 群组

### 创建群组

`POST /rpc/UniCsAC.php?route=group/create`

参数：

- `room_name`：群组名称，最长 32 个字符

返回：

```json
{
  "success": true,
  "message": "群组创建成功",
  "room_id": 1,
  "id": 1,
  "invite_code": "AbCd123"
}
```

### 获取公开群组

`GET /rpc/UniCsAC.php?route=group/get_public_list`

需要登录。返回公开展示的群组列表。

### 获取群组详情

`GET /rpc/UniCsAC.php?route=group/get_group_view_info`

参数：

- `room_id` 或 `rid`

返回：

```json
{
  "success": true,
  "room": {},
  "is_in_group": true,
  "has_apply": false,
  "is_owner": false,
  "is_admin": false,
  "can_view_invite": true
}
```

### 获取群成员

`GET /rpc/UniCsAC.php?route=group/get_members`

参数：

- `room_id` 或 `rid`

要求当前用户是群成员。返回 `members[]`：

- `uid`
- `nickname`
- `avatar`
- `is_owner`
- `is_admin`
- `is_muted`
- `mute_until`
- `online_status`

### 申请或直接加入群组

`POST /rpc/UniCsAC.php?route=group/apply_join`

参数：

- `room_id` 或 `rid`
- `code`：`join_type=2` 或 `3` 时必填
- `answer`：`join_type=4` 时提交审核答案

行为：

- `join_type=1`：直接加入
- `join_type=2`：校验一次性邀请码，成功后重置邀请码
- `join_type=3`：校验固定口令
- `join_type=4`：提交入群申请

### 获取入群申请

`GET /rpc/UniCsAC.php?route=group/get_applications`

参数：

- `room_id` 或 `rid`

要求群主或管理员。返回 `applications`、`applies`、`requests` 三个同内容数组。

### 处理入群申请

`POST /rpc/UniCsAC.php?route=group/handle_apply`

参数：

- `apply_id`
- `action=pass|refuse`

### 编辑群资料

`POST /rpc/UniCsAC.php?route=group/edit_info`

参数写法一：

- `room_id`
- `room_name`
- `intro`
- `notice`

参数写法二：

- `room_id`
- `action=name|intro|notice`
- `value`

要求群主或管理员。

### 更新群设置

`POST /rpc/UniCsAC.php?route=group/update_settings`

参数：

- `room_id`
- `join_type`：1-4
- `fixed_code`：固定口令
- `question`：审核问题，写入 `ask_question`
- `answer`：审核答案，写入 `ask_answer`
- `show_in_list=0|1`
- `allow_invite=0|1`

要求群主或管理员。

### 重置邀请码

`POST /rpc/UniCsAC.php?route=group/reset_invite_code`

参数：

- `room_id`

要求群主。返回 `invite_code` 和 `new_code`。

### 转让群主

`POST /rpc/UniCsAC.php?route=group/transfer`

参数：

- `room_id`
- `target_uid` 或 `new_owner_uid`

要求群主。当前实现会创建转让申请并通知目标用户。

### 解散群组

`POST /rpc/UniCsAC.php?route=group/disband`

参数：

- `room_id`

要求群主。当前实现将群组标记为已解散并通知成员。

### 退出群组

`POST /rpc/UniCsAC.php?route=group/leave`

参数：

- `room_id` 或 `rid`

群主不能直接退出，需先转让或解散。

### 禁言或解除禁言

`POST /rpc/UniCsAC.php?route=group/mute_member`

参数：

- `room_id`
- `target_uid`
- `action=mute|unmute`
- `minutes`：`action=mute` 时必填，范围 1-43200

要求群主或管理员。

### 踢出成员

`POST /rpc/UniCsAC.php?route=group/kick_member`

参数：

- `room_id`
- `target_uid`

要求群主或管理员。

### 设置或取消管理员

`POST /rpc/UniCsAC.php?route=group/set_admin`

参数：

- `room_id`
- `target_uid`
- `action=set|remove`

要求群主。

## 消息

### 发送群聊消息

`POST /rpc/UniCsAC.php?route=message/send_group_msg`

参数：

- `room_id`
- `content`：文本内容；上传图片时可为空
- `img`：可选图片文件，字段名固定为 `img`
- `reply_to`：可选，被回复消息 ID
- `mention_uids`：可选，逗号分隔 UID，如 `2,3,8`

要求当前用户是群成员且未被禁言。

### 获取群聊消息

`GET /rpc/UniCsAC.php?route=message/get_group_msg`

兼容别名：

`GET /rpc/UniCsAC.php?route=group/get_group_msg`

参数：

- `room_id` 或 `rid`

返回 `messages[]`。别名 route：`group/get_group_msg`。

### 发送私聊消息

`POST /rpc/UniCsAC.php?route=message/send_private_msg`

参数：

- `friend_id`
- `content`：文本内容；上传图片时可为空
- `img`：可选图片文件，字段名固定为 `img`
- `reply_to`：可选，被回复消息 ID

要求双方是好友。

### 获取私聊消息

`GET /rpc/UniCsAC.php?route=message/get_private_msg`

参数：

- `friend_id`
- `last_id`：可选，只返回 ID 大于该值的消息

返回：

```json
{
  "success": true,
  "messages": [],
  "last_id": 100
}
```

该接口会自动把对方发来的未读私聊标记为已读。

### 发送语音消息

`POST /rpc/UniCsAC.php?route=message/send_voice_msg`

参数：

- `voice`：语音文件，字段名固定为 `voice`
- `duration`：时长，秒
- `room_id`：群聊语音时传
- `friend_id`：私聊语音时传

支持音频 MIME：`audio/webm`、`audio/ogg`、`audio/mpeg`、`audio/wav`、`audio/mp4`。

### 撤回消息

`POST /rpc/UniCsAC.php?route=message/recall_msg`

参数：

- `msg_id`
- `type=group|private`，默认 `group`
- `room_id`：群聊撤回时必填

规则：

- 自己发送的消息 2 分钟内可撤回
- 群主可撤回本群消息
- 管理员可撤回普通成员消息

### 标记已读

`POST /rpc/UniCsAC.php?route=message/mark_read`

参数：

- 私聊：`friend_id`
- 群聊：`room_id`，可选 `last_msg_id`

### 获取 @ 和回复计数

`GET /rpc/UniCsAC.php?route=message/get_mentions`

返回：

- `unread_mentions`
- `unread_replies`

## 精华消息

### 设置或取消精华

`POST /rpc/UniCsAC.php?route=essence/set_essence`

参数：

- `msg_id`
- `room_id`

要求群主或管理员。同一个接口会按当前状态切换：已是精华则取消，否则设为精华。

### 获取精华列表

`GET /rpc/UniCsAC.php?route=essence/get_essence`

参数：

- `room_id`

返回：

- `essence_list[]`
- `can_remove`

`essence_list[]` 使用消息字段结构，并额外包含：

- `set_uid`
- `set_nick`
- `set_time`

### 获取精华统计

`GET /rpc/UniCsAC.php?route=essence/get_essence_stats`

参数：

- `room_id`
- `type=today|week|month|all`，默认 `today`

返回：

- `type`
- `type_name`
- `total`
- `text_count`
- `image_count`
- `voice_count`
- `rank[]`：贡献排行，包含 `rank`、`uid`、`nickname`、`count`
- `latest_set_time`
- `rank[]`

## 举报与反馈

### 提交举报

`POST /rpc/UniCsAC.php?route=report/submit_report`

参数：

- `type=user|group`
- 用户举报：`uid`
- 群组举报：`rid`
- `reason`：至少 10 个字符
- `anonymous=0|1`
- `nickname` / `username`：用户举报时可传目标显示名
- `room_name`：群组举报时可传目标群名

### 提交 Bug 反馈

`POST /rpc/UniCsAC.php?route=bug_report`

参数：

- `title`
- `description`

反馈会发送给管理员，并写入一条私聊系统消息。

## 工具上传

### 上传图片

`POST /rpc/UniCsAC.php?route=utils/upload_image`

参数：

- `image`：图片文件

返回：

```json
{
  "success": true,
  "url": "upload/img/xxx.jpg"
}
```

### 上传语音

`POST /rpc/UniCsAC.php?route=utils/upload_voice`

参数：

- `voice`：语音文件

返回：

```json
{
  "success": true,
  "url": "upload/voice/xxx.webm"
}
```

## 管理员

管理员 UID 固定为 `1`。

### 生成管理员临时令牌

`POST /rpc/UniCsAC.php?route=admin/generate_token`

要求当前登录用户 UID 为 `1`。

返回：

```json
{
  "success": true,
  "token": "hex-token",
  "expires_in": 300
}
```

### 封禁管理

`GET /rpc/UniCsAC.php?route=admin/admin_ban`

参数：

- `token`

返回当前封禁用户和封禁群组：

- `users[]`
- `rooms[]`

`POST /rpc/UniCsAC.php?route=admin/admin_ban`

公共参数：

- `token`
- `action`

动作：

- `action=ban_user`：参数 `user_id`、`ban_days`、`ban_reason`
- `action=unban_user`：参数 `user_id`
- `action=ban_room`：参数 `room_id`、`ban_days`、`ban_reason`
- `action=unban_room`：参数 `room_id`

`POST` 会消耗令牌；每次管理写操作前需要重新生成令牌。

## 测试

### 数据库连通性测试

`GET /rpc/UniCsAC.php?route=test`

返回：

```json
{
  "success": true,
  "message": "Database OK"
}
```

如果本地无法连接远程 MySQL，该接口可能返回服务器错误。

## 第三方客户端建议

1. 登录成功后保存 Cookie，并在后续请求中携带。
2. 文件消息直接使用 `message/send_group_msg` 或 `message/send_private_msg` 上传 `img`，不需要先调用工具上传接口。
3. 私聊增量同步使用 `message/get_private_msg` 的 `last_id`。
4. 群聊当前返回全量消息，客户端可自行缓存最后消息 ID 做本地增量渲染。
5. 客户端不要信任 `online_status`、`content`、`nickname` 等展示字段，渲染前应转义。
6. 所有 route 均不带 `.php` 后缀。
