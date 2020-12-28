Quassel-in-a-box
===============

This takes a stock Ubuntu 16.04/18.04/20.04 system, and with Salt, turns it into an IRC setup with desktop, mobile, and web clients, search, a home page, and includes Let's Encrypt certificates for encrypted connections.

*This is not endorsed by the official [Quassel IRC project][web-quassel], [Quassel Webserver][web-quassel-web], or [Quassel Rest Search][web-quassel-rest-search]*

***Work in progress:** features may change without warning.  Please read the commit log before updating production systems.*

## Deployment

* Customize the files in ```pillar``` to suit your environment
  * See below for the minimum viable setup (e.g. local development)
* Apply the salt state via ```salt-call```
  * Works with a [masterless minion Salt setup](https://docs.saltstack.com/en/latest/topics/tutorials/quickstart.html ), no need for master

### Minimum viable setup (local development)

1. Set your server hostname

[`pillar/server/hostnames.sls`](pillar/server/hostnames.sls):
```yaml
# Hostname details (optional/default configuration removed)
server:
  # Hostnames
  hostnames:
    # Domains by certificate chain
    # Main domain
    cert-primary:
      # Hostname visible to the world, used in SSL certs and branding
      root: public.domain.here.example.com
```

2. Set up `certbot` for Let's Encrypt certificates, or disable it

[`pillar/server/web/certbot.sls`](pillar/server/web/certbot.sls):
```yaml
# Certificate details for Let's Encrypt (optional/default configuration removed)
certbot:
  # Replace dummy certificates with certificates from Let's Encrypt?
  #
  # NOTE - enabling certbot implies you agree to the Let's Encrypt
  # Terms of Service (subscriber agreement).  Please read it first.
  # https://letsencrypt.org/repository/#let-s-encrypt-subscriber-agreement
  enable: True
  # Use staging/test server to avoid rate-limit issues?
  testing: False
  # Account details
  account:
    # Email address for recovery
    email: real-email-address@example.com
```

3. Set initial credentials for Quassel core

[`pillar/server/chat/quassel/main.sls`](pillar/server/chat/quassel/main.sls):
```yaml
# Quassel configuration (optional/default configuration removed)
server:
  chat:
    quassel:
      # Quassel core
      core:
        # Initial/administrative user
        admin:
          username: initial_quassel_user
          password: change_this_password
      # PostgreSQL database setup
      database:
        password: also_change_this_database_password
```

## Usage

### Default setup

* [Quassel IRC][web-quassel] core running on port `4242`, with admin user [as in pillar data](pillar/server/chat/quassel/main.sls)
  * Stable version configured [from mamarley's PPA](https://launchpad.net/~mamarley/+archive/ubuntu/quassel)
* Website at [configured server hostname](pillar/server/hostnames.sls), with HTTP/HTTPS enabled
  * [Quassel Web][web-quassel-web] available at `https://hostname/chat`
  * [Quassel Rest Search][web-quassel-rest-search] available at `https://hostname/search`
  * Basic connection information and links to the desktop and [Android client, Quasseldroid](https://quasseldroid.info)
* Let's Encrypt for certificates with automated deployment and renewal, including reloading services
* 2 GB swapfile for low-memory systems (e.g. 1 GB RAM)
  * Initial NPM deploy of Quassel Web spikes memory usage

### Configuration

* Tune PostgreSQL performance (**recommended**)
  * Modify [`pillar/server/storage/database.sls`](pillar/server/storage/database.sls) according to your system specifications.
  * Periodic cleanup may help as well, see [the Quassel IRC project wiki for details](https://bugs.quassel-irc.org/projects/1/wiki/PostgreSQL#PostgreSQL-performance-and-maintenance )

* Add new Quassel core user
```bash
$ sudo --user=quasselcore quasselcore --add-user --configdir=/var/lib/quassel
```

* Change password of Quassel core user `USERNAME` without access to original password
```bash
$ sudo --user=quasselcore quasselcore --change-userpass=USERNAME --configdir=/var/lib/quassel
```
*Administration UI to be added later.*

### Extra features

#### Lock down allowed networks
* Useful for a shared core provided by a network
* Not yet recommended for use by fully untrusted users
  * Work is ongoing in the Quassel IRC upstream project to provide restricted accounts

[`pillar/server/chat/quassel/main.sls`](pillar/server/chat/quassel/main.sls):
```yaml
# Quassel configuration
server:
  chat:
    quassel:
      # [...existing configuration here...]
      # Restrictions and lockdown
      lockdown:
        # Lock the IRC ident to the Quassel account username
        strict-ident: False
        # Limit what networks can be used from any Quassel account
        strict-networks:
          # If enabled, only networks listed below are allowed
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
```

#### Manage software versions
* Modify [`pillar/server/chat/quassel/versions.sls`](pillar/server/chat/quassel/versions.sls)
  * Recommendation: set a fixed tag/commit ID for production, test newer versions locally first

#### Customize branding, name, help messages, etc on website
* Modify [`pillar/server/chat/quassel/branding.sls`](pillar/server/chat/quassel/branding.sls)

#### Report system status via Telegraf to a remote metrics server
* Configure [`pillar/server/metrics.sls`](pillar/server/metrics.sls) with metrics server details
* Example receiving setup: Grafana + Telegraf HTTP Listener + InfluxDB

#### Set up daily automatic, PGP-encrypted backups
* Configure [`pillar/common/backup/system.sls`](pillar/common/backup/system.sls) with upload script and encryption settings
  * Example script given for use with [rclone](https://rclone.org/), enabling backup to many cloud/self-hosted services

## Credits

* [Quassel IRC][web-quassel] for the IRC client and server core
* [Quassel Webserver][web-quassel-web] for web chat
* [Quassel Rest Search][web-quassel-rest-search] for web search
* *Some credits in the individual files, too*
* *If you're missing, let me know, and I'll fix it as soon as I can!*

[web-quassel]: https://github.com/quassel/quassel
[web-quassel-rest-search]: https://github.com/justjanne/quassel-rest-search/
[web-quassel-web]: https://github.com/magne4000/quassel-webserver
