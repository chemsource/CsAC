#!/usr/bin/env bash
set -euo pipefail
umask 077
exec 9>/run/lock/csac-backup.lock
flock 9
cd "$(dirname "$0")/.."
directory=${1:-/opt/csac/backups}
install -d -m 0700 "$directory"
target="$directory/csac-$(date -u +%Y%m%dT%H%M%SZ).sql.gz"
temporary=$(mktemp "$directory/.backup.XXXXXX")
trap 'rm -f "$temporary"' EXIT
docker compose exec -T db sh -c \
    'MYSQL_PWD="$(cat /run/secrets/db_root_password)" mariadb-dump -uroot --lock-all-tables --quick --routines --events --triggers --databases csac' \
    | gzip > "$temporary"
gzip -t "$temporary"
mv "$temporary" "$target"
printf 'Database backup saved: %s\n' "$target"
