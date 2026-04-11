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

# Set up the wallabag environment for prod so the Symfony debug toolbar is off.
export APP_ENV=prod
export APP_DEBUG=0
export SYMFONY_ENV=prod

# PREVIEW_URL is injected by Aviator's preview system with the sandbox's public
# URL. Wallabag uses DOMAIN_NAME for generating asset URLs and redirects.
export DOMAIN_NAME="${PREVIEW_URL:-http://127.0.0.1:8000}"

cd /code

t "Starting Redis..."
redis-cli ping >/dev/null 2>&1 || redis-server --daemonize yes
t "Redis ready"

t "Installing any new PHP dependencies..."
composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader 2>/dev/null || true
t "Composer done"

t "Installing any new Node dependencies..."
yarn install --frozen-lockfile 2>/dev/null || true
t "Yarn done"

t "Building frontend..."
yarn build:dev
t "Frontend build done"

t "Warming Symfony cache..."
php bin/console cache:clear --env=prod --no-debug 2>&1 | tail -3 || true
t "Cache warmed"

t "Starting php-fpm..."
setsid php-fpm --daemonize
t "php-fpm started"

t "Starting nginx..."
setsid nginx
t "Nginx started"

t "Preview environment ready."
