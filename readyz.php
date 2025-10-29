<?php
/**
 * Readiness healthcheck (checks DB; optional Redis)
 * 
 * Use this when you want Cloudflare to pull a node from rotation if DB isn’t reachable (and optionally Redis, if you enable it).
 */
header('Content-Type: text/plain');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

$token = getenv('HEALTHZ_TOKEN');
if ($token && ($_GET['t'] ?? '') !== $token) { http_response_code(404); exit("Not Found\n"); }

$errors = [];

// DB check (uses your container env — fast, no WP bootstrap)
$dbHost = getenv('WORDPRESS_DB_HOST') ?: 'mariadb';
$dbUser = getenv('WORDPRESS_DB_USER') ?: getenv('SERVICE_USER_WORDPRESS');
$dbPass = getenv('WORDPRESS_DB_PASSWORD') ?: getenv('SERVICE_PASSWORD_WORDPRESS');
$dbName = getenv('WORDPRESS_DB_NAME') ?: 'wordpress';

mysqli_report(MYSQLI_REPORT_OFF);
$mysqli = mysqli_init();
$mysqli->options(MYSQLI_OPT_CONNECT_TIMEOUT, 2);
if (!$mysqli->real_connect($dbHost, $dbUser, $dbPass, $dbName)) {
    $errors[] = 'db';
} else {
    $ping = @$mysqli->query('SELECT 1');
    if (!$ping) $errors[] = 'db';
    $mysqli->close();
}

// Optional: Redis check (set HEALTHZ_CHECK_REDIS=1 to enforce)
if (getenv('HEALTHZ_CHECK_REDIS') === '1') {
    $redisHost = getenv('WP_REDIS_HOST') ?: 'redis';
    $redisPort = intval(getenv('WP_REDIS_PORT') ?: 6379);
    $errno = 0; $errstr = '';
    $sock = @fsockopen($redisHost, $redisPort, $errno, $errstr, 0.5);
    if ($sock) { fwrite($sock, "*1\r\n$4\r\nPING\r\n"); fclose($sock); } else { $errors[] = 'redis'; }
}

// Optional: avoid marking healthy during maintenance/update
if (file_exists(__DIR__ . '/.maintenance')) {
    $errors[] = 'maintenance';
}

if ($errors) {
    http_response_code(500);
    echo "NOT OK: " . implode(',', $errors) . "\n";
} else {
    http_response_code(200);
    echo "OK\n";
}