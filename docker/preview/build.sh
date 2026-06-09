#!/bin/bash
# Build the wallabag preview e2b template image.
#
# Usage (run from the wallabag repo root):
#   bash docker/preview/build.sh local   # local docker build only
#   bash docker/preview/build.sh e2b     # build + push to e2b

set -euo pipefail

MODE="${1:-local}"

case "$MODE" in
  local)
    echo "Building wallabag-preview Docker image locally..."
    docker build \
      -f docker/preview/Dockerfile \
      --platform linux/amd64 \
      -t wallabag-preview:test \
      .
    ;;
  e2b)
    echo "Building and pushing wallabag-preview template to e2b..."
    e2b template build \
      --config docker/preview/e2b.toml \
      --path . \
      --memory-mb 4096 \
      --cpu-count 4
    ;;
  *)
    echo "Usage: $0 {local|e2b}" >&2
    exit 1
    ;;
esac

echo "Build complete."
