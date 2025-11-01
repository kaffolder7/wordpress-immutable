# syntax=docker/dockerfile:1.6

# Contributors: Keep the default digest occasionally refreshed so Renovate can propose PRs off file content as well as CI-time resolution.
ARG BASE_IMAGE="wordpress:6.8.3-php8.3-apache@sha256:d58bf36cd0911273190beb740d8c7fad5fa30f35a4198131deb11573709ad4c1"   # default as a fallback
FROM ${BASE_IMAGE} AS app-base

# Pull Composer from the official image (already pinned & trusted)
ARG COMPOSER_IMAGE="composer:2@sha256:5248900ab8b5f7f880c2d62180e40960cd87f60149ec9a1abfd62ac72a02577c"   # default as a fallback
FROM ${COMPOSER_IMAGE} AS composer-src

FROM app-base

# Extract the ISO timestamp from the conf header (first match after "Generated:")
ARG CF_IPS_TS
# (We’ll set CF_IPS_TS from the workflow; see below)

LABEL org.opencontainers.image.title="wordpress-immutable" \
      org.opencontainers.image.description="Immutable WordPress runtime (Apache/PHP) with Cloudflare RemoteIP, security headers, health/ready endpoints, and read-only wp-content/vendor mounts." \
      org.opencontainers.image.url="https://github.com/kaffolder7/wordpress-immutable" \
      org.opencontainers.image.source="https://github.com/kaffolder7/wordpress-immutable" \
      org.opencontainers.image.documentation="https://github.com/kaffolder7/wordpress-immutable#readme" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.cloudflare_ips.generated="${CF_IPS_TS}" \
      org.opencontainers.image.cloudflare_ips.source="https://www.cloudflare.com/ips/"

# WP-CLI (pin + verify)
ARG WPCLI_VERSION=2.10.0

# System deps just for fetching/verifying wp-cli (we'll purge later)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends curl ca-certificates; \
    \
    curl -fsSLo /usr/local/bin/wp "https://github.com/wp-cli/wp-cli/releases/download/v${WPCLI_VERSION}/wp-cli-${WPCLI_VERSION}.phar"; \
    curl -fsSLo /tmp/wp.phar.sha512 "https://github.com/wp-cli/wp-cli/releases/download/v${WPCLI_VERSION}/wp-cli-${WPCLI_VERSION}.phar.sha512"; \
    echo "$(cat /tmp/wp.phar.sha512)  /usr/local/bin/wp" | sha512sum -c -; \
    chmod +x /usr/local/bin/wp; \
    rm -f /tmp/wp.phar.sha512; \
    \
    # purge fetch-time deps to keep the image small
    apt-get purge -y curl; \
    apt-get autoremove -y; \
    rm -rf /var/lib/apt/lists/*

# Drop-in Composer from official image (no network, no PHP installer)
COPY --from=composer-src /usr/bin/composer /usr/local/bin/composer
# (Optional) If Composer isn’t needed at runtime, delete this line:

# Install other PHP extensions for media
# The base image has a good spread, but for WordPress media you’ll usually want gd, exif, maybe imagick. The official image has gd compiled in; if you rely on imagick, add:
# RUN apt-get update && apt-get install -y --no-install-recommends \
#     imagemagick ghostscript && rm -rf /var/lib/apt/lists/*

# PHP customizations
COPY --link --chown=www-data:www-data --chmod=0644 php/custom.ini $PHP_INI_DIR/conf.d/custom.ini

# Health & readiness endpoints
COPY --chown=www-data:www-data --chmod=0644 healthz.php readyz.php /var/www/html/

# Ship a default `.htaccess` and avoid runtime writes
# With `read_only: true` and wp_content mounted RO, WordPress can’t write permalinks rules.
# So, let's bake a standard `.htaccess` into the image so toggling permalinks in wp-admin isn’t required.
COPY --link --chown=www-data:www-data --chmod=0644 .htaccess /var/www/html/.htaccess

# Configure/harden Apache
COPY apache/*.conf /etc/apache2/conf-available/
RUN a2enmod headers remoteip expires deflate && \
    # Enable brotli if present (falls back to gzip)
    if [ -f /usr/lib/apache2/modules/mod_brotli.so ]; then a2enmod brotli; fi && \
    a2enconf harden security-headers remoteip-cloudflare logformat-remoteip customlog-remoteip static-cache robots-nonprod passenv fqdn https-forwarded compression

# MU plugins: env loader + hardening
RUN mkdir -p /var/www/html/wp-content/mu-plugins
COPY --chown=www-data:www-data --chmod=0644 mu-plugins/ /var/www/html/wp-content/mu-plugins/

# Optional: default to a small Apache prefork to keep memory down
ENV APACHE_RUN_USER=www-data APACHE_RUN_GROUP=www-data

# Nothing else at runtime should mutate the image; we'll set read_only in Compose.