#!/usr/bin/env bash
set -euo pipefail
umask 077

exec 9>/home/ubuntu/farmspot-deploy/deploy.lock
flock -n 9 || exit 0
cd /home/ubuntu/Farmspot
git pull --ff-only origin main

revision=$(git rev-parse HEAD:website)
state=/home/ubuntu/farmspot-deploy/deployed-website
if [[ -f "$state" && $(cat "$state") == "$revision" ]]; then
    exit 0
fi

image="farmspot-web:$revision"
live=farmspot-web-test
previous=farmspot-web-auto-previous
sudo -n docker build -t "$image" ./website

# Keep backups on the host, outside replaceable containers and build contexts.
backup_dir=/home/ubuntu/farmspot-backups/deployments
mkdir -p "$backup_dir"
dump="$backup_dir/$(date -u +%Y%m%dT%H%M%SZ)-$revision.sql.gz"
sudo -n docker exec farmspot-mysql sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysqldump -uroot --single-transaction --no-tablespaces --routines --events farmspot' | gzip > "$dump"
gzip -t "$dump"

# Run migrations before switching traffic. Storage (including migration backups)
# must survive deployment; the live container uses this same persistent volume.
sudo -n docker run --rm --network farmspot-net \
    --env-file /home/ubuntu/farmspot-deploy/web.env \
    -e LOG_CHANNEL=stderr \
    -v farmspot-web-storage:/app/storage \
    --entrypoint php "$image" /app/artisan migrate --force

if sudo -n docker container inspect "$previous" >/dev/null 2>&1; then
    sudo -n docker rm "$previous"
fi
sudo -n docker rename "$live" "$previous"
if sudo -n docker stop "$previous" &&
   sudo -n docker run -d --name "$live" \
      --restart unless-stopped --network farmspot-net \
      --env-file /home/ubuntu/farmspot-deploy/web.env \
      -e APP_URL=https://farmspot-admin.duckdns.org \
      -e SESSION_DRIVER=file -e LOG_CHANNEL=stderr \
      -v farmspot-web-storage:/app/storage \
      -p 127.0.0.1:8000:8000 \
      --entrypoint php "$image" /app/artisan serve --host=0.0.0.0 --port=8000 &&
   status=$(curl --silent --show-error --fail --retry 5 --retry-connrefused \
      --max-time 10 --resolve farmspot-admin.duckdns.org:443:127.0.0.1 \
      --output /dev/null --write-out '%{http_code}' \
      https://farmspot-admin.duckdns.org/login) && [[ "$status" == 200 ]]; then
    printf '%s\n' "$revision" > "$state"
    echo 'FarmSpot deployment and database migrations passed the HTTPS login check.'
else
    sudo -n docker rm -f "$live" >/dev/null 2>&1 || true
    sudo -n docker rename "$previous" "$live"
    sudo -n docker start "$live"
    echo 'Website deployment failed; previous container restarted. Database migrations are retained.' >&2
    exit 1
fi
