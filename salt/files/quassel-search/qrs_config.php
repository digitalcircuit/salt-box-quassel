<?php
define('db_host', 'localhost');
define('db_port', 5432);
define('db_name', '{{ salt['pillar.get']('quassel:database:name', 'quassel') }}');
define('db_user', '{{ salt['pillar.get']('quassel:database:username', 'quassel') }}');
define('db_pass', '{{ salt['pillar.get']('quassel:database:password') }}');
define('backend', 'pgsql-smart');
define('path_prefix', '/search');
