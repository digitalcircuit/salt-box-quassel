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

# Attempt to determine if TLS 1.3 is supported by comparing OpenSSL and nginx
# versions.
#
# See https://github.com/mozilla/ssl-config-generator/blob/293fbf574f3c062eb227ab6e69074d534e97108d/src/js/configs.js#L77-L87
# Minimum versions
# > Minimum nginx version
{% set minver_tls13_nginx = '1.13.0' %}
# > Minimum openssl versions
{% set minver_tls13_openssl = '1.1.1' %}
# Actual versions
# > nginx
{% set localver_nginx = salt['pkg.list_repo_pkgs']('nginx')['nginx'] |first() %}
# > openssl
{% set localver_openssl = salt['pkg.list_repo_pkgs']('openssl')['openssl'] |first() %}
#
# Compare versions
{% set tls13_available = False %}
{% if salt['pkg.version_cmp'](localver_nginx, minver_tls13_nginx) >= 0 %}
  {% if salt['pkg.version_cmp'](localver_openssl, minver_tls13_openssl) >= 0 %}
    {% set tls13_available = True %}
  {% endif %}
{% endif %}

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
    # Templating is needed for php_handler and ssl_common (TLSv1.3 detection)
    - template: jinja
    - context:
        tls13_available: {{ tls13_available }}
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
