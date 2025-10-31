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

/** DB check with short, explicit timeouts **/
$dbHost = getenv('WORDPRESS_DB_HOST') ?: 'mariadb';
$dbUser = getenv('WORDPRESS_DB_USER') ?: getenv('SERVICE_USER_WORDPRESS');
$dbPass = getenv('WORDPRESS_DB_PASSWORD') ?: getenv('SERVICE_PASSWORD_WORDPRESS');
$dbName = getenv('WORDPRESS_DB_NAME') ?: 'wordpress';

mysqli_report(MYSQLI_REPORT_OFF);
$mysqli = mysqli_init();
// 1) connect timeout (seconds)
$mysqli->options(MYSQLI_OPT_CONNECT_TIMEOUT, 2);

// 2) add read timeout (requires mysqlnd)
if (defined('MYSQLI_OPT_READ_TIMEOUT')) {
    $mysqli->options(MYSQLI_OPT_READ_TIMEOUT, 2);
}
// 3) add write timeout if available (PHP 8.1+, mysqlnd)
if (defined('MYSQLI_OPT_WRITE_TIMEOUT')) {
    $mysqli->options(MYSQLI_OPT_WRITE_TIMEOUT, 2);
}

if (!$mysqli->real_connect($dbHost, $dbUser, $dbPass, $dbName)) {
    $errors[] = 'db';
} else {
    // Optional: cap SELECT time (MySQL 5.7+; ms). Only affects SELECT.
    // If unsupported, MySQL just ignores it.
    @$mysqli->query('SET SESSION MAX_EXECUTION_TIME=1000');

    $ping = @$mysqli->query('SELECT 1');
    if (!$ping) $errors[] = 'db';
    @$mysqli->close();
}

// Optional: Redis check (set HEALTHZ_CHECK_REDIS=1 to enforce)
if (getenv('HEALTHZ_CHECK_REDIS') === '1') {
    $redisHost = getenv('WP_REDIS_HOST') ?: 'redis';
    $redisPort = intval(getenv('WP_REDIS_PORT') ?: 6379);
    $errno = 0; $errstr = '';
    $sock = @fsockopen($redisHost, $redisPort, $errno, $errstr, 0.5);
    if ($sock) {
        stream_set_timeout($sock, 1);
        fwrite($sock, "*1\r\n$4\r\nPING\r\n");
        $resp = fgets($sock);
        fclose($sock);
        if (stripos($resp ?? '', 'PONG') === false) { $errors[] = 'redis'; }
    } else { $errors[] = 'redis'; }
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