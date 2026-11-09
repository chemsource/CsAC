# CsAC WebSocket v2 接入

面向 Android 等原生客户端的地址为 `wss://csac.chat/ws/v2`，也可使用 `/rpc/ws/v2`。原有 `/ws` 接口继续保留。v2 使用 JSON-RPC 2.0、UTF-8 文本帧，不传二进制文件。连接成功后服务器推送 `session.ready`，其 `params` 包含身份状态、事件游标、保留窗口、心跳周期和限制。可选 WebSocket 子协议为 `csac.v2`；客户端应回应 WebSocket Ping 帧并自动重连。

## 认证和方法发现

原生客户端可在握手时发送 `Authorization: Bearer <session-token>`；已登录的同站浏览器也可使用现有会话 Cookie。也可先建立匿名连接，通过 `auth/login` 或 `auth/register` 登录，成功后从 `result.session.token` 获取令牌；已有令牌可调用 `session.authenticate`。令牌是凭据，请使用 Android 安全存储，不要放在 URL、日志或崩溃报告中。匿名连接须在 30 秒内完成认证；令牌失效、退出登录或账号封禁后连接会关闭。

```json
{"jsonrpc":"2.0","id":"login-1","method":"auth/login","params":{"username":"alice","pwd":"password","platform":"Android-native-app"}}
```

`rpc.discover` 返回可用业务方法及 `public`、`read_only`、`idempotency_key` 元数据；`control_methods` 列出连接控制方法。用户侧 JSON API 使用既有 HTTP 路由名，如 `user/get_info`、`friend/send_request`、`group/create`、`message/send_group_msg`、`message/get_private_msg` 和 `space/get_list`。参数与原 HTTP API 对应，业务成功结果位于 `result.data`，原 HTTP 状态位于 `result.http_status`；业务失败返回 JSON-RPC `error`，原返回体在 `error.data.body`。

```json
{"jsonrpc":"2.0","id":"send-1","method":"message/send_group_msg","params":{"room_id":42,"content":"你好"},"idempotency_key":"group-message-001"}
```

二进制上传、下载和 multipart 请求继续使用 HTTPS，例如语音、文件、图片、头像上传；先读取 `rpc.discover`，无法通过 WS 访问的方法走原 HTTP API。旧长轮询、旧会话扩展以及 ACOP/eMApps 后台管理也不通过 v2 提供。

## 重试与请求边界

业务写操作应带唯一 `idempotency_key`，长度 8–128，只能使用字母、数字、下划线、点、冒号和连字符。密钥按用户隔离，要求同一个密钥始终对应相同方法和参数。断线重发时沿用原密钥；服务端返回已完成的结果，不再重复执行业务。认证、密码修改、注销等凭据操作不缓存请求结果，不要自动重复提交。`user/update_profile` 的密码修改也是例外。

可通过 `requests.status` 查询密钥：

```json
{"jsonrpc":"2.0","id":"status-1","method":"requests.status","params":{"idempotency_key":"group-message-001"}}
```

状态 `complete` 包含原 `outcome`，`unknown` 表示查无记录；`pending_or_interrupted` 表示尚未完成或服务器中断，客户端须先重新同步业务状态，不能假定该操作未执行。`-32010` 表示密钥已用于不同参数，`-32011` 表示结果不确定，`-32013` 表示响应太大，应缩小分页；批量写入收到该错误时先查请求状态。幂等记录与事件默认保留 7 天，过期后不能用于去重。

同一连接一次最多 16 个批量请求，消息上限 1 MiB。正常认证连接每分钟最多 1200 个请求，匿名连接每分钟最多 10 个；每个批量元素单独计数。建议请求带 `id`，尤其是认证和写操作。金额以外的 ID 在部分 API 中是 JSON 数字，事件 `seq`、游标和确认值始终为十进制字符串，客户端不要转成浮点数。

## 实时事件和断线恢复

服务端通过 `method: "event"` 推送数据变动提示。持久事件包含 `seq`、`type`、`data` 和 `server_time`；数据仅包含必要的标识与状态，不包含消息正文。客户端收到提示后用相应查询 API 更新本地数据。

主要事件包括 `message.created/updated/deleted`、`conversation.read`、`friend.changed`、`friend.request_changed`、`notification.created/updated/deleted`、`group.created/updated/disbanded`、`group.members_changed`、`group.roles_changed`、`group.application_changed`、`group.transfer_changed`、`group.files_changed`、`group.essence_changed`、`space.changed`、`profile.updated`、`user.updated`。服务端会根据当前好友或群成员关系过滤历史和实时事件；被移出群聊或解除好友关系后，不能再回放相关消息提示。

```json
{"jsonrpc":"2.0","method":"event","params":{"seq":"128","type":"message.created","data":{"room_id":42,"msg_id":73,"uid":7,"msg_type":1},"server_time":1760000000}}
```

首次使用应保存 `session.ready` 或认证成功返回的 `cursor`，随后读取用户、好友、群组和会话的完整快照，再从该游标开始回放；同步快照期间缓冲实时事件。重连后从设备持久保存的最后游标回放：

```json
{"jsonrpc":"2.0","id":"resume-1","method":"events.resume","params":{"after":"128","limit":200}}
```

结果中 `events` 是当前页，`next_cursor` 是扫描到的位置，`has_more` 表示需要继续请求。即使本页没有符合权限的事件，也要沿 `next_cursor` 翻页，直到 `has_more` 为 `false`。回放和实时推送可能交错或重复：缓冲实时事件，按 `seq` 去重并同步受影响的数据；只有完整处理所有回放页及缓冲事件后才持久化安全游标。可以发送 `events.ack`（`params.seq` 为已处理游标）确认；它是当前连接的提示，客户端仍须持久保存自己的游标。服务端不会根据 ACK 自动替客户端保存恢复进度。

如果游标超出保留窗口或领先于服务器，收到 `-32009` 和 `reset_required`，重新获取完整快照，以错误中的 `cursor` 为基准重新回放。事件默认保留 7 天；服务器重启后事件仍保留。慢消费者可能被断开，重连后使用保存的游标恢复。

`presence.get` 查询允许查看的用户，`typing.set` 通过 `conversation_type`（`group` 或 `private`）、`conversation_id` 和 `active` 通知对方。`presence.changed` 与 `typing.changed` 为临时事件，带 `transient: true`，不进入持久回放；输入状态约 5 秒过期。`connected` 仅代表当前服务实例的 v2 连接，`last_active` 可辅助展示最后活跃时间。

## Bot 事件

Bot 使用 `wss://csac.chat/bot/ws`，握手中发送 `Authorization: Bearer <bot-token>`。连接后发送 `{"type":"subscribe","events":["private_msg","group_msg","state"]}`，可选事件为 `group_msg`、`private_msg`、`group_join`、`group_leave`、`group_mute`、`group_disband`、`state`，`*` 订阅全部；`{"type":"unsubscribe"}` 取消。`event:state` 包含与用户事件相同的变动元数据。Bot 转发经内部队列尽力投递，不提供 v2 事件游标回放；需要可靠业务状态时应调用 Bot API 同步。

## HTTP/3

`https://csac.chat` 的普通 HTTP 请求支持客户端与 Cloudflare 之间的 HTTP/3；本源 OpenResty 也已启用 QUIC。Cloudflare 到源站的协议由 Cloudflare 决定。WebSocket 使用 WSS 升级连接，不能把普通 WebSocket 视为 HTTP/3 数据流。Android 网络库应允许 HTTPS 根据网络条件选择 HTTP/3 或回退到 HTTP/2/1.1。
