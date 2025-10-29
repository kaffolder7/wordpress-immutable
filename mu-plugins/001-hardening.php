<?php
// Production-safe defaults
if (!defined('AUTOMATIC_UPDATER_DISABLED')) define('AUTOMATIC_UPDATER_DISABLED', true);
if (!defined('WP_AUTO_UPDATE_CORE')) define('WP_AUTO_UPDATE_CORE', false);
if (!defined('DISALLOW_FILE_MODS')) define('DISALLOW_FILE_MODS', true);  // no plugin/theme edits in Prod