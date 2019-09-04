# rclone configuation

common:
  backup:
    rclone-archive:
      versions:
        # rclone package source
        deb: https://downloads.rclone.org/rclone-current-linux-amd64.deb
      backends:
        archive:
          # Used in common/backup/system.sls
          type: webdav
          url: https://offsite-backup.example.invalid/remote.php/webdav/
          vendor: nextcloud
          user: offsite-user-system1
          pass: 'obscured_password_here'
          # Run the following to transform a normal password into the obscured
          # version...
          # rclone obscure <password>
          #
          # See https://rclone.org/commands/rclone_obscure/
          # And https://github.com/rclone/rclone/issues/2265
          # "Add --no-obscure flag so we don't try to reveal passwords"
