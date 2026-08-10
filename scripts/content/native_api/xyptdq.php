<?php
/**
 * Temporary CLI-only Xunrui API entry used by the controlled publisher smoke.
 * This file is copied into WEBROOT/api only for the duration of a server job.
 */
declare(strict_types=1);

if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}

define('IS_API', basename(__FILE__, '.php'));
define('SELF', pathinfo(__FILE__, PATHINFO_BASENAME));
require dirname(__DIR__) . '/index.php';
