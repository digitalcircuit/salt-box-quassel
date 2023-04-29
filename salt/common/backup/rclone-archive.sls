# rclone

# rclone is served as specific files, with version information available at
# https://downloads.rclone.org/version.txt
#
# Specific packages can be found at...
# https://downloads.rclone.org/

{% if salt['pillar.get']('common:backup:system:enable', False) == True %}
include:
  # For backup module
  - common.backup.system

# Don't install rclone without backups being enabled

{% set rclone_archive_config = '/root/salt/backup/rclone-archive/config' %}
# Used in pillar/common/backup/system.sls, too!

# Try to use the repository version if possible
{% set rclone_minver = '1.53.3' %}
{% set rclone_distver = salt['pkg.list_repo_pkgs']('rclone')['rclone'] |first() %}
{% set rclone_distver_new_enough = (salt['pkg.version_cmp'](rclone_distver, rclone_minver) >= 0) %}

# Install rclone
common.backup.rclone.pkg:
  pkg.installed:
{% if rclone_distver_new_enough == False %}
    - sources:
      - rclone: {{ salt['pillar.get']('common:backup:rclone-archive:versions:deb', 'https://downloads.rclone.org/rclone-current-linux-amd64.deb') }}
{% else %}
    - pkgs:
      - rclone
{% endif %}
    # Ensure rclone is available before configuring
    - require_in:
      - file: common.backup.system.scheduler
    - watch_in:
      - cmd: common.backup.system.configure

# Set up rclone configuration
common.backup.rclone-archive.config:
  file.managed:
    - name: {{ rclone_archive_config }}
    - source: salt://files/common/backup/rclone-archive/rclone-config
    - template: jinja
    - makedirs: True
{% if salt['pillar.get']('common:backup:system:enable', False) == True %}
    - require_in:
      - file: common.backup.system.scheduler
    - watch_in:
      - cmd: common.backup.system.configure
{% endif %}

# End backup portion
{% endif %}
