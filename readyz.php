<?php
/**
 * Readiness healthcheck (checks DB; optional Redis)
 * 
 * Use this when you want Cloudflare to pull a node from rotation if DB isn’t reachable (and optionally Redis, if you enable it).
 */
header('Content-Type: text/plain');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

// Optional token gate (set HEALTHZ_TOKEN env)
$token = getenv('HEALTHZ_TOKEN');
if ($token && ($_GET['t'] ?? '') !== $token) {
    http_response_code(403);
    exit("forbidden\n");
}

// Ultra-short timeouts
@ini_set('default_socket_timeout', '1');
@ini_set('mysql.connect_timeout', '1');
@ini_set('mysqli.reconnect', '0');

/** DB check with short, explicit timeouts **/
// $dbHost = getenv('WORDPRESS_DB_HOST') ?: 'mariadb';
// $dbUser = getenv('WORDPRESS_DB_USER') ?: getenv('SERVICE_USER_WORDPRESS');
// $dbPass = getenv('WORDPRESS_DB_PASSWORD') ?: getenv('SERVICE_PASSWORD_WORDPRESS');
// $dbName = getenv('WORDPRESS_DB_NAME') ?: 'wordpress';

// DB env
$dbHost = getenv('WORDPRESS_DB_HOST') ?: 'mariadb';
$dbUser = getenv('WORDPRESS_DB_USER') ?: 'wordpress';
$dbPass = getenv('WORDPRESS_DB_PASSWORD') ?: '';
$dbName = getenv('WORDPRESS_DB_NAME') ?: 'wordpress';

$errors = [];

// --- MySQL check (prefer TLS if supported) ---
$mysqli = mysqli_init();
if ($mysqli === false) {
    $errors[] = 'db_init';
} else {
    // keep it snappy
    $mysqli->options(MYSQLI_OPT_CONNECT_TIMEOUT, 1);
    $mysqli->options(MYSQLI_OPT_READ_TIMEOUT, 1);

    // Try to enable TLS (uses system CAs)
    if (function_exists('mysqli_ssl_set')) {
        @mysqli_ssl_set($mysqli, null, null, null, null, null);
    }

    $flags = 0;
    if (defined('MYSQLI_CLIENT_SSL')) {
        $flags |= MYSQLI_CLIENT_SSL;
    }

    if (!@$mysqli->real_connect($dbHost, $dbUser, $dbPass, $dbName, null, null, $flags)) {
        $errors[] = 'db_connect';
    } else {
        // tiny real query to ensure auth/schema ok
        @$mysqli->query('SET SESSION MAX_EXECUTION_TIME=1000');
        $q = @$mysqli->query('SELECT 1');
        if (!$q) $errors[] = 'db_query';
        @$mysqli->close();
    }
}

// --- Optional Redis check ---
$redisHost = getenv('REDIS_HOST') ?: '';
if ($redisHost) {
    try {
        $redis = new Redis();
        @$redis->connect($redisHost, (int)(getenv('REDIS_PORT') ?: 6379), 0.5);
        if (getenv('REDIS_PASSWORD')) {
            @$redis->auth(getenv('REDIS_PASSWORD'));
        }
        $pong = @$redis->ping();
        if (stripos((string)$pong, 'PONG') === false) {
            $errors[] = 'redis';
        }
        @$redis->close();
    } catch (Throwable $e) {
        $errors[] = 'redis';
    }
}

// Optional: avoid marking healthy during maintenance/update
if (file_exists(__DIR__ . '/.maintenance')) {
    $errors[] = 'maintenance';
}

if ($errors) {
    // http_response_code(500);
    // echo "NOT OK: " . implode(',', $errors) . "\n";
    http_response_code(503);
    header('Content-Type: text/plain');
    echo "unready: " . implode(',', $errors) . "\n";
    exit;
} else {
    http_response_code(200);
    echo "OK\n";
}