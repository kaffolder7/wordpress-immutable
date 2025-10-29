# Immutable WordPress Stack (Composer-driven, Multi-Instance Ready)

An immutable, production-oriented WordPress stack designed for **multi-instance** deployment behind **Cloudflare Load Balancer**, with a **dedicated database node** and **S3 offload** for uploads. Composer packages (plugins/themes/mu-plugins) are hydrated by a **vendor builder** service into read-only volumes; the runtime web container stays **stateless and read-only**.

## Highlights

- **Immutable runtime**: `wordpress` image includes PHP ini hardening, WP-CLI, Composer, health endpoints, MU-plugins.
- **Composer-driven content**: a short-lived `vendor` service installs plugins/themes into volumes (`/opt/vendor`, `/opt/wp-content`) from `COMPOSER_REQUIRE`.
- **Zero-drift prod**: web container mounts content **read-only**; uploads go to S3 via `humanmade/s3-uploads`.
- **LB-friendly health**: `/healthz.php` (liveness) and `/readyz.php` (DB-aware readiness) with an optional token.
- **Dev ergonomics**: a `docker-compose.override.yml` bind-mounts `wp-content` for local mutable development.
- **CI ready**: GitHub Actions workflows for **theme releases + Coolify redeploy** and **image build + Trivy scan + push**.

## Repo layout

- **`.github/workflows/`**
    - `build-images.yml` # Build, scan (Trivy), and push app + vendor-builder images
    - `theme-release.yml` # Build theme, tag, bump `COMPOSER_REQUIRE`, trigger Coolify
- **`builder/`**
    - `Dockerfile` # Composer-based builder image
    - `entrypoint.sh` # Installs packages into `/opt/vendor` and `/opt/wp-content`
- **`mu-plugins/`**
    - `000-env-config.php` # Loads vendor autoload, maps S3/SMTP/env → WP constants
    - `001-hardening.php` # Disallow file mods/auto updates in prod
    - `002-disable-users.php` # Simple account disable via user meta
- **`php/`**
    - `custom.ini` # PHP runtime settings
- `app.Dockerfile` # Immutable WordPress runtime (Apache)
- `docker-compose.yml` # Production-ish stack (stateless web + vendor builder)
- `docker-compose.override.yml` # Dev overrides (writable wp-content bind mount)
- `healthz.php` # Liveness probe (no DB)
- `readyz.php` # Readiness probe (checks DB, optional Redis)
- `.env.prod` # `COMPOSER_REQUIRE` baseline, e.g. plugins + theme pin
- `.htaccess` # Permalink rules baked in (immutable)

## How it works

### 1) Build content at deploy time (default)
- Set `COMPOSER_REQUIRE` (space-separated list of Composer packages + versions).
- The `vendor` service runs first, writing:
  - Composer autoload to `/opt/vendor/vendor`
  - Plugins/themes/mu-plugins into `/opt/wp-content/*` (via `composer/installers`)
- The `wordpress` service then mounts those volumes **read-only**.

### 2) Immutable runtime
- Root FS is `read_only: true` with `tmpfs` for `/tmp` and `/var/run`.
- `mu-plugins/000-env-config.php` maps env → constants (S3, SMTP) and finally honors `WORDPRESS_CONFIG_EXTRA` for last-mile overrides.
- `.htaccess` is baked in, avoiding runtime writes.

## Local development

```bash
# Bring up dev stack with writable wp-content and file editors enabled
docker compose -f docker-compose.yml -f docker-compose.override.yml up -d
```

- Edit your theme in `./wp-content/themes/<your-theme>`.
- Run your theme’s build tooling (e.g., `npm run dev`) in that directory.
- **Do not** rely on file editors in production; prod mounts are read-only.

## Production deployment (Coolify + Cloudflare LB)

