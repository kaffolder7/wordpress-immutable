<?php
/**
 * Disable specific users by a user meta flag.
 * 
 * This blocks all login methods that pass through WP auth (password, XML-RPC, basic auth to /wp-json with cookies, etc.).
 *
 * To disable user, run:
 *  `wp user meta update <ID> account_disabled 1 && wp user session destroy <ID>` via WP-CLI
 * 
 * To re-enable user:
 *  `wp user meta delete <ID> account_disabled`
 */
add_filter('authenticate', function ($user, $username) {
    if (empty($username)) return $user;

    $by = get_user_by('login', $username);
    if (!$by) return $user;

    if (get_user_meta($by->ID, 'account_disabled', true)) {
        return new WP_Error('account_disabled', __('This account has been disabled.'));
    }
    return $user;
}, 30, 2);

/** Helper: show an admin column/toggle (optional) */
add_filter('manage_users_columns', function($c){ $c['account_disabled']='Disabled'; return $c; });
add_filter('manage_users_custom_column', function($val,$col,$uid){
    if ($col==='account_disabled') return get_user_meta($uid,'account_disabled',true) ? 'Yes' : 'No';
    return $val;
},10,3);