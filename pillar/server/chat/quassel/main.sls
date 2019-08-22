# Quassel configuration
server:
  chat:
    quassel:
      # Quassel core
      core:
        # Listening port for client connections
        port: 4242
        # Initial/administrative user
        admin:
          username: initial_quassel_user
          password: change_this_password
        # System username quasselcore uses
        # This is NOT the Quassel login username
        username: quasselcore
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
      # Restrictions and lockdown
      lockdown:
        # Lock the IRC ident to the Quassel account username
        strict-ident: False
        # Limit what networks can be used from any Quassel account
        strict-networks:
          # If enabled, only whitelisted networks below are allowed
          enabled: False
          # Whitelist of IRC networks (domain names and/or IP addresses)
          #
          # NOTE - Domain names are translated to IP addresses, refreshed
          # periodically.  If you make use of round-robin DNS, you will need to
          # specify all possible domain names/IP addresses.
          hosts:
            - "irc.example.invalid"
            - "server-a.example.invalid"
            - "server-b.example.invalid"
          # Whitelist of allowed ports for IRC connections
          ports:
            - 6667
            - 6697
