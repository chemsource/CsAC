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
| 前端       | flutter web                         |
| 后端       | PHP 7.2+ (原生 MySQLi)               |
| 数据库     | MySQL / MariaDB                      |
| 会话管理   | PHP Session + Cookie                 |
| 文件存储   | 服务器单独目录                        |

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
3. 通过sql文件导入数据库
4. 修改core.php中的数据库配置为自己的数据库，跨域请求为自己的地址
5. 注册管理员账号，确保管理员账号uid为1

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

