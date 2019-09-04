# Apply to all (since we only have one machine)
base:
  '*':
    - common.backup.rclone-archive
    - common.backup.system
    - server.chat.quassel.top
    - server.hostnames
    - server.metrics
    - server.storage.database
    - server.system
    - server.web.certbot
