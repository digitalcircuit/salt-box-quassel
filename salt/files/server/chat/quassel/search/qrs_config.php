<?php
define('qrs_db_host', 'localhost');
define('qrs_db_port', 5432);
define('qrs_db_name', '{{ salt['pillar.get']('server:chat:quassel:database:name', 'quassel') }}');

// Only change this if you know what you are doing
define('qrs_db_connector', null);

define('qrs_db_user', '{{ salt['pillar.get']('server:chat:quassel:database:username', 'quassel') }}');
define('qrs_db_pass', '{{ salt['pillar.get']('server:chat:quassel:database:password') }}');

define('qrs_db_option_tsqueryfunction', "plainto_tsquery('english', :query)");
// Timeout in milliseconds
define('qrs_db_option_timeout', 5000);

define('qrs_backend', 'pgsql-smart');
define('qrs_enable_ranking', false);

define('qrs_path_prefix', '/search');
