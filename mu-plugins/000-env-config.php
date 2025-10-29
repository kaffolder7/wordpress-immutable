<?php
/**
 * Autoload Composer vendor from a mounted volume (read-only).
 * This keeps the app image immutable while allowing dynamic packages.
 */
$vendorPath = '/opt/vendor/vendor/autoload.php';
if (file_exists($vendorPath)) {
    require_once $vendorPath;
}

/**
 * Env-driven config injection.
 * Anything you pass in WORDPRESS_CONFIG_EXTRA (multiline) is appended here.
 * We also honor specific env vars for common services.
 */
if (!defined('DISALLOW_FILE_EDIT')) define('DISALLOW_FILE_EDIT', true);  // hardening

// S3 Uploads (humanmade/s3-uploads)
$envMap = [
    'S3_UPLOADS_BUCKET' => 'S3_UPLOADS_BUCKET',
    'S3_UPLOADS_REGION' => 'S3_UPLOADS_REGION',
    'S3_UPLOADS_KEY'    => 'S3_UPLOADS_KEY',
    'S3_UPLOADS_SECRET' => 'S3_UPLOADS_SECRET',
    'S3_UPLOADS_ENDPOINT' => 'S3_UPLOADS_ENDPOINT',
    'S3_UPLOADS_USE_PATH_STYLE_ENDPOINT' => 'S3_UPLOADS_USE_PATH_STYLE_ENDPOINT',
];

foreach ($envMap as $const => $env) {
    $val = getenv($env);
    if ($val !== false && !defined($const)) {
        define($const, $val);
    }
}
// foreach ([
//     'S3_UPLOADS_BUCKET','S3_UPLOADS_REGION','S3_UPLOADS_KEY','S3_UPLOADS_SECRET',
//     'S3_UPLOADS_ENDPOINT','S3_UPLOADS_USE_PATH_STYLE_ENDPOINT'
// ] as $k) { $v = getenv($k); if ($v !== false && !defined($k)) define($k, $v); }

// Optional SMTP wiring (WP Mail SMTP or similar)
if (getenv('WP_SMTP_FORCE') === 'true') {
    define('WPMS_ON', true);
    define('WPMS_MAILER', 'smtp');
    if (($from = getenv('MAIL_FROM'))) define('WPMS_MAIL_FROM', $from);
    if (($host = getenv('SMTP_HOST'))) define('WPMS_SMTP_HOST', $host);
    if (($port = getenv('SMTP_PORT'))) define('WPMS_SMTP_PORT', (int)$port);
    if (($user = getenv('SMTP_USER'))) define('WPMS_SMTP_USER', $user);
    if (($pass = getenv('SMTP_PASSWORD'))) define('WPMS_SMTP_PASS', $pass);
    if (($secure = getenv('SMTP_SECURE'))) define('WPMS_SMTP_ENCRYPTION', strtolower($secure));  // tls/ssl/none
}
// if (getenv('WP_SMTP_FORCE') === 'true') {
//     define('WPMS_ON', true); define('WPMS_MAILER', 'smtp');
//     foreach (['MAIL_FROM'=>'WPMS_MAIL_FROM','SMTP_HOST'=>'WPMS_SMTP_HOST','SMTP_PORT'=>'WPMS_SMTP_PORT',
//                 'SMTP_USER'=>'WPMS_SMTP_USER','SMTP_PASSWORD'=>'WPMS_SMTP_PASS','SMTP_SECURE'=>'WPMS_SMTP_ENCRYPTION'] as $e=>$c) {
//         $v = getenv($e); if ($v) define($c, is_numeric($v)?(int)$v:$v);
//     }
// }

// Allow raw extra PHP from env (last so it can override)
$extra = getenv('WORDPRESS_CONFIG_EXTRA');
if ($extra) {
    eval("?>".$extra);
}
/* if ($extra = getenv('WORDPRESS_CONFIG_EXTRA')) { eval("?>".$extra); } */