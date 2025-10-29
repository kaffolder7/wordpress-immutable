FROM wordpress:6.8.3-php8.3-apache

# System deps (curl, less, zip for wp-cli/composer)
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends curl less unzip git; \
    rm -rf /var/lib/apt/lists/*

# Install other PHP extensions for media
# The base image has a good spread, but for WordPress media you’ll usually want gd, exif, maybe imagick. The official image has gd compiled in; if you rely on imagick, add:
# RUN apt-get update && apt-get install -y --no-install-recommends \
#     imagemagick ghostscript && rm -rf /var/lib/apt/lists/*

# WP-CLI (phar) + Composer (phar)
RUN set -eux; \
    curl -sSLo /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar; \
    chmod +x /usr/local/bin/wp; \
    curl -sSLo /usr/local/bin/composer https://getcomposer.org/download/latest-stable/composer.phar; \
    chmod +x /usr/local/bin/composer

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
    > /etc/apache2/conf-available/remoteip-cloudflare.conf \
    && a2enconf remoteip-cloudflare

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