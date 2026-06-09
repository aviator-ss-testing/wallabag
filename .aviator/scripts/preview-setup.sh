#!/bin/bash
set -euo pipefail

LOG="/tmp/preview-timing.log"
START=$(date +%s)

t() {
  local now
  now=$(date +%s)
  echo "[$((now - START))s] $1" | tee -a "$LOG"
}

t "Starting wallabag preview setup"

# e2b runs the script as root. Make git operations trust /code.
git config --global --add safe.directory /code
cd /code

t "Starting Redis..."
redis-cli ping >/dev/null 2>&1 || redis-server --daemonize yes
t "Redis ready"

# composer refuses to run plugins as root without this.
export COMPOSER_ALLOW_SUPERUSER=1

# The template image baked the installed deps, the built frontend, and a seed DB
# into /code. The preview launch uses a git fetch fast-path and cleans the tree
# with `git clean -fd` (respects .gitignore), so those gitignored artifacts
# (vendor/, node_modules/, web/build/*, data/db/wallabag.sqlite) survive. We only
# redo a heavy step when the runbook branch actually changed the relevant files
# vs the commit the image was built from — recorded at /preview-image-sha
# (outside /code, where the launch clean can't delete it).
BASE_SHA=""
[ -f /preview-image-sha ] && BASE_SHA=$(cat /preview-image-sha)
if [ -n "$BASE_SHA" ] && git cat-file -e "$BASE_SHA" 2>/dev/null; then
  CHANGED=$(git diff --name-only "$BASE_SHA" HEAD 2>/dev/null || echo "__ALL__")
else
  CHANGED="__ALL__"
  t "  (no usable baked SHA — running full setup)"
fi
# changed <regex> -> true if the baked->HEAD diff touched a matching path
# (or if we have no reference and must assume everything changed).
changed() { [ "$CHANGED" = "__ALL__" ] || echo "$CHANGED" | grep -qE "$1"; }

# Database: the baked seed survives the launch; only act if it's missing/empty.
mkdir -p data/db
if [ ! -s data/db/wallabag.sqlite ]; then
  t "  DB missing/empty — running migrations"
  php bin/console doctrine:migrations:migrate --no-interaction --env=dev || true
fi
chmod 666 data/db/wallabag.sqlite 2>/dev/null || true

# PHP deps: reinstall only if vendor is gone or the branch changed composer files.
if [ ! -d vendor ] || changed '^composer\.(json|lock)$'; then
  t "  composer install"
  composer install --no-interaction --prefer-dist --no-scripts \
    || t "  WARN: composer install failed — using baked vendor/"
else
  t "  composer unchanged — skip"
fi

# Node deps: reinstall only if node_modules is gone or the branch changed them.
if [ ! -d node_modules ] || changed '^(package\.json|yarn\.lock)$'; then
  t "  yarn install"
  yarn install --frozen-lockfile \
    || t "  WARN: yarn install failed — using baked node_modules/"
else
  t "  node_modules unchanged — skip"
fi

# Frontend: rebuild only if the build output is gone or assets/templates changed.
if [ ! -d web/build ] || changed '^(assets/|webpack\.config\.js|package\.json|templates/)'; then
  t "  yarn build:dev"
  yarn build:dev || t "  WARN: yarn build:dev failed — using baked web/build/"
else
  t "  frontend unchanged — skip"
fi

# PREVIEW_URL is injected by Aviator's preview system with the sandbox's public
# URL. Wallabag uses WALLABAG_BASE_URL for asset/link generation.
export WALLABAG_BASE_URL="${PREVIEW_URL:-http://127.0.0.1:8000}"

t "Starting wallabag web server on port 8000..."
mkdir -p /var/log/app
setsid php bin/console server:run 0.0.0.0:8000 --env=dev \
  < /dev/null > /var/log/app/wallabag.log 2>&1 &
disown

# Don't report ready until the port actually accepts connections.
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
