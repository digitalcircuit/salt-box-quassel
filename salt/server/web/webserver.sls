# General webserver

nginx:
  pkg.installed:
    - pkgs:
      - nginx
  service.running:
    # Make sure configuration is in place first, and restart if any of it changes
    - name: nginx
    - watch:
      - pkg: nginx

# Set up basic configuration
nginx.config.confd.file:
  file.managed:
    - name: /etc/nginx/conf.d/common.conf
    - contents: |
        # [Common conf.d - managed by SaltStack]
        include /etc/nginx/conf.d/common/*.conf;
    - makedirs: True
    - watch_in:
      - service: nginx
nginx.config.confd.dir:
  file.recurse:
    - name: /etc/nginx/conf.d/common
    - source: salt://files/server/web/common/nginx/conf.d
    - makedirs: True
    - clean: True
    - watch_in:
      - service: nginx

nginx.config.includes:
  file.recurse:
    - name: /etc/nginx/includes/common
    - source: salt://files/server/web/common/nginx/includes
    # Templating is needed for php_handler
    - template: jinja
    - makedirs: True
    - clean: True
    - watch_in:
      - service: nginx

# Disable default site
nginx.config.disable-default:
  file.absent:
    - name: /etc/nginx/sites-enabled/default
    - watch_in:
      - service: nginx

# Set up common files
www-data.common:
  file.recurse:
    - name: /var/www/_common
    - source: salt://files/server/web/common/www/_common
    - makedirs: True
    - clean: True
    - watch_in:
      - service: nginx

# PHP
web-php:
  pkg.installed:
    - pkgs:
      # From php7
      - php-fpm
      - php-pgsql
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


# --- Migrations ---
# 2019-8-26: Main website changed to 'main' rather than domain name
nginx.config.disable-others:
  file.directory:
    - name: /etc/nginx/sites-enabled/
    # Disable other sites, don't remove anything matching current hostname
    - clean: True
    - exclude_pat: 'main'
    - watch_in:
      - service: nginx

# 2019-8-26: Configuration files moved to subdirectories
nginx.config.confd:
  file.absent:
    - name: /etc/nginx/conf.d/disable-server-version.conf
    - watch_in:
      - service: nginx
