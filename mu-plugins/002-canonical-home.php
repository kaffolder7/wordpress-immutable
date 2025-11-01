<?php
/**
 * Plugin Name: Canonical Home/SiteURL and HTTPS
 * Description: Forces WP_HOME/WP_SITEURL and canonical host/https, with guards for CLI/cron.
 */

if (defined('WP_CLI') && WP_CLI) { return; }          // don’t interfere with wp-cli
if (php_sapi_name() === 'cli') { return; }            // extra guard
if (defined('DOING_CRON') && DOING_CRON) { return; }  // don’t 301 during cron

// Prefer PRIMARY_DOMAIN from env; fallback to current host
$primary = getenv('PRIMARY_DOMAIN');
if (!$primary) {
    $primary = $_SERVER['HTTP_HOST'] ?? $_SERVER['SERVER_NAME'] ?? null;
    if (!$primary) { return; }
}

// Compute canonical base (https) — we expect HTTPS at the edge
$scheme = 'https';
$base   = $scheme . '://' . $primary;

// Define WP_HOME/SITEURL early if not already set by wp-config.php
if (!defined('WP_HOME'))    { define('WP_HOME',    $base); }
if (!defined('WP_SITEURL')) { define('WP_SITEURL', $base); }

// If the incoming host/scheme don’t match, redirect canonical
$currentHost   = $_SERVER['HTTP_HOST'] ?? '';
$currentScheme = (!empty($_SERVER['HTTPS']) && strtolower($_SERVER['HTTPS']) !== 'off') ? 'https' : 'http';

// Some proxies set X-Forwarded-Proto: https. Honor it.
if ($currentScheme !== 'https' && !empty($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
    $currentScheme = 'https';
}

$wantHost   = parse_url(WP_HOME, PHP_URL_HOST);
$wantScheme = parse_url(WP_HOME, PHP_URL_SCHEME) ?: 'https';

if ($wantHost && ($currentHost !== $wantHost || $currentScheme !== $wantScheme)) {
    // Preserve path/query
    $path = $_SERVER['REQUEST_URI'] ?? '/';
    $target = $wantScheme . '://' . $wantHost . $path;

    // Avoid loops on admin-ajax and REST if you have alt hosts — usually fine to redirect anyway
    if (php_sapi_name() !== 'cli') {
        header('Cache-Control: no-store', true);
        header('Location: ' . $target, true, 301);
        exit;
    }
}
