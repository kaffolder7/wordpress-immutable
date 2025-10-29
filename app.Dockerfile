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

# Apache hardening drop-in--
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

# MU plugins: env loader + hardening
RUN mkdir -p /var/www/html/wp-content/mu-plugins
COPY mu-plugins/ /var/www/html/wp-content/mu-plugins/

# Tighten perms (owned by www-data; image still writable during build)
RUN chown -R www-data:www-data /var/www/html

# Optional: default to a small Apache prefork to keep memory down
ENV APACHE_RUN_USER=www-data APACHE_RUN_GROUP=www-data

# Nothing else at runtime should mutate the image; we'll set read_only in Compose.