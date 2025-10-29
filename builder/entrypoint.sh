#!/usr/bin/env bash
set -euo pipefail

export COMPOSER_ALLOW_SUPERUSER=1     # silence "do not run as root" in containers
export COMPOSER_NO_INTERACTION=1
export COMPOSER_CACHE_DIR="${COMPOSER_CACHE_DIR:-/tmp/composer-cache}"  # ephemeral cache ok

# Where the vendor tree will be written (mounted volume)
TARGET_DIR=${TARGET_DIR:-/opt/vendor}
CONTENT_DIR=${CONTENT_DIR:-/opt/wp-content}
mkdir -p "$TARGET_DIR" "$CONTENT_DIR"

# Minimal composer.json with installers + WP Packagist
cat > /work/composer.json <<'JSON'
{
  "name": "immutable/wp-runtime",
  "type": "project",
  "minimum-stability": "stable",
  "prefer-stable": true,
  "repositories": [
    {"type":"composer","url":"https://wpackagist.org"}
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

# Merge extras (repos, config, allow-plugins, auth proxies, etc.)
if [[ -n "${COMPOSER_JSON_EXTRAS:-}" ]]; then
  echo "$COMPOSER_JSON_EXTRAS" > /work/extras.json
  jq -s '.[0] * .[1]' /work/composer.json /work/extras.json > /work/merged.json
  mv /work/merged.json /work/composer.json
fi

# Prepare args
COMMON_FLAGS="--no-dev --prefer-dist --no-ansi --no-progress --no-scripts"

if [[ -n "${COMPOSER_REQUIRE:-}" ]]; then
  set -x
  composer require $COMMON_FLAGS --working-dir=/work ${COMPOSER_REQUIRE}
  set +x
else
  composer install $COMMON_FLAGS --working-dir=/work
fi

# Copy results to mounted volumes
rm -rf "$TARGET_DIR/vendor" "$TARGET_DIR/composer.lock" "$TARGET_DIR/composer.json"
cp -a /work/vendor "$TARGET_DIR/vendor"
cp -a /work/composer.lock "$TARGET_DIR/composer.lock"
cp -a /work/composer.json "$TARGET_DIR/composer.json"

echo "[builder] vendor ready at $TARGET_DIR"
echo "[builder] wp-content ready at $CONTENT_DIR"