#!/usr/bin/env bash
set -euo pipefail

# Where the vendor tree will be written (mounted volume)
TARGET_DIR=${TARGET_DIR:-/opt/vendor}
CONTENT_DIR=${CONTENT_DIR:-/opt/wp-content}
# mkdir -p "$TARGET_DIR"
mkdir -p "$TARGET_DIR" "$CONTENT_DIR"

# Create a minimal composer.json; allow extras from env.
# Default repo includes WP Packagist for plugins/themes via Composer.
# cat > /work/composer.json <<'JSON'
# {
#   "name": "immutable/wp-runtime",
#   "type": "project",
#   "minimum-stability": "stable",
#   "prefer-stable": true,
#   "repositories": [
#     {"type": "composer", "url": "https://wpackagist.org"}
#   ],
#   "require": {}
# }
# JSON
cat > /work/composer.json <<'JSON'
{
  "name": "immutable/wp-runtime",
  "type": "project",
  "minimum-stability": "stable",
  "prefer-stable": true,
  "repositories": [
    {"type": "composer", "url": "https://wpackagist.org"}
  ],
  "require": {
    "composer/installers": "^2.3"
  },
  "extra": {
    "installer-paths": {
      "/opt/wp-content/plugins/{$name}/": ["type:wordpress-plugin"],
      "/opt/wp-content/themes/{$name}/":  ["type:wordpress-theme"],
      "/opt/wp-content/mu-plugins/{$name}/": ["type:wordpress-muplugin"]
    }
  }
}
JSON

# Optional JSON fragment override/merge (e.g., extra repos, config)
if [[ -n "${COMPOSER_JSON_EXTRAS:-}" ]]; then
  # naive merge: append then jq merge if jq exists; otherwise simple concat fallback
  if command -v jq >/dev/null 2>&1; then
    echo "$COMPOSER_JSON_EXTRAS" > /work/extras.json
    jq -s '.[0] * .[1]' /work/composer.json /work/extras.json > /work/merged.json
    mv /work/merged.json /work/composer.json
  else
    # Best effort: if jq isn't present in this image in future, skip.
    echo "Warning: jq not found; COMPOSER_JSON_EXTRAS ignored." >&2
  fi
fi

# Parse space-separated package specs from env, e.g.:
# COMPOSER_REQUIRE="wpackagist-plugin/woocommerce:^9.1 wpackagist-plugin/wp-mail-smtp:*"
if [[ -n "${COMPOSER_REQUIRE:-}" ]]; then
  set -x
  composer --no-interaction --no-ansi --working-dir=/work require --no-dev --prefer-dist ${COMPOSER_REQUIRE}
  set +x
else
  # still create composer.lock & vendor dir, even if empty
  composer --no-interaction --no-ansi --working-dir=/work install --no-dev --prefer-dist
fi

# Install to TARGET_DIR/vendor (copy), preserving autoload files
rm -rf "$TARGET_DIR/vendor" "$TARGET_DIR/composer.lock" "$TARGET_DIR/composer.json"
cp -a /work/vendor "$TARGET_DIR/vendor"
cp -a /work/composer.lock "$TARGET_DIR/composer.lock"
cp -a /work/composer.json "$TARGET_DIR/composer.json"

# echo "Composer vendor prepared at $TARGET_DIR"

# Important: ensure wp-content artifacts land in CONTENT_DIR
# (composer/installers already wrote to /opt/wp-content via installer-paths)
echo "Content prepared at $CONTENT_DIR and vendor at $TARGET_DIR"