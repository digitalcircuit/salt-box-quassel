# Backups of system data

# Set archive directory
{% set archive_configdir = salt['pillar.get']('common:backup:system:storage:datadir', '/root/salt/backup/system') %}
# If changing 'archive_configdir', also change 'salt-minion-only.sh'
{% set archive_moduledir = archive_configdir | path_join('scripts.d') %}
# If changing 'archive_moduledir', change every file referencing it

{% set archive_use_systemd = True %}

{% set archive_schedule_file_cron = '/etc/cron.daily/archive-run-backup' %}
{% set archive_schedule_name_systemd = 'archive-run-backup' %}

{% if salt['pillar.get']('common:backup:system:enable', False) == False %}
# Disable backups

# Remove scheduled file (cron)
common.backup.system.scheduler:
  file.absent:
    - name: {{ archive_schedule_file_cron }}

# Disable scheduled file (systemd)
common.backup.system.scheduler.cleanup.timer:
  service.dead:
    - name: {{ archive_schedule_name_systemd }}.timer
    - enable: False
common.backup.system.scheduler.cleanup.service.running:
  # Disable startup
  service.disabled:
    - name: {{ archive_schedule_name_systemd }}

{% else %}
# Enable backups

# Setup configuration directory
# > Modules
common.backup.system.configure.setup.moduledir:
  file.directory:
    - name: {{ archive_moduledir }}
    - makedirs: True
    - watch_in:
      - cmd: common.backup.system.configure
# > Configuration
common.backup.system.configure.setup.config:
  file.managed:
    - name: {{ archive_configdir }}/config-archive.sh
    - source: salt://files/common/backup/system/config-archive.sh
    - template: jinja
    - makedirs: True
    - require_in:
      - file: common.backup.system.scheduler
    - watch_in:
      - cmd: common.backup.system.configure
# > Utility with all system functionality
common.backup.system.configure.setup.utility:
  file.managed:
    - name: {{ archive_configdir }}/util-archive.sh
    - source: salt://files/common/backup/system/util-archive.sh
    - makedirs: True
    - require_in:
      - file: common.backup.system.scheduler
    - watch_in:
      - cmd: common.backup.system.configure
# > Utility with individual backup script functionality
common.backup.system.configure.setup.utility-script:
  file.managed:
    - name: {{ archive_configdir }}/util-archive-script.sh
    - source: salt://files/common/backup/system/util-archive-script.sh
    - makedirs: True
    - require_in:
      - file: common.backup.system.scheduler
    - watch_in:
      - cmd: common.backup.system.configure

# Get backup configured and set up
common.backup.system.configure:
  file.managed:
    - name: {{ archive_configdir }}/control-archive.sh
    - source: salt://files/common/backup/system/control-archive.sh
    - makedirs: True
    # Mark as executable
    - mode: 755
    - watch_in:
      - cmd: common.backup.system.configure
  cmd.run:
    # Validate settings
    - name: {{ archive_configdir }}/control-archive.sh check
    # Don't mark as changed unless output exists
    - stateful: True
    # Don't use "onchanges"/"onchanges_in", run each time, validating backup
    # settings whenever Salt state is applied.  This increases the likelihood
    # of failing settings being noticed.
    - require_in:
      - file: common.backup.system.scheduler

{% if archive_use_systemd == False %}
common.backup.system.scheduler:
  file.managed:
    - name: {{ archive_schedule_file_cron }}
    - contents: |
        # Run the automatic backup
        /bin/bash {{ archive_configdir }}/control-archive.sh backup
    # Mark as executable
    - mode: 755

{% else %}
# common.backup.system.scheduler.service.unit
common.backup.system.scheduler:
  # Unit for startup
  file.managed:
    - name: /etc/systemd/system/{{ archive_schedule_name_systemd }}.service
    - source: salt://files/common/backup/system/{{ archive_schedule_name_systemd }}.service
    - template: jinja
    - context:
        control_script: "{{ archive_configdir }}/control-archive.sh"
  cmd.run:
    - name: systemctl --system daemon-reload
    - onchanges:
      - file: common.backup.system.scheduler
common.backup.system.scheduler.service.disabled:
  # Disable startup (only run on timer)
  service.disabled:
    - name: {{ archive_schedule_name_systemd }}
    - require:
      - cmd: common.backup.system.scheduler
      - file: common.backup.system.scheduler
common.backup.system.scheduler.timer.unit:
  # Unit for periodic refresh
  file.managed:
    - name: /etc/systemd/system/{{ archive_schedule_name_systemd }}.timer
    - source: salt://files/common/backup/system/{{ archive_schedule_name_systemd }}.timer
  cmd.run:
    - name: systemctl --system daemon-reload
    - onchanges:
      - file: common.backup.system.scheduler.timer.unit
common.backup.system.scheduler.timer.running:
  # Enable periodic refresh
  service.running:
    - name: {{ archive_schedule_name_systemd }}.timer
    - enable: True
    - require:
      - cmd: common.backup.system.scheduler
      - file: common.backup.system.scheduler
      - cmd: common.backup.system.scheduler.timer.unit
    - watch:
      - file: common.backup.system.scheduler.timer.unit
{% endif %}

{% endif %}
