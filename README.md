# Immutable WordPress Stack (Composer-driven, Multi-Instance Ready)

<!-- [![Signed with Sigstore (cosign)](https://img.shields.io/badge/Signed%20with-Sigstore%20cosign-000?style=for-the-badge)](https://docs.sigstore.dev/cosign/overview/) -->
[![Cosign Verified](https://img.shields.io/badge/cosign-verified-2ea44f?style=for-the-badge)](https://docs.sigstore.dev/cosign/overview/)
[![Build & Sign](https://github.com/kaffolder7/wordpress-immutable/actions/workflows/build-images.yml/badge.svg)](https://github.com/kaffolder7/wordpress-immutable/actions/workflows/build-images.yml)
<!-- [![Build & Sign](https://img.shields.io/github/actions/workflow/status/kaffolder7/wordpress-immutable/build-images.yml)](https://github.com/kaffolder7/wordpress-immutable/actions/workflows/build-images.yml) -->

An immutable, production-oriented WordPress stack designed for **multi-instance** deployment behind **Cloudflare Load Balancer**, with a **dedicated database node** and **S3 offload** for uploads. Composer packages (plugins / themes / mu-plugins) are hydrated by a **vendor builder** service into read-only volumes; the runtime web container stays **stateless** and **read-only**.

## Highlights

- **Immutable runtime**: `wordpress` image includes PHP ini hardening, WP-CLI, health/readiness endpoints, MU-plugins. No Composer in runtime.
- **Composer-driven content**: a short-lived `vendor` service installs plugins/themes into volumes (`/opt/vendor`, `/opt/wp-content`) from `COMPOSER_REQUIRE`.
- **Zero-drift prod**: web container mounts content **read-only**; uploads go to S3 via [`humanmade/s3-uploads`](https://github.com/humanmade/S3-Uploads).
- **LB-friendly health**: `/healthz.php` (liveness) and `/readyz.php` (DB-aware readiness) with an optional token.
- **Dev ergonomics**: a `docker-compose.override.yml` bind-mounts `wp-content` for local mutable development.
<!-- - **CI ready**: GitHub Actions workflows for **theme releases + Coolify redeploy** and **image build + Trivy scan + push**. -->
- **CI ready**: GitHub Actions workflow for **image build + Trivy scan + push**.

## Repo layout

- `.github/workflows/`
  - `build-images.yml` &mdash; Build, scan (Trivy), and push app + vendor-builder images
  - `theme-release.yml` &mdash; Build theme, tag, bump `COMPOSER_REQUIRE`, trigger Coolify
- `apache/*` &mdash; Various Apache headers/RemoteIP/hardening configuration files
- `builder/`
  - `Dockerfile` &mdash; Composer-based builder image
  - `entrypoint.sh` &mdash; Installs packages into `/opt/vendor` and `/opt/wp-content`
- `mu-plugins/`
  - `000-env-config.php` &mdash; Loads vendor autoload, maps S3/SMTP/env → WP constants
  - `001-hardening.php` &mdash; Disallow file mods/auto updates in prod
  - `002-canonical-home.php` &mdash; Ensures WP_HOME/WP_SITEURL point to https://$PRIMARY_DOMAIN.
Redirects any mismatched host/scheme to the canonical one.
  - `003-disable-users.php` &mdash; Simple account disable via user meta
- `php/`
  - `custom.ini` &mdash; PHP runtime settings
- `app.Dockerfile` &mdash; Immutable WordPress runtime (Apache)
- `docker-compose.yml` &mdash; Production-ish stack (stateless web + vendor builder)
- `docker-compose.override.yml` &mdash; Dev overrides (writable wp-content bind mount)
- `healthz.php` &mdash; Liveness probe (no DB)
- `readyz.php` &mdash; Readiness probe (checks DB, optional Redis)
- `.env.prod` &mdash; `COMPOSER_REQUIRE` baseline, e.g. plugins + theme pin
- `.htaccess` &mdash; Permalink rules baked in (immutable)

<!-- ```bash
.github/workflows/
  ↪ build-images.yml  # Build, scan (Trivy), and push app + vendor-builder images
  ↪ theme-release.yml  # Build theme, tag, bump COMPOSER_REQUIRE, trigger Coolify

builder/
  ↪ Dockerfile  # Composer-based builder image
  ↪ entrypoint.sh  # Installs packages into /opt/vendor and /opt/wp-content

mu-plugins/
  ↪ 000-env-config.php  # Loads vendor autoload, maps S3/SMTP/env → WP constants
  ↪ 001-hardening.php  # Disallow file mods/auto updates in prod
  ↪ 002-disable-users.php  # Simple account disable via user meta

php/
  ↪ custom.ini  # PHP runtime settings

app.Dockerfile  # Immutable WordPress runtime (Apache)
docker-compose.yml  # Production-ish stack (stateless web + vendor builder)
docker-compose.override.yml  # Dev overrides (writable wp-content bind mount)
healthz.php  # Liveness probe (no DB)
readyz.php  # Readiness probe (checks DB, optional Redis)
.env.prod  # COMPOSER_REQUIRE baseline, e.g. plugins + theme pin
.htaccess  # Permalink rules baked in (immutable)
``` -->

## How it works

### 1) Build content at deploy time (default)
- Set `COMPOSER_REQUIRE` (space-separated list of Composer packages + versions).
- The `vendor` service runs first, writing:
  - Composer autoload to `/opt/vendor/vendor`
  - Plugins/themes/mu-plugins into `/opt/wp-content/*` *(via `composer/installers`)*
- The `wordpress` service then mounts those volumes **read-only**.

### 2) Immutable runtime
- The runtime does **not** contain the `composer` binary. Instead, `mu-plugins/000-env-config.php` loads the vendor autoloader from the read-only volume at `/opt/vendor/vendor/autoload.php`. This satisfies packages like `humanmade/s3-uploads` that require Composer’s autoloader.
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

## Production deployment (e.g. Coolify + Cloudflare LB)

- Terminate TLS at Cloudflare; origin can be “Full (strict)”.
- Cache policy: enable CDN caching for static `wp-content/*` and `wp-includes/*`. Honor origin headers (we send long-lived `Cache-Control` + `immutable` for assets).
- Add CF rules: rate-limit `/wp-login.php`, block `xmlrpc.php` (we also deny it at Apache for direct hits).

1. Configure your Coolify app to use this repo and pass environment values:
    - **DB:** `WORDPRESS_DB_HOST`, `WORDPRESS_DB_USER`, `WORDPRESS_DB_PASSWORD`, `WORDPRESS_DB_NAME`
    - **S3:** `S3_UPLOADS_*`
    - **SMTP (optional):** `WP_SMTP_FORCE`, `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, `SMTP_SECURE`
    - **Health token:** `HEALTHZ_TOKEN` (and have CF LB check `/healthz.php?t=$TOKEN` or `/readyz.php?t=$TOKEN`)
    - Any extra **WP `defines()`** via `WORDPRESS_CONFIG_EXTRA`
2. Ensure **uploads go to S3** (`humanmade/s3-uploads`) to keep the web tier stateless.
    - Put **Cloudflare Load Balancer** in front of multiple Coolify-managed instances:
    - Health check path: `/healthz.php?t=$TOKEN`, or `/readyz.php?t=$TOKEN`
    - Rate-limit `wp-login.php` and block/limit `xmlrpc.php`
    - Cache static assets (theme CSS/JS, uploads, `wp-includes`)

<!-- ## Theme release workflow (no app image rebuild)

- The **Theme release & Coolify** redeploy workflow:
    1. Builds your theme (Node/Vite/Webpack)
    2. Creates a git tag (provided or timestamp)
    3. Updates `.env.prod` to pin `COMPOSER_REQUIRE` to the new theme tag
    4. Commits/pushes the env bump
    5. Calls your **Coolify Deploy Hook** to redeploy

At deploy time, the `vendor` service installs that theme version into `wp_content` volume; the app mounts it read-only. -->

## Building & publishing images (optional)

- The **Build, Scan with Trivy, and Push** workflow:
    - Builds `app` and `vendor-builder` images
    - Scans them with [**Trivy**](https://github.com/aquasecurity/trivy) (fails on High/Critical)
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

**Core:**
- `WORDPRESS_DB_HOST`, `WORDPRESS_DB_USER`, `WORDPRESS_DB_PASSWORD`, `WORDPRESS_DB_NAME`

**Composer content:**
- `COMPOSER_REQUIRE` — space-separated package list (e.g., `yourorg/awesome-theme:1.2.3` `wpackagist-plugin/wp-mail-smtp:^4`)
- `COMPOSER_JSON_EXTRAS` — JSON fragment to add repos/config (private VCS, allow-plugins, auth mechanisms)

**S3 Uploads:**
- `S3_UPLOADS_BUCKET`, `S3_UPLOADS_REGION`, `S3_UPLOADS_KEY`, `S3_UPLOADS_SECRET`, - `S3_UPLOADS_ENDPOINT`, `S3_UPLOADS_USE_PATH_STYLE_ENDPOINT` — set `"true"` for MinIO/Backblaze.

**SMTP (optional):**
- `WP_SMTP_FORCE=true`, `MAIL_FROM`, `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, `SMTP_SECURE`

**Health:**
- `HEALTHZ_TOKEN` — optional token for `/healthz.php` and `/readyz.php`

**WP extras (advanced):**
- `ALLOW_CONFIG_EXTRA` — set `true` in dev (via override) to allow `WORDPRESS_CONFIG_EXTRA` to be evaluated. Leave `false` in prod.
- `WORDPRESS_CONFIG_EXTRA` — final PHP appended via MU-plugin (use sparingly; prefer explicit env → constants)

## Health endpoints
- `GET /healthz.php?t=$HEALTHZ_TOKEN` → **200 OK** if PHP is serving (no DB).
- `GET /readyz.php?t=$HEALTHZ_TOKEN` → **200 OK** only if DB (and optional Redis) is reachable; returns 500 otherwise.

For Cloudflare Load Balancer, prefer `/readyz.php?t=$HEALTHZ_TOKEN` so origins are marked unhealthy (503) if DB is down. Use `/healthz.php` (no DB) for container liveness only.

## Cron
A separate `cron` service runs `wp cron event run --due-now` every ~60s with small jitter to avoid thundering-herd when you scale replicas.

See [`docker-compose.yml`](docker-compose.yml#L136-L170); _lines 136-170_

<!-- ```yaml
services:
  cron:
    image: ghcr.io/kaffolder7/wordpress-immutable:latest
    depends_on:
      mariadb:
        condition: service_healthy
    environment:
      # same DB and WP env as wordpress
    command: bash -lc 'while true; do wp cron event run --due-now --path=/var/www/html --allow-root; sleep 60; done'
``` -->

Or, add a tiny external scheduler that runs:
```bash
wp cron event run --due-now --path=/var/www/html --allow-root
```
...with the same env as `wordpress`, so web pods stay boring/fast.

## Operations / Runbooks

- Rotate `HEALTHZ_TOKEN` anytime; LB health URLs must include the new token.
- WP salts: set `AUTH_KEY`, `SECURE_AUTH_KEY`, etc. in env; the MU-plugin consumes them at boot.
- Disable a user fast: `wp user meta update <ID> account_disabled 1 && wp user session destroy <ID>`

Note: **Cloudflare IP trust list stays fresh** — A scheduled workflow regenerates `apache/remoteip-cloudflare.conf` weekly and opens a PR. Labels embed the “Generated:” timestamp into the app image so you can audit freshness.

## Security hardening

- Read-only root FS + **tmpfs** for writable dirs.
- **DISALLOW_FILE_MODS/EDIT** in prod; manage code via Composer.
- Apache hardening: `ServerTokens Prod`, `ServerSignature Off`, `-Indexes`, baked `.htaccess`.
- Trivy vulnerability scans on images in CI before push.
- Rate-limit auth endpoints at Cloudflare; disable XML-RPC.
- **Canonical HTTPS host** — `mu-plugins/002-canonical-home.php` forces `WP_HOME`/`WP_SITEURL` to `https://$PRIMARY_DOMAIN` and 301-redirects mismatched host/scheme. It skips CLI/cron. Ensure `apache/https-forwarded.conf` is enabled so WordPress sees HTTPS when you’re behind Cloudflare.

## Supply chain

Images are signed keylessly via Sigstore (cosign) in CI. Verify locally:

```bash
COSIGN_EXPERIMENTAL=1 cosign verify ghcr.io/kaffolder7/wordpress-immutable:latest \
  | jq -r '.payload|@base64d' | jq .
```

## Troubleshooting

- **Health check failing?** Ensure `HEALTHZ_TOKEN` is set in env and used in the healthcheck URL.
- **Theme not updating in prod?** Confirm `.env.prod` has the new tag in `COMPOSER_REQUIRE` and that the vendor job logs show the pin.
- **Uploads missing?** Verify S3 credentials/endpoint and that the `S3_UPLOADS_*` constants are defined at runtime.
- **Canonical redirect loops?** If you see redirect loops after a domain change, ensure `PRIMARY_DOMAIN` matches the new host and that `apache/https-forwarded.conf` is active so `is_ssl()` reflects the edge protocol.

## License

This stack composes multiple upstream projects (WordPress, Composer, etc.). Review and comply with their licenses and any commercial plugin/theme terms.