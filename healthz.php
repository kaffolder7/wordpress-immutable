<?php
/**
 * Super-light liveness healthcheck (no DB)
 * 
 * Use this if you only need to know “the PHP container is up and serving.”
 */
header('Content-Type: text/plain');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

// Optional simple token check to avoid random hits:
// set HEALTHZ_TOKEN in your container env and call /healthz?t=TOKEN
$token = getenv('HEALTHZ_TOKEN');
if ($token && ($_GET['t'] ?? '') !== $token) {
    http_response_code(404);  // don't advertise the endpoint
    exit("Not Found\n");
}

http_response_code(200);
echo "OK\n";