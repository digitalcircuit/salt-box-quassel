<?php
// Here you should put the hostname of your postgres database
define('qrs_db_host', 'localhost');
// This is the port of your postgres database, usually it should stay at 5432
define('qrs_db_port', 5432);
// The username of the database in the postgres database
define('qrs_db_name', '{{ salt['pillar.get']('server:chat:quassel:database:name', 'quassel') }}');

// Only change this if you know what you are doing
define('qrs_db_connector', null);

// Username and password QRS should use to connect to your database
// (not your quassel user/pass)
define('qrs_db_user', '{{ salt['pillar.get']('server:chat:quassel:database:username', 'quassel') }}');
define('qrs_db_pass', '{{ salt['pillar.get']('server:chat:quassel:database:password') }}');

// Configure the primary language of your database here. Supported are:
// - simple (works for every language, but worse than configuring the correct language)
// - arabic
// - danish
// - dutch
// - english
// - finnish
// - french
// - german
// - hungarian
// - indonesian
// - irish
// - italian
// - lithuanian
// - nepali
// - norwegian
// - portuguese
// - romanian
// - russian
// - spanish
// - swedish
// - tamil
// - turkish
{%- set psql_with_websearch = '11' -%}
{%- set localver_psql = salt['pkg.list_repo_pkgs']('postgresql')['postgresql'] |first() -%}
{% if salt['pkg.version_cmp'](localver_psql, psql_with_websearch) >= 0 %}
// Modern websearch query support
define('qrs_db_option_tsqueryfunction', "websearch_to_tsquery('english', :query)");
{% else %}
// Legacy plain text search
define('qrs_db_option_tsqueryfunction', "plainto_tsquery('english', :query)");
{% endif -%}

// Timeout in milliseconds
define('qrs_db_option_timeout', 5000);

define('qrs_backend', 'pgsql-smart');
define('qrs_enable_ranking', false);

// If you install QRS in a subfolder, put the path to the subfolder, without trailing /, here.
define('qrs_path_prefix', '/search');
