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

# Diff against the SHA the image was built from to detect what changed on
# the branch. This lets us skip composer/yarn/build when nothing relevant
# changed, cutting preview launch time for typical runs.
#
# Fallback: if /code/.preview-image-sha doesn't exist (image was built with
# an older Dockerfile that didn't bake it in), diff against origin/master
# instead. This still detects runbook changes correctly since runbooks branch
# off master.
IMAGE_SHA=""
if [ -f /code/.preview-image-sha ]; then
  IMAGE_SHA=$(cat /code/.preview-image-sha)
elif git -C /code rev-parse --verify origin/master >/dev/null 2>&1; then
  IMAGE_SHA=$(git -C /code rev-parse origin/master)
  t "  (no baked SHA — diffing against origin/master)"
fi
CHANGED_FILES=""
if [ -n "$IMAGE_SHA" ]; then
  CHANGED_FILES=$(git -C /code diff --name-only "$IMAGE_SHA" HEAD 2>/dev/null || echo "")
fi
# If we still have no reference point, assume everything might have changed
# and rebuild the frontend unconditionally (safe fallback).
FORCE_REBUILD="false"
if [ -z "$IMAGE_SHA" ]; then
  FORCE_REBUILD="true"
  t "  (no reference SHA — forcing full rebuild)"
fi

t "Checking for dependency changes..."
if [ "$FORCE_REBUILD" = "true" ] || echo "$CHANGED_FILES" | grep -qE '^composer\.(json|lock)$'; then
  t "  installing PHP dependencies"
  composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader
else
  t "  composer unchanged — skipping"
fi

if [ "$FORCE_REBUILD" = "true" ] || echo "$CHANGED_FILES" | grep -qE '^(package\.json|yarn\.lock)$'; then
  t "  installing Node dependencies"
  yarn install --frozen-lockfile
else
  t "  yarn unchanged — skipping"
fi

t "Building frontend..."
if [ "$FORCE_REBUILD" = "true" ] || echo "$CHANGED_FILES" | grep -qE '^(assets/|webpack\.config\.js|package\.json|templates/)'; then
  t "  rebuilding frontend"
  yarn build:dev
else
  t "  frontend unchanged — skipping"
fi
t "Frontend build done"

# PREVIEW_URL is injected by Aviator's preview system with the sandbox's
# public URL. Wallabag uses WALLABAG_BASE_URL for asset/link generation.
export WALLABAG_BASE_URL="${PREVIEW_URL:-http://127.0.0.1:8000}"

t "Starting wallabag web server on port 8000..."
# Same approach as local development: Symfony's built-in web server in dev
# mode. The Symfony Web Debug Toolbar is disabled via app/config/config_dev.yml
# (web_profiler.toolbar: false) so the UI is clean.
setsid php bin/console server:run 0.0.0.0:8000 --env=dev \
  < /dev/null > /var/log/app/wallabag.log 2>&1 &
disown
t "Wallabag started"

t "Preview environment ready."
