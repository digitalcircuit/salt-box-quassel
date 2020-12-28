# Certbot for Let's Encrypt certificates

{% if salt['pillar.get']('certbot:enable', False) == True %}
# Require webserver to be installed first
include:
  - .webserver

# Ensure Let's Encrypt challenges directory exists
certbot.config.challenges:
  file.directory:
    - name: /var/lib/letsencrypt
    # Don't allow global access to the challenges
    - user: root
    - group: www-data
    - mode: 750

# Install Certbot itself
# It's recommended to use the upstream version, even though certbot is in the repos
#
# Ubuntu 20.04+ - the certbot PPA is deprecated, replaced by the snap version.
# Migrate to the snap version if needed.  For now, just use the distribution package.
{% set certbot_minver = '0.40.0' %}
{% set certbot_distver = salt['pkg.list_repo_pkgs']('certbot')['certbot'] |first() %}
{% set certbot_distver_new_enough = (salt['pkg.version_cmp'](certbot_distver, certbot_minver) >= 0) %}

{% if certbot_distver_new_enough == False %}
certbot.ppa:
  pkgrepo.managed:
    - ppa: certbot/certbot
  pkg.uptodate:
    # Only update if changes are made
    - onchanges:
      - pkgrepo: certbot.ppa
{% endif %}

certbot:
  pkg.installed:
    - pkgs:
      - certbot
{% if certbot_distver_new_enough == False %}
    - require:
      - pkgrepo: certbot.ppa
{% endif %}

# Set up renewal hooks
# Do before installation so any running services will be reloaded
certbot.renewal:
  file.managed:
    - name: /etc/letsencrypt/renewal-hooks/deploy/certbot-setup-reload
    - source: salt://files/server/certbot/certbot-setup-reload
    - template: jinja
    - context:
        certbot_setup_cert_dir: /root/salt/certbot/cert
    - makedirs: True
    # Mark as executable
    - mode: 755
    # Hooks directory is created during first run, but this script should be
    # ready before first run.

# Setup configuration directory
certbot.configure.setup.dir:
  file.directory:
    - name: /root/salt/certbot/cert
    - makedirs: True

{% for CERT_NAME, args in salt['pillar.get']('server:hostnames', {}).items() %}
{% set CERT_PRIMARY = args.root %}

certbot.configure.setup.cert.{{ CERT_NAME }}:
  # Manage domains.conf
  file.managed:
    - name: {{ '/root/salt/certbot/cert' | path_join(CERT_NAME, 'domains.conf') }}
    - source: salt://files/server/certbot/domains_template.conf
    - makedirs: True
    # Templating is needed for domain manipulation
    - template: jinja
    - context:
        cert_name: {{ CERT_NAME }}
        cert_primary: {{ CERT_PRIMARY }}
        cert_alternatives:
        # All certificates, excluding 'root', only the domain name (no cert name)
{% for CERT_ALT_KEY, CERT_ALT_VALUE in args.items() if not CERT_ALT_KEY == 'root' %}
          - "{{ CERT_ALT_VALUE }}"
{% endfor %}
    - watch_in:
      - cmd: certbot.configure

{% endfor %}

# Get Let's Encrypt configured and set up
# Salt doesn't seem to have a way for cmd.script's "unless" clause to be a remote script, too
certbot.configure:
  file.managed:
    - name: /root/salt/certbot/certbot-setup.sh
    - source: salt://files/server/certbot/certbot-setup.sh
    - makedirs: True
    # Mark as executable
    - mode: 755
  cmd.run:
    # Configure Certbot to acquire the certificates for the first time
    - name: /root/salt/certbot/certbot-setup.sh "/root/salt/certbot/cert" configure
#    - source: salt://files/server/certbot/certbot-setup.sh
    # Ignore if certbot already configured
    - unless: /root/salt/certbot/certbot-setup.sh "/root/salt/certbot/cert" check
    - require:
      - service: nginx
      - pkg: certbot
      - file: certbot.renewal
      - file: certbot.configure.setup.dir

# --- Migrations ---
# 2019-8-26: Main certificate changed to 'cert-primary' rather than domain name
# NOTE: This is a manual step!
# Run the following:
#
# $ sudo ls /etc/letsencrypt/archive/ # See certificates
# $ sudo certbot delete --cert-name 'public.domain.here.example.com'
#
# Don't delete the 'cert-primary' certificate

# Archived migrations on 2019-8-26 due to legacy system:hostname pillar
## certbot 0.19
## Remove old configuration hook script
#certbot.migrate.remove_old_hook_configure:
#  file.line:
#    - name: "/etc/letsencrypt/renewal/{{ salt['pillar.get']('system:hostname', 'dev') }}.conf"
#    - content: "post_hook = /bin/run-parts /etc/letsencrypt/post-hook.d/"
#    - mode: delete
#    - require:
#      - file: certbot.configure
#      - cmd: certbot.configure
#
## Remove old renewal hook directory
#certbot.migrate.remove_old_hooks:
#  file.absent:
#    - name: /etc/letsencrypt/post-hook.d

{% endif %}
