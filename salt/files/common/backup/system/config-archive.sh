#!/bin/bash
# See http://redsymbol.net/articles/unofficial-bash-strict-mode/
set -euo pipefail

# Indicates that archive configuration has been loaded
MODULE_ARCHIVE_SETTINGS_LOADED="true"

# [Storage]
#
# ----
# ARCHIVE_WORKDIR_PATH
# Required; suggested: "/var/backups/common-backup-system"
#
# Path to temporary working directory for backup creation.  This must have
# enough space to store the entirety of the system backup.
#
ARCHIVE_WORKDIR_PATH="{{ salt['pillar.get']('common:backup:system:storage:workdir', '/var/backups/common-backup-system') }}"
#
# ----
# ARCHIVE_CONFIGDIR_PATH
# Required; suggested: "/etc/opt/archive"
#
# Path to persistent directory for backup modules and runtime configuration.
#
ARCHIVE_DATADIR_PATH="{{ salt['pillar.get']('common:backup:system:storage:datadir', '/root/salt/backup/system') }}"
#
# ----
# ARCHIVE_DEBUG_DISABLE_SECURE_PATH
# Set to 'true' or 'false'
#
# If false (default), temporary archive directories will be chown'd
# (change owner'd) to root where applicable, helping ensure the security and
# privacy of archives.  This requires running the archive script as root.  For
# testing, you may want to disable this.
#
# WARNING: Disabling secure paths may result in leaking your private
# information!
#
ARCHIVE_DEBUG_DISABLE_SECURE_PATH=false

# [Encryption]
#
# ----
# ARCHIVE_ENCRYPT_ENABLE
# Set to 'true' or 'false'
#
# If true, enable encryption of backups with GPG.  This requires specifying
# ARCHIVE_ENCRYPT_GPG_KEYID as well.
#
# WARNING: You must have the private key to the GPG key in order to decrypt
# your backups!
#
ARCHIVE_ENCRYPT_ENABLE={{ salt['pillar.get']('common:backup:system:encrypt:enable', 'false') | lower }}
#
# ----
# ARCHIVE_ENCRYPT_GPG_KEYID
# Set to the GPG key ID used for receiving encrypted backups
#
# NOTE: You should use the long format of the key ID to avoid ID collisions.
#
# WARNING: You must have the private key to the specified GPG key in order to
# decrypt your backups!
#
ARCHIVE_ENCRYPT_GPG_KEYID="{{ salt['pillar.get']('common:backup:system:encrypt:gpg_keyid', '') }}"

# [Hooks]
#
# ----
# archive_hook_prebackup_cmd
# @returns 0 if successful, otherwise 1 (stops backup with error)
#
# Run before a backup, no parameters specified
# Use to create filesystem snapshots, etc
archive_hook_prebackup_cmd ()
{
	: # Bash no-op - allow for empty commands
	{{ salt['pillar.get']('common:backup:system:script:prebackup', '') }}
}
#
# ----
# archive_hook_printroot_cmd
# @prints  Path to root
#
# Run before a backup, should print path to filesystem root
# Use to backup from filesystem snapshots, etc
# NOTE: some backup modules may ignore this, e.g. database dumps
archive_hook_printroot_cmd ()
{
	{{ salt['pillar.get']('common:backup:system:script:printroot', '
	# Default: real root
	echo "/"
') }}
}
#
# ----
# archive_hook_upload_cmd
# @param  $1  Path to directory of current backup archive, or 'check' to test
#             if working
# @returns 0 if successful, otherwise 1 (stops backup with error)
#
# Run after a backup, should upload to a remote location or move the files
# outside of the current archive.
# Special-case "check" as the working directory to check if all dependencies
# are available.
#
# WARNING: The current archive is deleted after this command is run.  Backups
# must be uploaded/moved elsewhere to be saved!
archive_hook_upload_cmd ()
{
	local EXPECTED_ARGS=1
	if [ $# -ne $EXPECTED_ARGS ]; then
		echo "Usage: [archive_hook_upload_cmd] {path to directory of current backup archive, or 'check'}" >&2
		return 1
	fi
	local ARCHIVE_PATH_WORKINGDIR="$1"

	{{ salt['pillar.get']('common:backup:system:script:upload', '
	# Default: do nothing
	if [[ "$ARCHIVE_PATH_WORKINGDIR" == "check" ]]; then
		# Things are not ready, this command should be customized
		return 1
	else
		# Run the upload here, return 0 on success
		return 1
	fi
') }}
}
#
# ----
# archive_hook_postbackup_cmd
# @returns 0 if successful, otherwise 1 (stops backup with error)
#
# Run after a backup, no parameters specified
# Use to clean up filesystem snapshots, etc
archive_hook_postbackup_cmd ()
{
	: # Bash no-op - allow for empty commands
	{{ salt['pillar.get']('common:backup:system:script:postbackup', '') }}
}
