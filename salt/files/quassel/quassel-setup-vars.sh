# Configuration variables for setting up Quassel
QUASSEL_PSQL_USER_NAME="{{ salt['pillar.get']('quassel:database:username', 'quassel') }}"
QUASSEL_PSQL_USER_PASSWORD="{{ salt['pillar.get']('quassel:database:password') }}"
QUASSEL_PSQL_HOSTNAME="localhost"
QUASSEL_PSQL_PORT="5432"
QUASSEL_PSQL_DB_NAME="{{ salt['pillar.get']('quassel:database:name', 'quassel') }}"
QUASSEL_ADMIN_USER_NAME="{{ salt['pillar.get']('quassel:core:admin:username') }}"
QUASSEL_ADMIN_USER_PASSWORD="{{ salt['pillar.get']('quassel:core:admin:password') }}"
