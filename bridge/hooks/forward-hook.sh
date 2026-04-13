#!/bin/bash

set -u

HOOK_URL="${1:-}"
TIMEOUT_SECONDS="${2:-15}"

if [ -z "$HOOK_URL" ]; then
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  exit 0
fi

REQUEST_BODY_FILE="$(mktemp -t claudepal-hook-body.XXXXXX)"
RESPONSE_BODY_FILE="$(mktemp -t claudepal-hook-response.XXXXXX)"

cleanup() {
  rm -f "$REQUEST_BODY_FILE" "$RESPONSE_BODY_FILE"
}

trap cleanup EXIT

cat > "$REQUEST_BODY_FILE"

HTTP_STATUS="$(
  curl \
    --silent \
    --show-error \
    --output "$RESPONSE_BODY_FILE" \
    --write-out "%{http_code}" \
    --max-time "$TIMEOUT_SECONDS" \
    --header "Content-Type: application/json" \
    --data-binary "@$REQUEST_BODY_FILE" \
    --request POST \
    "$HOOK_URL" \
    2>/dev/null || printf "000"
)"

case "$HTTP_STATUS" in
  2*)
    if [ -s "$RESPONSE_BODY_FILE" ]; then
      cat "$RESPONSE_BODY_FILE"
    fi
    ;;
esac

exit 0
