# Quassel configuration
quassel:
  # Quassel core
  core:
    # Listening port for client connections
    port: 4242
    # Initial/administrative user
    admin:
      username: initial_quassel_user
      password: change_this_password
  # PostgreSQL database setup
  database:
    name: quassel
    username: quassel
    password: also_change_this_database_password
  # Quassel Webserver configuration
  web:
    # User for running NodeJS
    username: quassel-web
    # Directory for local Unix listening socket
    socket_dir: /var/run/quassel-web
