# General webserver

nginx:
  pkg.installed: []
  service.running:
    # Make sure configuration is in place first, and restart if any of it changes
    - watch:
      - file: nginx.config.site
      - file: nginx.config.confd
      - file: nginx.config.includes
      - file: nginx.config.enable
      - file: nginx.config.disable-others
      - file: nginx.config.dhparams
      - cmd: nginx.config.dhparams
      # ---
      # These will be satisfied whenever SSL certificates are set up, too
      - file: nginx.config.dummy_certs.cert
      - file: nginx.config.dummy_certs.fullcert
      - file: nginx.config.dummy_certs.privkey
      - file: nginx.config.dummy_certs.marker
      # ---

# Set up basic configuration
nginx.config.site:
  file.managed:
    - name: /etc/nginx/sites-available/{{ salt['pillar.get']('system:hostname', 'dev') }}
    - source: salt://files/nginx/sites/main_site
    - template: jinja
    - makedirs: True
nginx.config.confd:
  file.recurse:
    - name: /etc/nginx/conf.d
    - source: salt://files/nginx/conf.d
    - makedirs: True
    - clean: True
nginx.config.includes:
  file.recurse:
    - name: /etc/nginx/includes
    - source: salt://files/nginx/includes
    - makedirs: True
    - clean: True
nginx.config.enable:
  file.symlink:
    - name: /etc/nginx/sites-enabled/{{ salt['pillar.get']('system:hostname', 'dev') }}
    - target: /etc/nginx/sites-available/{{ salt['pillar.get']('system:hostname', 'dev') }}
    - makedirs: True
nginx.config.disable-others:
  file.directory:
    - name: /etc/nginx/sites-enabled/
    # Disable other sites, don't remove anything matching current hostname
    - clean: True
    - exclude_pat: '*{{ salt['pillar.get']('system:hostname', 'dev') }}*'

# Ensure SSL dhparams exists, clean up others
nginx.config.dhparams:
  file.directory:
    - name: /etc/nginx/dhparam
    # Don't allow global access to the DH params
    - user: root
    - group: www-data
    - mode: 750
    # Clean up from other sites, don't remove anything matching current hostname
    - clean: True
    - exclude_pat: '*{{ salt['pillar.get']('system:hostname', 'dev') }}*'
  cmd.run:
    - name: openssl dhparam -out /etc/nginx/dhparam/{{ salt['pillar.get']('system:hostname', 'dev') }}.pem 2048
    - creates: /etc/nginx/dhparam/{{ salt['pillar.get']('system:hostname', 'dev') }}.pem

# ---
# Ensure there's some form of SSL certificate in place
# This will get replaced when certbot is set up
# Disable replacing existing files, don't overwrite a potentially-valid cert
#
# Only if dummy certs are added, store an indication that these are the dummy certificates.
nginx.config.dummy_certs.marker:
  file.managed:
    - name: /etc/letsencrypt/live/{{ salt['pillar.get']('system:hostname', 'dev') }}/is_dummy_certs
    - replace: False
    - makedirs: True
    # Only add if changes are made
    - onchanges:
      - file: nginx.config.dummy_certs.cert
      - file: nginx.config.dummy_certs.fullcert
      - file: nginx.config.dummy_certs.privkey
nginx.config.dummy_certs.cert:
  file.managed:
    - name: /etc/letsencrypt/live/{{ salt['pillar.get']('system:hostname', 'dev') }}/chain.pem
    - source: salt://files/certbot/dummy_certs/cert.pem
    - replace: False
    - makedirs: True
nginx.config.dummy_certs.fullcert:
  file.managed:
    - name: /etc/letsencrypt/live/{{ salt['pillar.get']('system:hostname', 'dev') }}/fullchain.pem
    - source: salt://files/certbot/dummy_certs/cert.pem
    - replace: False
    - makedirs: True
nginx.config.dummy_certs.privkey:
  file.managed:
    - name: /etc/letsencrypt/live/{{ salt['pillar.get']('system:hostname', 'dev') }}/privkey.pem
    - source: salt://files/certbot/dummy_certs/privkey.pem
    - replace: False
    - makedirs: True

# Don't try to clean these up!  Let's Encrypt may put other files in these
# folders and automatically removing private keys is asking for trouble.
# ---

# Prepare the base setup
www-data.base:
  file.directory:
    - name: /var/www/
    # Clean up from other sites, don't remove anything matching current hostname or _common
    - clean: True
    # Use a regular expression
    - exclude_pat: 'E@(\/var\/www\/(_common|{{ salt['pillar.get']('system:hostname', 'dev') }})\/)*'

# Set up common files
www-data.common:
  file.recurse:
    - name: /var/www/_common
    - source: salt://files/www/_common
    - clean: True

# Set up main site
www-data.main.base:
  file.directory:
    - name: /var/www/html_{{ salt['pillar.get']('system:hostname', 'dev') }}/
www-data.main.index:
  file.managed:
    - name: /var/www/html_{{ salt['pillar.get']('system:hostname', 'dev') }}/index.html
    - source: salt://files/www/html_main_site/index.html
    - template: jinja
www-data.main.error:
  file.recurse:
    - name: /var/www/html_{{ salt['pillar.get']('system:hostname', 'dev') }}/errors
    - source: salt://files/www/html_main_site/errors
    - template: jinja
    - makedirs: True
    - clean: True
www-data.main.manifest:
  file.managed:
    - name: /var/www/html_{{ salt['pillar.get']('system:hostname', 'dev') }}/manifest.json
    - source: salt://files/www/html_main_site/manifest.json
    - template: jinja
www-data.main.robots:
  file.managed:
    - name: /var/www/html_{{ salt['pillar.get']('system:hostname', 'dev') }}/robots.txt
    - source: salt://files/www/html_main_site/robots.txt
www-data.main.style:
  file.symlink:
    - name: /var/www/html_{{ salt['pillar.get']('system:hostname', 'dev') }}/style/theme
    - target: /var/www/_common/style/orange
    - makedirs: True

# PHP
web-php:
  pkg.installed:
    - pkgs:
      - php7.0-fpm
      - php7.0-pgsql
    - require_in:
      - service: nginx
      # Don't run the web-server until PHP is installed

# www-data maintenance user
# Avoid running Git as root
www-data-manager:
  user.present:
    - name: www-manage
    - fullname: 'Web management user'
    - system: True
    - createhome: False
