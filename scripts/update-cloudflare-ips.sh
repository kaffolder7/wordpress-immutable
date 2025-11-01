#!/usr/bin/env bash
set -euo pipefail

OUT="apache/remoteip-cloudflare.conf"

TMP_V4="$(mktemp)"
TMP_V6="$(mktemp)"

curl -fsSL https://www.cloudflare.com/ips-v4 -o "$TMP_V4"
curl -fsSL https://www.cloudflare.com/ips-v6 -o "$TMP_V6"

{
  echo "# Generated: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  echo "# Source: https://www.cloudflare.com/ips/"
  echo "RemoteIPHeader CF-Connecting-IP"
  echo
  # v4
  while read -r cidr; do
    [[ -z "$cidr" ]] && continue
    echo "RemoteIPTrustedProxy $cidr"
  done < <(grep -E '^[0-9.]+/[0-9]+' "$TMP_V4")
  # v6
  while read -r cidr; do
    [[ -z "$cidr" ]] && continue
    echo "RemoteIPTrustedProxy $cidr"
  done < <(grep -E '^[0-9a-fA-F:]+/[0-9]+' "$TMP_V6")
} > "$OUT"

rm -f "$TMP_V4" "$TMP_V6"

echo "Wrote $OUT"