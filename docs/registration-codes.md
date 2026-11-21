# CsAC 注册码接入

注册码用于**创建站点账号**，与用于加入群组的**群组邀请码**无关。邮箱验证码注册继续保留。用注册码成功注册后，即使尚未绑定邮箱，也可以正常聊天、加好友、加入或创建群组、使用实时事件。账号不会被标为已经验证邮箱；需要邮箱登录、找回密码等功能时，应先绑定真实邮箱。

## 注册

HTTP：向 `POST /rpc/UniCsAC.php/auth/register` 发送 JSON 请求体。WebSocket v2：在匿名连接上调用 `auth/register`，将相同字段放入 `params`。

```json
{
  "username": "example_user",
  "nickname": "小明",
  "pwd": "示例密码，请替换",
  "confirm_pwd": "示例密码，请替换",
  "registration_code": "<管理员提供的注册码>"
}
```

- 不传 `registration_code`（或传空字符串）时，继续走原有流程。传入非空注册码时，只走注册码流程；即使同时传了 `email` 和 `email_code`，也不会绑定该邮箱，注册码失败后不会自动改走邮箱注册。注册码区分大小写，首尾空白会被去除。
- HTTP 注册成功后使用响应 Cookie；WS v2 从 `result.session` 读取令牌和游标。注册码注册成功时，`needs_email_verification` 为 `false`。
- 码无效、已过期、用完或作废时，HTTP 返回 `success: false` 和 `code: "invalid_registration_code"`；WS v2 可读 `error.data.body.code`。不要把注册码放进 URL、日志、分析事件或崩溃报告。
- 只有成功创建账号才扣减一个名额。若提交后连接中断、没有收到响应，应先尝试用刚填写的账号和密码登录，不要自动重发注册。
- 如需同时上传头像，仍可使用 HTTP multipart。也可先注册，再走原有头像上传流程。

## 管理

管理接口仅通过 HTTP 提供，要求当前有效的站点管理员会话（`CSAC_ADMIN_UID`），支持同源会话 Cookie 或 `Authorization: Bearer <session-token>`。不能以群管理员身份、用户侧 WS v2 或旧式会话扩展替代登录。以下路由均以 `/rpc/UniCsAC.php/` 为前缀；写入用 JSON 请求体。

| 方法与路由 | 参数 | 成功结果 |
| --- | --- | --- |
| `POST admin/registration_codes/create` | `max_uses`，以及 `expires_at` 或 `never_expires: true` | `201`，`data` 为注册码信息，`data.code` 为供复制的完整码 |
| `GET admin/registration_codes/list` | 可选 `limit`、`before_id` | `200`，`data.codes` 为列表，**不返回原码**；`data.next_before_id` 为下一页游标 |
| `GET admin/registration_codes/detail` | `id`；可选 `limit`、`before_uid` | `200`，`data.registration_code.code` 为完整码，`data.redemptions` 为成功注册账号，`data.next_before_uid` 为下一页游标 |
| `POST admin/registration_codes/revoke` | `id` | `200`，单独作废指定码；重复作废不会重置第一次作废时间 |

`max_uses` 是 1 至 2147483647 的整数。`expires_at` 是未来的 Unix 秒时间戳；只有明确提交 `never_expires: true` 才会设为永久。两种有效期设置不能同时使用。

元数据包括 `id`、`status`、`max_uses`、`used_count`、`remaining_uses`、`created_at`、`created_by`、`expires_at`、`revoked_at` 和 `revoked_by`。状态为 `active`（可用）、`exhausted`（用完）、`expired`（到期）或 `revoked`（作废）；`remaining_uses` 仅表示未用配额，不代表到期或作废的码可用。注册明细含 `uid`、`username`、`nickname`、`registered_at`，不含邮箱、密码或会话令牌。所有时间以 Unix 秒返回；永久码的 `expires_at` 为 `null`。

分页默认 30 条，最大 100 条。下一页请求传回对应的 `next_before_id` 或 `next_before_uid`；为 `null` 表示没有更多。作废、用完或到期不会撤销已注册账号的权限。管理员仍能在详情中复制这些码以供核对，但不能再用它们注册。

服务端通过 `CSAC_REGISTRATION_CODE_KEY` 保护可复制原码。启用和备份方法见[部署说明](../deploy/README.md#注册码注册)。本次未添加 Web 或 Android 管理界面。
