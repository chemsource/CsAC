# CsAC Docker 部署

后端包含聊天 RPC、ServerBot、ACOP、eMApps 四个 Go 进程，共用独立 MariaDB。`compose.yaml` 使用持久卷保存数据库、Bot 库、小程序包和签名密钥；聊天上传目录使用 `CSAC_DATA_ROOT`。应用端口只监听宿主机回环地址，数据库不发布端口。

正式服务目录为 `/opt/csac`。私密配置放在该目录的 `.env`，数据库 root 密码放在 `secrets/mysql-root-password`，两者权限均为 `0600`，不进入 Git 或 Docker 镜像。数据库应用密码、缓存盐、Bot 内部密钥和 ACOP 会话密钥应分别随机生成。

```sh
docker build -t csac-backend:版本号 .
docker compose config --quiet
docker compose up -d --no-build --wait
docker compose ps
```

`CSAC_RELEASE` 必须与镜像版本号一致。首次启动空卷时加载 `database_template.sql`；恢复已有数据库应先停止四个应用进程，备份当前库，再导入原始 SQL，核对行数后启动应用。不要使用 `down -v` 删除正式卷。已有账号和管理员 UID 沿用导入数据库，不再注册新的首个管理员。

## GitHub 自动部署

推送到 `main` 后，Actions 执行 Go race 检查、vet 和四个服务的构建，再构建 Linux amd64 生产镜像。验证通过后通过 SSH 上传镜像并部署。PR 执行检查和镜像构建，工作流也支持从 `main` 手动运行。

连接信息通过仓库的 Actions Secrets 配置。

| Secret | 内容 |
| --- | --- |
| `CSAC_DEPLOY_HOST` | 部署服务器地址 |
| `CSAC_DEPLOY_PORT` | SSH 端口 |
| `CSAC_DEPLOY_USER` | 受限部署账号 |
| `CSAC_DEPLOY_KEY` | 该账号的专用 Ed25519 私钥 |
| `CSAC_KNOWN_HOSTS` | 预先核实的 SSH 主机公钥记录 |

部署接收器安装在 `/usr/local/sbin/csac-ci-receive`，配置为 `/etc/csac/deploy.json`，模板见 `ci-config.example.json`。SSH 与 sudo 约束分别见 `csac-ci.sshd.example`、`csac-ci.sudoers.example`，部署账号的主目录和公钥文件由 root 管理。SSH 配置应在现有通配 `Match` 规则之前包含，再通过 `sshd -t` 验证和重载。

账号通过强制命令接收 `check` 或 `deploy <commit-sha> <run-number> <attempt> <archive-sha256>`。镜像按提交、运行编号和重试次数命名，上传后核对 SHA-256、镜像引用、非 root 用户及提交标签。

接收器使用 `/opt/csac/compose.yaml` 和 `.env` 更新 RPC、ServerBot、ACOP、eMApps。每次部署先保存数据库备份及四个容器各自的镜像，随后等待容器和 HTTP 健康检查。失败时恢复原环境文件和各容器的镜像，记录保存在 `/opt/csac/backups/ci-*` 与 `/opt/csac/releases/ci-*.json`。持久化部署记录用于恢复中断任务，文件锁和运行序号用于串行部署及跳过过期任务。

部署完成后，CI 通过 HTTPS 验证 `csac.chat/healthz`。数据库连接参数、缓存盐及服务内部密钥从服务器的私密 `.env` 读取。

邮箱验证码、邮箱登录和找回账号依赖 SMTP。将 RPC 的 `CSAC_SMTP_*` 和 ACOP 的 `ACOP_SMTP_*` 配置在服务器私密 `.env` 中，再重新创建相应容器。`CSAC_REQUIRE_EMAIL_VERIFICATION` 同时控制注册和已有账号的验证要求；可用 `CSAC_REQUIRE_REGISTER_EMAIL_VERIFICATION` 和 `CSAC_REQUIRE_EXISTING_USER_EMAIL_VERIFICATION` 分别覆盖。开启已有账号验证前，应确认未绑定邮箱的用户可以完成绑定。

## 域名与前端

生产站点已通过 1Panel 本机管理接口创建为反向代理网站，代号为 `csac`。可以在「网站」中查看域名、日志、HTTPS 和配置文件。Go 服务继续由 `/opt/csac/compose.yaml` 管理。

网关配置分为三个文件。共享配置需要先于站点加载，站点的代理目录由 1Panel 的启停操作管理。

