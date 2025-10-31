FROM wordpress:6.8.3-php8.3-apache

# WP-CLI (pin + verify) & Composer (pin + verify)
ARG WPCLI_VERSION=2.10.0
ARG COMPOSER_VERSION=2.7.7

# Composer public key used for phar signatures (tags key).
# Source: https://composer.github.io/pubkeys.html
# Bake this here, so verification does NOT depend on a network fetch of the key.

# copy the public key from the repo into the image
COPY security/composer-tags.pub /usr/local/share/composer-tags.pub

# System deps (curl, less, zip for wp-cli/composer)
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends curl less unzip git ca-certificates openssl ca-certificates; \
    rm -rf /var/lib/apt/lists/*; \
    \
    # --- WP-CLI (pin + verify) ---
    curl -fsSLo /usr/local/bin/wp "https://github.com/wp-cli/wp-cli/releases/download/v${WPCLI_VERSION}/wp-cli-${WPCLI_VERSION}.phar"; \
    curl -fsSLo /tmp/wp.phar.sha512 "https://github.com/wp-cli/wp-cli/releases/download/v${WPCLI_VERSION}/wp-cli-${WPCLI_VERSION}.phar.sha512"; \
    echo "$(cat /tmp/wp.phar.sha512)  /usr/local/bin/wp" | sha512sum -c -; \
    chmod +x /usr/local/bin/wp; \
    \
    # --- Composer (pin + verify RSA signature) ---
    curl -fsSLo /usr/local/bin/composer "https://getcomposer.org/download/${COMPOSER_VERSION}/composer.phar"; \
    curl -fsSLo /tmp/composer.phar.sig "https://getcomposer.org/download/${COMPOSER_VERSION}/composer.phar.sig"; \
    openssl dgst -sha384 -verify /usr/local/share/composer-tags.pub -signature /tmp/composer.phar.sig /usr/local/bin/composer; \
    chmod +x /usr/local/bin/composer; \
    rm -f /tmp/wp.phar.sha512 /tmp/composer.phar.sig

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
# (Keep these ranges in config management so they can be refreshed when Cloudflare updates them.)
RUN a2enmod remoteip rewrite headers \
    && printf '%s\n' \
        'RemoteIPHeader CF-Connecting-IP' \
        '# Trust Cloudflare (update list periodically via config management)' \
        'RemoteIPTrustedProxy 173.245.48.0/20' \
        'RemoteIPTrustedProxy 103.21.244.0/22' \
        'RemoteIPTrustedProxy 103.22.200.0/22' \
        'RemoteIPTrustedProxy 103.31.4.0/22' \
        'RemoteIPTrustedProxy 141.101.64.0/18' \
        'RemoteIPTrustedProxy 108.162.192.0/18' \
        'RemoteIPTrustedProxy 190.93.240.0/20' \
        'RemoteIPTrustedProxy 188.114.96.0/20' \
        'RemoteIPTrustedProxy 197.234.240.0/22' \
        'RemoteIPTrustedProxy 198.41.128.0/17' \
        'RemoteIPTrustedProxy 162.158.0.0/15' \
        'RemoteIPTrustedProxy 104.16.0.0/13' \
        'RemoteIPTrustedProxy 104.24.0.0/14' \
        'RemoteIPTrustedProxy 172.64.0.0/13' \
        'RemoteIPTrustedProxy 131.0.72.0/22' \
        'RemoteIPTrustedProxy 2400:cb00::/32' \
        'RemoteIPTrustedProxy 2606:4700::/32' \
        'RemoteIPTrustedProxy 2803:f800::/32' \
        'RemoteIPTrustedProxy 2405:b500::/32' \
        'RemoteIPTrustedProxy 2405:8100::/32' \
        'RemoteIPTrustedProxy 2a06:98c0::/29' \
        'RemoteIPTrustedProxy 2c0f:f248::/32' \
    > /etc/apache2/conf-available/remoteip-cloudflare.conf \
    && a2enconf remoteip-cloudflare

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

# MU plugins: env loader + hardening
RUN mkdir -p /var/www/html/wp-content/mu-plugins
COPY mu-plugins/ /var/www/html/wp-content/mu-plugins/

# Tighten perms (owned by www-data; image still writable during build)
RUN chown -R www-data:www-data /var/www/html

# Optional: default to a small Apache prefork to keep memory down
ENV APACHE_RUN_USER=www-data APACHE_RUN_GROUP=www-data

# Nothing else at runtime should mutate the image; we'll set read_only in Compose.