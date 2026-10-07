#!/bin/sh
set -e
cd /app

# The Render dashboard provides APP_KEY; generate one on the fly if it is
# missing so the container never half-works.
if [ -z "${APP_KEY:-}" ]; then
  export APP_KEY="base64:$(php artisan key:generate --show)"
fi

# The Aiven schema already exists; this only applies anything newer/extra.
php artisan migrate --force --no-interaction || true

php artisan storage:link --no-interaction >/dev/null 2>&1 || true

# Render injects the listening port through $PORT (default 10000).
exec php artisan serve --host=0.0.0.0 --port="${PORT:-10000}"