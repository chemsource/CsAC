#!/bin/sh
set -eu

site_dir=${CSAC_CERT_SITE_DIR:-/opt/1panel/www/shared/certbot}
certificate="$site_dir/letsencrypt/live/csac.chat/fullchain.pem"
state_file="$site_dir/letsencrypt/.csac-loaded-sha256"
# Both sites share this Certbot configuration directory and lock.
exec 9>/run/lock/unour-certificate.lock
flock -n 9 || exit 0
test -s "$certificate"

renew_status=0
docker run --rm --name csac-certbot \
    --volume "$site_dir/acme:/var/www/acme" \
    --volume "$site_dir/letsencrypt:/etc/letsencrypt" \
    certbot/certbot:v5.8.0 renew --quiet --cert-name csac.chat \
    --webroot --webroot-path /var/www/acme --preferred-challenges http \
    "$@" || renew_status=$?

fingerprint=$(sha256sum "$certificate")
fingerprint=${fingerprint%% *}
loaded=''
if [ -f "$state_file" ]; then loaded=$(cat "$state_file"); fi
if [ "$loaded" != "$fingerprint" ]; then
    set -- $(docker ps -q --filter label=com.docker.compose.service=openresty)
    test "$#" -eq 1
    docker exec "$1" nginx -t
    docker exec "$1" nginx -s reload
    temporary=$(mktemp "$state_file.XXXXXX")
    trap 'rm -f "$temporary"' 0
    printf '%s\n' "$fingerprint" > "$temporary"
    chmod 0600 "$temporary"
    mv -f "$temporary" "$state_file"
fi
exit "$renew_status"
