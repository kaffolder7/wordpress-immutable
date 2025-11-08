#!/usr/bin/env bash
set -euo pipefail

OUT="apache/remoteip-cloudflare.conf"

TMP_V4="$(mktemp)"
TMP_V6="$(mktemp)"
TMP_OUT="$(mktemp)"

cleanup() { rm -f "$TMP_V4" "$TMP_V6" "$TMP_OUT"; }
trap cleanup EXIT

curl --max-time 10 -fsSL https://www.cloudflare.com/ips-v4 -o "$TMP_V4"
curl --max-time 10 -fsSL https://www.cloudflare.com/ips-v6 -o "$TMP_V6"

# sanity: require at least N lines
test "$(wc -l < "$TMP_V4")" -ge 5 && test "$(wc -l < "$TMP_V6")" -ge 5 || { echo "CF IP list too short"; exit 1; }

{
  echo "# Source: https://www.cloudflare.com/ips/"
  echo "RemoteIPHeader CF-Connecting-IP"
  echo

  # v4 + v6, canonical order, de-duped
  {
    grep -E '^[0-9.]+/[0-9]+' "$TMP_V4"
    grep -E '^[0-9a-fA-F:]+/[0-9]+' "$TMP_V6"
  } | sort -V | uniq | while read -r cidr; do
    [ -z "$cidr" ] && continue
    echo "RemoteIPTrustedProxy $cidr"
  done
} > "$TMP_OUT"

# Only update the tracked file if the content actually changed
if [ ! -f "$OUT" ] || ! cmp -s "$TMP_OUT" "$OUT"; then
  mv "$TMP_OUT" "$OUT"
  echo "Updated $OUT"
else
  echo "No changes in Cloudflare IPs."
fi

# -- Note: Keep `RemoteIPHeader CF-Connecting-IP` (primary) and do not also trust `X-Forwarded-For` unless you have a compelling reason. If you must, prefer `CF-Connecting-IP` and treat `X-Forwarded-For` only as a fallback.
# -- Note: If you ever put another proxy between CF and Apache (e.g., an Nginx forwarder or a container network hop), list its egress CIDRs as `RemoteIPInternalProxy` so RemoteIP processes the headers in the right hop order.