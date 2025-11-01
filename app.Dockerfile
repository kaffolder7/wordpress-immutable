# syntax=docker/dockerfile:1.6

ARG BASE_IMAGE="wordpress:6.8.3-php8.3-apache@sha256:d58bf36cd0911273190beb740d8c7fad5fa30f35a4198131deb11573709ad4c1"   # default as a fallback
FROM ${BASE_IMAGE}

# WP-CLI (pin + verify) & Composer (pin + verify)
ARG WPCLI_VERSION=2.10.0
ARG COMPOSER_VERSION=2.7.7

# System deps (no php-cli needed; php is already in the WP image)
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends curl less unzip git ca-certificates openssl; \
    rm -rf /var/lib/apt/lists/*; \
    \
    # --- WP-CLI (pin + verify SHA512) ---
    curl -fsSLo /usr/local/bin/wp "https://github.com/wp-cli/wp-cli/releases/download/v${WPCLI_VERSION}/wp-cli-${WPCLI_VERSION}.phar"; \
    curl -fsSLo /tmp/wp.phar.sha512 "https://github.com/wp-cli/wp-cli/releases/download/v${WPCLI_VERSION}/wp-cli-${WPCLI_VERSION}.phar.sha512"; \
    echo "$(cat /tmp/wp.phar.sha512)  /usr/local/bin/wp" | sha512sum -c -; \
    chmod +x /usr/local/bin/wp; \
    \
    # --- Composer (installer with SHA-384 verification; pinned version) ---
    curl -fsSLo /tmp/composer-setup.php https://getcomposer.org/installer; \
    curl -fsSLo /tmp/composer-setup.sig https://composer.github.io/installer.sig; \
    php -r ' \
    $sig = trim(file_get_contents("/tmp/composer-setup.sig")); \
    $file = "/tmp/composer-setup.php"; \
    if (hash_file("sha384", $file) !== $sig) { \
        fwrite(STDERR, "ERROR: Invalid Composer installer checksum\n"); \
        unlink($file); \
        exit(1); \
    } \
    '; \
    php /tmp/composer-setup.php --no-ansi --install-dir=/usr/local/bin --filename=composer --version="${COMPOSER_VERSION}"; \
    composer --version; \
    rm -f /tmp/wp.phar.sha512 /tmp/composer-setup.php /tmp/composer-setup.sig

# Install other PHP extensions for media
# The base image has a good spread, but for WordPress media you’ll usually want gd, exif, maybe imagick. The official image has gd compiled in; if you rely on imagick, add:
# RUN apt-get update && apt-get install -y --no-install-recommends \
#     imagemagick ghostscript && rm -rf /var/lib/apt/lists/*

# PHP customizations
COPY php/custom.ini $PHP_INI_DIR/conf.d/custom.ini

# Health endpoint
COPY healthz.php /var/www/html/healthz.php

# Readiness endpoint
COPY readyz.php /var/www/html/readyz.php

# Ship a default `.htaccess` and avoid runtime writes
# With `read_only: true` and wp_content mounted RO, WordPress can’t write permalinks rules.
# So, let's bake a standard `.htaccess` into the image so toggling permalinks in wp-admin isn’t required.
COPY .htaccess /var/www/html/.htaccess

# Apache hardening drop-ins--
# Adds a tiny conf file to trim headers + disable directory listings
RUN printf '%s\n' \
    'ServerTokens Prod' \
    'ServerSignature Off' \
    '<Directory "/var/www/html">' \
    '  Options -Indexes' \
    '  AllowOverride All' \
    '</Directory>' \
    > /etc/apache2/conf-available/harden.conf \
    && a2enconf harden

# Basic header hardening
RUN a2enmod headers \
    && printf '%s\n' \
        'Header always set X-Frame-Options "SAMEORIGIN"' \
        'Header always set X-Content-Type-Options "nosniff"' \
        'Header always set Referrer-Policy "strict-origin-when-cross-origin"' \
        'Header always set Permissions-Policy "geolocation=(), camera=(), microphone=()"' \
    > /etc/apache2/conf-available/security-headers.conf \
    && a2enconf security-headers

# Trust the real client IP behind Cloudflare. Enable `mod_remoteip` and map `CF-Connecting-IP` so WordPress sees the real client IP (affects rate-limit/abuse plugins and logs)
# Cloudflare egress ranges (v4+v6). Update with `scripts/update-cloudflare-ips.sh`
# See header inside the file for "Generated:" timestamp & source URL.
COPY apache/remoteip-cloudflare.conf /etc/apache2/conf-available/remoteip-cloudflare.conf
RUN a2enmod remoteip && a2enconf remoteip-cloudflare
# -- Note: Keep `RemoteIPHeader CF-Connecting-IP` (primary) and do not also trust `X-Forwarded-For` unless you have a compelling reason. If you must, prefer `CF-Connecting-IP` and treat `X-Forwarded-For` only as a fallback.
# -- Note: If you ever put another proxy between CF and Apache (e.g., an Nginx forwarder or a container network hop), list its egress CIDRs as `RemoteIPInternalProxy` so RemoteIP processes the headers in the right hop order.

# Extract the ISO timestamp from the conf header (first match after "Generated:")
ARG CF_IPS_TS
# (We’ll set CF_IPS_TS from the workflow; see below)

LABEL org.opencontainers.image.cloudflare_ips.generated="${CF_IPS_TS}" \
      org.opencontainers.image.cloudflare_ips.source="https://www.cloudflare.com/ips/"

# Log the real client IP with `mod_remoteip`
# -- Make sure your Apache log format uses `%a` (the client IP after RemoteIP) so logs/IDS/rate-limit plugins work correctly.
RUN printf '%s\n' \
    'LogFormat "%a %l %u %t \\"%r\\" %>s %b \\"%{Referer}i\\" \\"%{User-Agent}i\\"" combined_remoteip' \
    > /etc/apache2/conf-available/logformat-remoteip.conf \
    && a2enconf logformat-remoteip

# Apache logs: actually use the remote IP format
# -- Use the new format (above) so rate-limit/IDS tooling sees the real client IP (post-RemoteIP).
RUN printf '%s\n' \
    'CustomLog ${APACHE_LOG_DIR}/access.log combined_remoteip' \
    > /etc/apache2/conf-available/customlog-remoteip.conf \
    && a2enconf customlog-remoteip

# Helpful cache headers for static assets (CF honors origin headers)
# -- Cloudflare will cache regardless, but good origin headers reduce revalidation and help any non-CF hop.
RUN a2enmod expires && printf '%s\n' \
    '<IfModule mod_expires.c>' \
    '  ExpiresActive On' \
    '  <LocationMatch "^/wp-(content|includes)/.*\.(css|js|png|jpg|jpeg|gif|svg|webp|woff2?)$">' \
    '    ExpiresDefault "access plus 30 days"' \
    '    Header set Cache-Control "public, max-age=2592000, immutable"' \
    '  </LocationMatch>' \
    '</IfModule>' \
    > /etc/apache2/conf-available/static-cache.conf \
    && a2enconf static-cache

# Add X-Robots-Tag: noindex automatically for non-prod
# -- This keeps staging/dev out of search engines without flipping WP settings.
RUN printf '%s\n' \
    '<IfModule mod_headers.c>' \
    '  SetEnvIfExpr "!reqenv(WP_ENVIRONMENT_TYPE) || reqenv(WP_ENVIRONMENT_TYPE) != '\''production'\''" is_nonprod' \
    '  Header always set X-Robots-Tag "noindex, nofollow" env=is_nonprod' \
    '</IfModule>' \
    > /etc/apache2/conf-available/robots-nonprod.conf \
    && a2enconf robots-nonprod

# Ensure `WP_ENVIRONMENT_TYPE` is visible to Apache rules
# -- Pass it explicitly so it’s always present in the request env.
RUN printf '%s\n' \
    'PassEnv WP_ENVIRONMENT_TYPE' \
    > /etc/apache2/conf-available/passenv.conf \
    && a2enconf passenv

# Silence the Apache FQDN warning
RUN printf 'ServerName localhost\n' > /etc/apache2/conf-available/fqdn.conf && a2enconf fqdn

# Assert HTTPS when CF forwards it
# -- Prevents mixed-content/redirect loop edge cases when origin sees http but the request was HTTPS at CF.
RUN printf '%s\n' \
    'SetEnvIfNoCase X-Forwarded-Proto "^https$" HTTPS=on' \
    > /etc/apache2/conf-available/https-forwarded.conf \
    && a2enconf https-forwarded

# MU plugins: env loader + hardening
RUN mkdir -p /var/www/html/wp-content/mu-plugins
COPY mu-plugins/ /var/www/html/wp-content/mu-plugins/

# Tighten perms (owned by www-data; image still writable during build)
RUN chown -R www-data:www-data /var/www/html

# Optional: default to a small Apache prefork to keep memory down
ENV APACHE_RUN_USER=www-data APACHE_RUN_GROUP=www-data

# Nothing else at runtime should mutate the image; we'll set read_only in Compose.