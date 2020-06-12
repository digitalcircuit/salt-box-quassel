# Backups of data
common:
  backup:
    system:
      # Enable or disable backup system
      enable: False
      # Scripts to faciliate backups
      script:
        # prebackup
        # @returns 0 if successful, otherwise 1 (stops backup with error)
        #
        # Run before a backup, no parameters specified
        # Use to create filesystem snapshots, etc
        prebackup: ''
        #
        # printroot
        # @prints  Path to root
        #
        # Run before a backup, should print path to filesystem root
        # Use to backup from filesystem snapshots, etc
        # NOTE - some backup modules may ignore this, e.g. database dumps
        printroot: |
          # Default: real root
          echo "/"
        #
        # upload
        # @param  $ARCHIVE_PATH_WORKINGDIR  Path to directory of current backup
        #                                   archive, or 'check' to test for
        #                                   dependencies, don't try to upload
        # @returns 0 if successful, otherwise 1 (stops backup with error)
        #
        # Run after a backup, should upload to a remote location or move the files
        # outside of the current archive.
        #
        # WARNING - The current archive is deleted after this command is run.
        # Backups must be uploaded/moved elsewhere to be saved!
        upload: |
          # Default: do nothing
          local RCLONE_ARCHIVE_NAME="archive"
          local RCLONE_ARCHIVE_ROOT_PATH="$RCLONE_ARCHIVE_NAME:/backups/$HOSTNAME"
          local RCLONE_ARCHIVE_TEST_UNCONFIRMED_PATH="$RCLONE_ARCHIVE_ROOT_PATH/connection-test"
          local RCLONE_ARCHIVE_TEST_CONFIRMED_PATH="$RCLONE_ARCHIVE_ROOT_PATH/connection-verified"
          local RCLONE_ARCHIVE_PATH="$RCLONE_ARCHIVE_ROOT_PATH/archive-$HOSTNAME"
          local RCLONE_ARCHIVE_OLD_PATH="$RCLONE_ARCHIVE_PATH-old"
          local RCLONE_ARCHIVE_CONFIG="/root/salt/backup/rclone-archive/config"
          if [[ "$ARCHIVE_PATH_WORKINGDIR" == "check" ]]; then
              # Ensure rclone is available
              if ! command -v rclone >/dev/null; then
                  echo "Error: 'rclone' is not installed" >&2
                  return 1
              fi
              if [ ! -f "$RCLONE_ARCHIVE_CONFIG" ]; then
                  echo "Error: rclone configuration file '$RCLONE_ARCHIVE_CONFIG' is not set up" >&2
                  return 1
              fi
              if ! rclone --config "$RCLONE_ARCHIVE_CONFIG" listremotes | grep --quiet "$RCLONE_ARCHIVE_NAME"; then
                  echo "Error: rclone remote archive '$RCLONE_ARCHIVE_NAME' is not set up" >&2
                  return 1
              fi
              # Don't keep retrying in case of e.g. password issues
              if ! rclone --config "$RCLONE_ARCHIVE_CONFIG" --retries 1 touch "$RCLONE_ARCHIVE_TEST_UNCONFIRMED_PATH"; then
                  echo "Error: rclone unable to create files on remote archive '$RCLONE_ARCHIVE_NAME' - check user/pass?" >&2
                  return 1
              fi
              if ! rclone --config "$RCLONE_ARCHIVE_CONFIG" --retries 1 moveto "$RCLONE_ARCHIVE_TEST_UNCONFIRMED_PATH" "$RCLONE_ARCHIVE_TEST_CONFIRMED_PATH"; then
                  echo "Error: rclone unable to modify files on remote archive '$RCLONE_ARCHIVE_NAME' - check user/pass?" >&2
                  return 1
              fi
              # All good!
              return 0
          else
              # Make old backup directory in case it doesn't exist
              # (Avoids errors with the next command)
              if ! rclone --config "$RCLONE_ARCHIVE_CONFIG" mkdir "$RCLONE_ARCHIVE_OLD_PATH"; then
                  echo "Error: rclone create old archive directory" >&2
                  return 1
              fi
              # Delete current old backup directory
              if ! rclone --config "$RCLONE_ARCHIVE_CONFIG" purge "$RCLONE_ARCHIVE_OLD_PATH"; then
                  echo "Error: rclone create old archive directory" >&2
                  return 1
              fi
              # Make new backup directory in case it doesn't exist
              # (Avoids errors with the next command)
              if ! rclone --config "$RCLONE_ARCHIVE_CONFIG" mkdir "$RCLONE_ARCHIVE_PATH"; then
                  echo "Error: rclone create old archive directory" >&2
                  return 1
              fi
              # Move old backup out of the way (retain 1 old version)
              if ! rclone --config "$RCLONE_ARCHIVE_CONFIG" move "$RCLONE_ARCHIVE_PATH" "$RCLONE_ARCHIVE_OLD_PATH"; then
                  echo "Error: rclone move current to old archive directory failed" >&2
                  return 1
              fi
              # Run the upload here, return 0 on success
              if ! rclone --config "$RCLONE_ARCHIVE_CONFIG" sync "$ARCHIVE_PATH_WORKINGDIR" "$RCLONE_ARCHIVE_PATH"; then
                  echo "Error: rclone sync failed" >&2
                  return 1
              fi
              # Success
              return 0
          fi
        # postbackup
        # @returns 0 if successful, otherwise 1 (stops backup with error)
        #
        # Run after a backup, no parameters specified
        # Use to clean up filesystem snapshots, etc
        postbackup: ''
      # Backup encryption
      encrypt:
          # Enable or disable encryption of backups with GPG
          enable: False
          # Set to the GPG key ID used for receiving encrypted backups
          #
          # WARNING - You should use the full (not just long!) format of the
          # key ID to avoid ID collisions.
          #
          # WARNING - You must have the private key to the specified GPG key in order
          # to decrypt your backups!
          #
          # Remove spaces from key IDs (keep for email-based)
          gpg_keyid: 'AAAABBBBCCCCDDDDEEEEFFFF0000111122223333'
          # Name field <email@example.invalid>
      # Backup storage/working directory
      storage:
        # Path to persistent directory for backup modules and runtime
        # configuration.
        datadir: /root/salt/backup/system
        # Path to temporary working directory for backup creation.  This must have
        # enough space to store the entirety of the system backup.
        workdir: /var/backups/common-backup-system
