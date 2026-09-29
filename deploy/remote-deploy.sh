#!/usr/bin/env bash
# Runs ON THE DEMO SERVER. It is the only thing the GitHub deploy key may do:
# ~/.ssh/authorized_keys pins the key to this script with command="…",restrict,
# so the key cannot open a shell, forward ports or run anything else.
#
# The Deploy workflow calls it over SSH with one of:
#   deploy <40-character commit sha>   switch the app to ghcr.io/perf-eng/ladebahn:<sha>
#   status                             print the image the app is running
#
# Only the app container is replaced. The database, its volume and Caddy (with the
# TLS certificate) are never touched — no "down", never "-v".
set -euo pipefail

REPO_DIR="${LADEBAHN_DIR:-$HOME/ladebahn}"
IMAGE_REPO="ghcr.io/perf-eng/ladebahn"
COMPOSE=(docker compose -f compose.prod.yaml)

read -r action sha extra <<< "${SSH_ORIGINAL_COMMAND:-}"
cd "$REPO_DIR"

current_image() { grep -E '^APP_IMAGE=' .env 2>/dev/null | tail -1 | cut -d= -f2- || true; }

case "${action:-}" in
  status)
    echo "running=$(current_image)"
    "${COMPOSE[@]}" ps
    exit 0
    ;;
  deploy)
    ;;
  *)
    echo "usage: deploy <commit-sha> | status" >&2
    exit 2
    ;;
esac

if [ -n "${extra:-}" ] || ! [[ "${sha:-}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "expected: deploy <40-character commit sha>" >&2
  exit 2
fi

image="$IMAGE_REPO:$sha"
previous="$(current_image)"

echo "== Updating compose files from GitHub (main)"
git fetch --quiet origin main
git merge --ff-only --quiet origin/main

echo "== Downloading $image"
docker pull --quiet "$image"

echo "== Switching the app container (database and Caddy untouched)"
set_env() { # set_env NAME VALUE — replace or append one line in .env
  if grep -qE "^$1=" .env; then sed -i "s|^$1=.*|$1=$2|" .env; else printf '%s=%s\n' "$1" "$2" >> .env; fi
}
grep -q 'Set by deploy/remote-deploy.sh' .env || printf '\n# Set by deploy/remote-deploy.sh — what the app runs\n' >> .env
set_env APP_IMAGE "$image"
set_env APP_VERSION "${sha:0:7}"
"${COMPOSE[@]}" up --detach --no-build --no-deps app

echo "previous=${previous:-none}"
echo "deployed=$image"