| 仓库文件 | 服务器位置 |
| --- | --- |
| `openresty-http.conf` | `/opt/1panel/www/conf.d/00-00-csac-http.conf` |
| `openresty.conf` | `/opt/1panel/www/conf.d/csac.conf` |
| `openresty-routes.conf` | `/opt/1panel/www/sites/csac/proxy/root.conf` |

修改后先执行 OpenResty 容器内的 `nginx -t`，通过后再平滑重载。面板中的配置编辑会执行检查与重载。

| 入口 | 用途 |
| --- | --- |
| `https://csac.chat/` | Flutter Web 静态页面，目录为 `/opt/1panel/www/sites/csac/index` |
| `/rpc/UniCsAC.php?route=…` | 现有客户端的聊天 API |
| `/api/…` | 聊天 API 的路径形式 |
| `/ws`、`/websocket.php` | 现有聊天 WebSocket |
| `/ws/v2`、`/rpc/ws/v2` | 用户侧 JSON-RPC、实时事件和断线回放，见 [接入说明](../docs/websocket.md) |
| `/acop`、`/acop/…` | 开放平台 API |
| `/bot/api/…`、`/bot/ws` | Bot API 与 WebSocket |
| `/emapps/…` | 小程序 API、目录、包下载 |
| `/healthz` | 聊天主服务健康检查 |

站点监听 HTTPS 和 QUIC（UDP 443）；Cloudflare 的 HTTP/3 设置需保持开启。`CSAC_WS_ORIGINS` 控制允许的浏览器来源，`CSAC_WS_RETENTION_DAYS`（1–30，默认 7）设置回放与幂等记录保留期，`CSAC_WS_MAX_CONNECTIONS`（16–4096，默认 256）限制单进程连接数。首次启用时，`friend_relation` 和 `friend_request` 从 MyISAM 转换为 InnoDB，使业务变更与事件写入保持事务一致；升级前应备份数据库。

内部 Bot 和 eMApps 接口不公开代理。网关只接受本站来源或无 Origin 的原生客户端请求，并清洗代理地址头；访问日志不记录请求参数、Cookie 或认证头。后续 Flutter Web 只需将构建结果放入静态目录，继续使用同一域名的 API 和 WebSocket。

证书源文件存放在 `/opt/1panel/www/shared/certbot/letsencrypt/live/csac.chat/`，HTTP 验证目录为 `/opt/1panel/www/shared/certbot/acme`，Cloudflare 可信代理配置为 `/opt/1panel/www/shared/cloudflare-realip.conf`。这些共享文件独立于两个站点的目录。

1Panel 以本地导入方式登记证书，并管理站点的 `ssl/fullchain.pem` 与 `ssl/privkey.pem`。`csac-certificate.timer` 只续期 `csac.chat`，与游戏的 `uno.csac.chat` 续期分开，使用同一文件锁避免并发操作证书目录。

`sync-panel-certificate.py` 通过 root 可访问的 `/etc/1panel/agent.sock` 更新证书记录、有效期和站点证书副本。恢复这项同步时，将脚本安装到 `/usr/local/libexec/1panel-sync-certificate.py`，并配置服务的 `ExecStartPost`。

```sh
install -m 0755 deploy/sync-panel-certificate.py /usr/local/libexec/1panel-sync-certificate.py
install -d /etc/systemd/system/csac-certificate.service.d
cat > /etc/systemd/system/csac-certificate.service.d/1panel.conf <<'EOF'
[Service]
Environment=CSAC_CERT_SITE_DIR=/opt/1panel/www/shared/certbot
ExecStartPost=/usr/bin/python3 /usr/local/libexec/1panel-sync-certificate.py csac.chat
EOF
systemctl daemon-reload
```

`unour-certificate.service` 使用同一脚本同步 `uno.csac.chat`，其共享目录变量为 `UNOUR_SITE_DIR`。证书续期由现有 Certbot 定时任务负责，1Panel 显示证书为本地导入。

## 备份与维护

```sh
bash /opt/csac/deploy/backup.sh
sh /opt/csac/deploy/renew-certificate.sh --dry-run --no-random-sleep-on-renew
systemctl list-timers csac-backup.timer csac-certificate.timer
```

`csac-backup.timer` 每日保存数据库备份到 `/opt/csac/backups`。备份使用全表读锁，保证原库中 MyISAM 表也能获得一致快照。上传文件和小程序密钥所在目录需另行备份；仅 SQL 无法恢复这些文件。备份、SQL 导入文件、运行日志和真实凭据都不进入仓库。
