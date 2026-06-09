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

# e2b runs the script as root. Make sure /code is accessible to git operations.
git config --global --add safe.directory /code

cd /code

t "Starting Redis..."
redis-cli ping >/dev/null 2>&1 || redis-server --daemonize yes
t "Redis ready"

# The template image pre-installs deps and a seed DB into $DEPS_CACHE. That
# dir lives outside /code, so it survives the fresh `git clone` the preview
# system does into /code on every launch. We seed the freshly-cloned workspace
# from it here — copying is far faster than a cold composer/yarn install — and
# only fall back to a real install when the cache is absent or the branch
# changed the lockfiles.
DEPS_CACHE="/opt/wallabag-deps"

# e2b runs this script as root; composer refuses to run plugins as root
# without this. The seeded vendor came from a root build, so installs need it.
export COMPOSER_ALLOW_SUPERUSER=1

# Strategy: seed deps from the cache (a plain copy, fast and engine-check-free),
# then *try* to reconcile to the repo's exact lockfile. The reconcile is
# best-effort — if it fails (e.g. the image's toolchain doesn't match the
# repo's engine requirements) we keep the seeded deps so the preview still
# boots rather than dying on a `set -e`.
t "Setting up PHP dependencies..."
if [ ! -d /code/vendor ] && [ -d "$DEPS_CACHE/vendor" ]; then
  t "  seeding vendor/ from $DEPS_CACHE"
  cp -a "$DEPS_CACHE/vendor" /code/vendor
fi
if [ ! -d /code/vendor ] || ! cmp -s /code/composer.lock "$DEPS_CACHE/composer.lock" 2>/dev/null; then
  t "  reconciling composer deps to repo lockfile"
  composer install --no-interaction --prefer-dist --optimize-autoloader \
    || t "  WARN: composer install failed — continuing with seeded vendor/"
else
  t "  vendor/ matches cache"
fi

t "Setting up Node dependencies..."
if [ ! -d /code/node_modules ] && [ -d "$DEPS_CACHE/node_modules" ]; then
  t "  seeding node_modules/ from $DEPS_CACHE"
  cp -a "$DEPS_CACHE/node_modules" /code/node_modules
fi
if [ ! -d /code/node_modules ] || ! cmp -s /code/yarn.lock "$DEPS_CACHE/yarn.lock" 2>/dev/null; then
  t "  reconciling node deps to repo lockfile"
  yarn install --frozen-lockfile \
    || t "  WARN: yarn install failed — continuing with seeded node_modules/"
else
  t "  node_modules/ matches cache"
fi

# Rebuild the frontend so the branch's asset/template changes are reflected.
# Best-effort for the same reason as above.
t "Building frontend..."
yarn build:dev || t "  WARN: yarn build:dev failed — serving prebuilt assets"
t "Frontend build done"

# Seed the prebuilt sqlite DB (baked into $DEPS_CACHE). Without it every
# request 500s on missing tables (e.g. wallabag_internal_setting).
t "Setting up database..."
mkdir -p /code/data/db
if [ ! -f /code/data/db/wallabag.sqlite ]; then
  if [ -f "$DEPS_CACHE/data/db/wallabag.sqlite" ]; then
    t "  seeding wallabag.sqlite from $DEPS_CACHE"
    cp "$DEPS_CACHE/data/db/wallabag.sqlite" /code/data/db/wallabag.sqlite
  else
    t "  no baked DB — running migrations"
    php bin/console doctrine:migrations:migrate --no-interaction --env=dev || true
  fi
fi
chmod 666 /code/data/db/wallabag.sqlite 2>/dev/null || true

# PREVIEW_URL is injected by Aviator's preview system with the sandbox's
# public URL. Wallabag uses WALLABAG_BASE_URL for asset/link generation.
export WALLABAG_BASE_URL="${PREVIEW_URL:-http://127.0.0.1:8000}"

t "Starting wallabag web server on port 8000..."
# Same approach as local development: Symfony's built-in web server in dev
# mode. The Symfony Web Debug Toolbar is disabled via app/config/config_dev.yml
# (web_profiler.toolbar: false) so the UI is clean.
mkdir -p /var/log/app
setsid php bin/console server:run 0.0.0.0:8000 --env=dev \
  < /dev/null > /var/log/app/wallabag.log 2>&1 &
disown

# Don't report "ready" until the port actually accepts connections — the old
# script logged success unconditionally, masking a server that died on boot.
t "Waiting for server on port 8000..."
for i in $(seq 1 20); do
  if curl -sf -o /dev/null http://127.0.0.1:8000/; then
    t "Wallabag is up on port 8000"
    break
  fi
  if [ "$i" -eq 20 ]; then
    t "ERROR: wallabag did not come up on port 8000 — last log lines:"
    tail -40 /var/log/app/wallabag.log | tee -a "$LOG" || true
    exit 1
  fi
  sleep 1
done

t "Preview environment ready."