1. Configure your Coolify app to use this repo and pass environment values:
    - **DB:** `WORDPRESS_DB_HOST`, `WORDPRESS_DB_USER`, `WORDPRESS_DB_PASSWORD`, `WORDPRESS_DB_NAME`
    - **S3:** `S3_UPLOADS_*`
    - **SMTP (optional):** `WP_SMTP_FORCE`, `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, `SMTP_SECURE`
    - **Health token:** `HEALTHZ_TOKEN` (and have CF LB check `/readyz.php?t=$TOKEN`)
    - Any extra **WP `defines()`** via `WORDPRESS_CONFIG_EXTRA`
2. Ensure **uploads go to S3** (`humanmade/s3-uploads`) to keep the web tier stateless.
    - Put **Cloudflare Load Balancer** in front of multiple Coolify-managed instances:
    - Health check path: `/readyz.php?t=$TOKEN`
    - Rate-limit `wp-login.php` and block/limit `xmlrpc.php`
    - Cache static assets (theme CSS/JS, uploads, `wp-includes`)

## Theme release workflow (no app image rebuild)

- The **Theme release & Coolify** redeploy workflow:
    1. Builds your theme (Node/Vite/Webpack)
    2. Creates a git tag (provided or timestamp)
    3. Updates `.env.prod` to pin `COMPOSER_REQUIRE` to the new theme tag
    4. Commits/pushes the env bump
    5. Calls your **Coolify Deploy Hook** to redeploy

At deploy time, the `vendor` service installs that theme version into `wp_content` volume; the app mounts it read-only.

## Building & publishing images (optional)

- The **Build, Scan with Trivy, and Push** workflow:
    - Builds `app` and `vendor-builder` images
    - Scans them with **Trivy** (fails on High/Critical)
    - Pushes multi-arch images to GHCR on pass

Use these images in `docker-compose.yml` by setting:
```yaml
services:
  vendor:
    image: ghcr.io/kaffolder7/wp-vendor-builder:latest
  wordpress:
    image: ghcr.io/kaffolder7/wordpress-immutable:latest
```

## Environment variables

#### Core
- `WORDPRESS_DB_HOST`, `WORDPRESS_DB_USER`, `WORDPRESS_DB_PASSWORD`, `WORDPRESS_DB_NAME`
#### Composer content
- `COMPOSER_REQUIRE` — space-separated package list (e.g., `yourorg/awesome-theme:1.2.3` `wpackagist-plugin/wp-mail-smtp:^4`)
- `COMPOSER_JSON_EXTRAS` — JSON fragment to add repos/config (private VCS, allow-plugins, auth mechanisms)
#### S3 Uploads
- `S3_UPLOADS_BUCKET`, `S3_UPLOADS_REGION`, `S3_UPLOADS_KEY`, `S3_UPLOADS_SECRET`, - `S3_UPLOADS_ENDPOINT`, `S3_UPLOADS_USE_PATH_STYLE_ENDPOINT`
#### SMTP (optional)
- `WP_SMTP_FORCE=true`, `MAIL_FROM`, `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, `SMTP_SECURE`
#### Health
- `HEALTHZ_TOKEN` — optional token for `/healthz.php` and `/readyz.php`
#### WP extras (advanced)
- `WORDPRESS_CONFIG_EXTRA` — final PHP appended via MU-plugin (use sparingly; prefer explicit env → constants)

## Health endpoints
- `GET /healthz.php?t=$HEALTHZ_TOKEN` → **200 OK** if PHP is serving (no DB).
- `GET /readyz.php?t=$HEALTHZ_TOKEN` → **200 OK** only if DB (and optional Redis) is reachable; returns 500 otherwise.

Point Cloudflare LB at `/readyz.php` for origin health. Keep `/healthz.php` for simple container liveness.

## Cron
Run WP Cron out-of-band:

```yaml
services:
  cron:
    image: ghcr.io/kaffolder7/wordpress-immutable:latest
    depends_on:
      mariadb:
        condition: service_healthy
    environment:
      # same DB and WP env as wordpress
    command: bash -lc 'while true; do wp cron event run --due-now --path=/var/www/html --allow-root; sleep 60; done'
```

or, add a tiny external scheduler that runs...
```bash
wp cron event run --due-now --path=/var/www/html --allow-root
```
...with the same env as `wordpress`, so web pods stay boring/fast.

## Security hardening

- Read-only root FS + **tmpfs** for writable dirs.
- **DISALLOW_FILE_MODS/EDIT** in prod; manage code via Composer.
- Apache hardening: `ServerTokens Prod`, `ServerSignature Off`, `-Indexes`, baked `.htaccess`.
- Trivy vulnerability scans on images in CI before push.
- Rate-limit auth endpoints at Cloudflare; disable XML-RPC.

## Troubleshooting

- **Health check failing?** Ensure `HEALTHZ_TOKEN` is set in env and used in the healthcheck URL.
- **Theme not updating in prod?** Confirm `.env.prod` has the new tag in `COMPOSER_REQUIRE` and that the vendor job logs show the pin.
- **Uploads missing?** Verify S3 credentials/endpoint and that the `S3_UPLOADS_*` constants are defined at runtime.

## License

This stack composes multiple upstream projects (WordPress, Composer, etc.). Review and comply with their licenses and any commercial plugin/theme terms.