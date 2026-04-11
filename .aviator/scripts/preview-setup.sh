#!/bin/bash
set -euo pipefail

LOG="/tmp/preview-timing.log"
START=$(date +%s)

t() {
  local now
  now=$(date +%s)
  local elapsed=$((now - START))
  echo "[${elapsed}s] $1" | tee -a "$LOG"
}

t "Starting wallabag preview setup"

# Ensure /code is writable by the current user (e2b runs the script as root
# but the repo may have been cloned as a different user).
chown -R user:user /code/ 2>/dev/null || true

# php-fpm runs as www-data and needs to write caches/logs/sqlite — chown the
# dirs it touches so it can operate without permission errors.
mkdir -p /code/var/cache /code/var/logs /code/data/db
chown -R www-data:www-data /code/var /code/data
chmod -R g+w /code/var /code/data

# Set up the wallabag environment for prod so the Symfony debug toolbar is off.
export APP_ENV=prod
export APP_DEBUG=0
export SYMFONY_ENV=prod

# PREVIEW_URL is injected by Aviator's preview system with the sandbox's public
# URL. Wallabag uses two env vars for URL generation:
#   - DOMAIN_NAME: used by nginx/docker for server_name
#   - WALLABAG_BASE_URL: used by Symfony (services.yml, config.yml) for
#     generating absolute URLs, asset paths, and redirects. This is the one
#     that matters for avoiding CORS issues and broken links in the preview.
export DOMAIN_NAME="${PREVIEW_URL:-http://127.0.0.1:8000}"
export WALLABAG_BASE_URL="${PREVIEW_URL:-http://127.0.0.1:8000}"

cd /code

t "Starting Redis..."
redis-cli ping >/dev/null 2>&1 || redis-server --daemonize yes
t "Redis ready"

# Diff against the SHA the image was built from to detect what changed on
# the branch. This lets us skip composer/yarn/build when nothing relevant
# changed, cutting preview launch time from ~35s to <5s for typical runs.
IMAGE_SHA=""
if [ -f /code/.preview-image-sha ]; then
  IMAGE_SHA=$(cat /code/.preview-image-sha)
fi
CHANGED_FILES=""
if [ -n "$IMAGE_SHA" ]; then
  git config --global --add safe.directory /code
  CHANGED_FILES=$(git -C /code diff --name-only "$IMAGE_SHA" HEAD 2>/dev/null || echo "")
fi

t "Checking for dependency changes..."
if echo "$CHANGED_FILES" | grep -qE '^composer\.(json|lock)$'; then
  t "  composer.lock changed — installing PHP dependencies"
  composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader
else
  t "  composer unchanged — skipping"
fi

if echo "$CHANGED_FILES" | grep -qE '^(package\.json|yarn\.lock)$'; then
  t "  yarn.lock changed — installing Node dependencies"
  yarn install --frozen-lockfile
else
  t "  yarn unchanged — skipping"
fi

t "Building frontend..."
if echo "$CHANGED_FILES" | grep -qE '^(assets/|webpack\.config\.js|package\.json)'; then
  t "  frontend sources changed — rebuilding"
  yarn build:dev
else
  t "  frontend unchanged — skipping"
fi
t "Frontend build done"

t "Warming Symfony cache..."
php bin/console cache:clear --env=prod --no-debug 2>&1 | tail -3 || true
# cache:clear ran as root and recreated the cache dirs root-owned. Hand them
# back to www-data so php-fpm can write at request time.
chown -R www-data:www-data /code/var
chmod -R g+w /code/var
t "Cache warmed"

t "Starting php-fpm..."
setsid php-fpm --daemonize < /dev/null > /var/log/app/php-fpm.log 2>&1
t "php-fpm started"

t "Starting nginx..."
setsid nginx < /dev/null > /var/log/app/nginx.log 2>&1
t "Nginx started"

t "Preview environment ready."
