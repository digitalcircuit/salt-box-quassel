#!/bin/bash
# See http://redsymbol.net/articles/unofficial-bash-strict-mode/
set -euo pipefail

_LOCAL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# Get directory of this file

# Indicates that archive utilities have been loaded
MODULE_ARCHIVE_UTIL_LOADED="true"

# Production
ARCHIVE_SETTINGS_PATH="$_LOCAL_DIR/config-archive.sh"
# Testing
#ARCHIVE_SETTINGS_PATH="$_LOCAL_DIR/config-archive-TEST.sh"
#-------------------------------------------------------------
if [ -z "${MODULE_ARCHIVE_SETTINGS_LOADED:-}" ]; then
	source "$ARCHIVE_SETTINGS_PATH"
fi
#-------------------------------------------------------------
# Check if session environment is prepared
if [ -z "${MODULE_ARCHIVE_SETTINGS_LOADED:-}" ]; then
	# Quit as nothing can happen
	echo "Archive configuration not loaded, does the file 'config-archive.sh' exist? (will now exit)" >&2
	exit 1
fi
#-------------------------------------------------------------

ARCHIVE_SETTINGS_SCRIPT_PATH="$ARCHIVE_DATADIR_PATH/config-archive-script.sh"

# Workflow
#
# [check]
# Load configuration
# Working directory for archive path usable
# Post-backup move/upload command usable
# GPG setup
# > Validate parameters, update/verify keys if enabled
# Validate each backup module via "check"
#
# [backup]
# Validate configuration
# Acquire lock file for backup/restore
# Run pre-backup command (e.g. creating BTRFS snapshot)
# Create empty working archive path
# Run backup modules
# Run upload command
# > Include parameter: current archive path
# Run post-backup command (e.g. deleting BTRFS snapshot)
# Delete working archive path
#
# [restore]
# Validate configuration
# Acquire lock file for backup/restore
# Check for incoming archive
# > Error if encrypted
# Move archive to working archive path
# Run restore modules
# Delete working archive path

# Global variables
# ----

# Logging
ARCHIVE_WORKDIR_LOG_FILE="$ARCHIVE_WORKDIR_PATH/archive.log.txt"

# Encryption
# > Private variable parts
ARCHIVE_ENCRYPT_GPG_HOME="$ARCHIVE_DATADIR_PATH/gpg"
ARCHIVE_ENCRYPT_GPG_KEYSERVER="hkps://keys.openpgp.org"
#ARCHIVE_ENCRYPT_GPG_KEYID="$ARCHIVE_ENCRYPT_GPG_KEYID"
ARCHIVE_ENCRYPT_GPG_APP="gpg"
# Always trust the key (headless server, no web of trust here)
# See https://stackoverflow.com/questions/13116457/how-to-make-auto-trust-gpg-public-key
ARCHIVE_ENCRYPT_GPG_FILTER="$ARCHIVE_ENCRYPT_GPG_APP --batch --quiet --no-tty --homedir "$ARCHIVE_ENCRYPT_GPG_HOME" --encrypt --recipient "$ARCHIVE_ENCRYPT_GPG_KEYID" --trust-model=always --compress-algo none"
# > Encryption pipe command
ARCHIVE_ENCRYPT_FILTER="$ARCHIVE_ENCRYPT_GPG_FILTER"

# File extensions
ARCHIVE_BACKUP_EXT="gz"
ARCHIVE_BACKUP_EXT_PGP="$ARCHIVE_BACKUP_EXT.pgp"
ARCHIVE_BACKUP_TAR_EXT="tar.$ARCHIVE_BACKUP_EXT"
ARCHIVE_BACKUP_TAR_EXT_PGP="tar.$ARCHIVE_BACKUP_EXT_PGP"

# Modules
ARCHIVE_MODULE_PATH="$ARCHIVE_DATADIR_PATH/scripts.d"

# Library functions

# Proper locking using "flock" from util-linux
#
# Source:
# https://stackoverflow.com/questions/1715137/what-is-the-best-way-to-ensure-only-one-instance-of-a-bash-script-is-running
# https://gist.github.com/przemoc/571091
#
## Copyright (C) 2009 Przemyslaw Pawelczyk <przemoc@gmail.com>
##
## This script is licensed under the terms of the MIT license.
## https://opensource.org/licenses/MIT
#
# Lockable script boilerplate

### HEADER ###

ARCHIVE_LOCKFILE="/var/lock/`basename $0`"
ARCHIVE_LOCKFD=99

# PRIVATE
_archive_lock()             { flock -$1 $ARCHIVE_LOCKFD; }
_archive_no_more_locking()  { _archive_lock u; _archive_lock xn && rm -f $ARCHIVE_LOCKFILE; }
_archive_prepare_locking()  { eval "exec $ARCHIVE_LOCKFD>\"$ARCHIVE_LOCKFILE\""; trap _archive_no_more_locking EXIT; }

# ON START
_archive_prepare_locking

# PUBLIC
archive_exlock_now()        { _archive_lock xn; }  # obtain an exclusive lock immediately or fail
archive_exlock()            { _archive_lock x; }   # obtain an exclusive lock
archive_shlock()            { _archive_lock s; }   # obtain a shared lock
archive_unlock()            { _archive_lock u; }   # drop a lock

### BEGIN OF SCRIPT ###

## Simplest example is avoiding running multiple instances of script.
#exlock_now || exit 1
#
## Remember! Lock file is removed when one of the scripts exits and it is
##           the only script holding the lock or lock is not acquired at all.


# Functions
# ----

archive_check_system ()
{
	# Load configuration, check everything specified and usable
	if ! archive_hook_upload_cmd "check"; then
		echo "Error: archive_hook_upload_cmd check reports that it's not usable" >&2
		return 1
	fi

	if [ ! -d "$ARCHIVE_DATADIR_PATH" ]; then
		echo "Error: ARCHIVE_DATADIR_PATH does not point to an existing path ($ARCHIVE_DATADIR_PATH)" >&2
		return 1
	fi

	if [ -z "$ARCHIVE_WORKDIR_PATH" ]; then
		echo "Error: ARCHIVE_WORKDIR_PATH is not set" >&2
		return 1
	fi

	if ! archive_encrypt_prepare; then
		echo "Error: encryption not ready, fix issues, or disable encryption (not recommended)" >&2
		return 1
	fi

	local ARCHIVE_SYSTEM_ROOT_RESULT="$(archive_hook_printroot_cmd)"
	# Remove the trailing slash
	local ARCHIVE_SYSTEM_ROOT_PREFIX="${ARCHIVE_SYSTEM_ROOT_RESULT%/}"

	if [ ! -d "$ARCHIVE_SYSTEM_ROOT_PREFIX/" ]; then
		echo "Error: archive_hook_printroot_cmd does not provide an existing path ($ARCHIVE_SYSTEM_ROOT_PREFIX/)" >&2
		return 1
	fi

	# Save relevant configuration settings for scripts
	if ! cat >"$ARCHIVE_SETTINGS_SCRIPT_PATH" <<EOL
#!/bin/bash
# #### #### ####
# WARNING: Automatically generated, edits will be lost!
# #### #### ####

# Indicates that archive configuration has been loaded
MODULE_ARCHIVE_SCRIPT_SETTINGS_LOADED="true"

# Relevant settings
# > Encryption
ARCHIVE_ENCRYPT_ENABLE="$ARCHIVE_ENCRYPT_ENABLE"
ARCHIVE_ENCRYPT_FILTER="$ARCHIVE_ENCRYPT_FILTER"
# > Root filesystem prefix (for backups, e.g. snapshot)
ARCHIVE_SYSTEM_ROOT_PREFIX="$ARCHIVE_SYSTEM_ROOT_PREFIX"
# > File extensions
ARCHIVE_BACKUP_EXT="$ARCHIVE_BACKUP_EXT"
ARCHIVE_BACKUP_EXT_PGP="$ARCHIVE_BACKUP_EXT_PGP"
ARCHIVE_BACKUP_TAR_EXT="$ARCHIVE_BACKUP_TAR_EXT"
ARCHIVE_BACKUP_TAR_EXT_PGP="$ARCHIVE_BACKUP_TAR_EXT_PGP"
EOL
	then
		echo "Error: unable to save settings for individual scripts, could not modify '$ARCHIVE_SETTINGS_SCRIPT_PATH'" >&2
		return 1
	fi

	# Make sure each backup module has everything needed
	#
	# run-parts:
	#   --verbose:  Show all
	#   --report:   Show only failed
	if ! run-parts --lsbsysinit --exit-on-error --report \
		--arg="check" "$ARCHIVE_MODULE_PATH"; then
		echo "[!] Error: backup modules not ready in '$ARCHIVE_MODULE_PATH'" >&2
		return 1
	fi
}

archive_encrypt_prepare ()
{
	if [[ "$ARCHIVE_ENCRYPT_ENABLE" != "true" ]]; then
		# Encryption disabled, set pipe command to fail if used, pass checks
		ARCHIVE_ENCRYPT_FILTER="false"
		return 0
	fi

	if [ -z "$ARCHIVE_ENCRYPT_GPG_KEYID" ]; then
		echo "Error: ARCHIVE_ENCRYPT_GPG_KEYID does not point to a GPG key ID" >&2
		return 1
	fi

	# Encryption variables are set on load

	# Set up GPG
	# > Prepare directories
	if [ ! -d "$ARCHIVE_DATADIR_PATH" ] ; then
		mkdir "$ARCHIVE_DATADIR_PATH" || return 1
	fi
	if [ ! -d "$ARCHIVE_ENCRYPT_GPG_HOME" ] ; then
		mkdir "$ARCHIVE_ENCRYPT_GPG_HOME" || return 1
	fi
	# > Ensure tight permissions
	if [[ "$ARCHIVE_DEBUG_DISABLE_SECURE_PATH" != "true" ]]; then
		# Allowed, change to root
		chown root:root "$ARCHIVE_ENCRYPT_GPG_HOME" || return 1
	else
		# Disallowed, warn
		echo "WARNING: Ownership of GPG home is unchanged!" >&2
		echo "         Set ARCHIVE_DEBUG_DISABLE_SECURE_PATH = true to fix." >&2
	fi
	chmod 700 "$ARCHIVE_ENCRYPT_GPG_HOME" || return 1
	# > Fetch/update key
	if ! "$ARCHIVE_ENCRYPT_GPG_APP" --batch --quiet --no-tty --homedir "$ARCHIVE_ENCRYPT_GPG_HOME" --keyserver "$ARCHIVE_ENCRYPT_GPG_KEYSERVER" --recv-keys "$ARCHIVE_ENCRYPT_GPG_KEYID" >/dev/null 2>&1; then
		echo "Error: failed to fetch GPG key ID '$ARCHIVE_ENCRYPT_GPG_KEYID'!" >&2
		echo "       To debug, remove the stdout/stderr redirection" >&2
		# Remove the ">/dev/null 2>&1" at the end
		return 1
	fi
	# > Trust the key
	# See https://blog.tersmitten.nl/how-to-ultimately-trust-a-public-key-non-interactively.html
#	echo "$( \
#  $ARCHIVE_ENCRYPT_GPG_APP --batch --quiet --no-tty --homedir "$ARCHIVE_ENCRYPT_GPG_HOME" --list-keys --keyid-format LONG --fingerprint \
#  | grep $ARCHIVE_ENCRYPT_GPG_KEYID -A 1 | tail -1 \
#  | tr -d '[:space:]' | awk 'BEGIN { FS = "=" } ; { print $2 }' \
#):6:" | "$ARCHIVE_ENCRYPT_GPG_APP" --batch --quiet --no-tty --homedir "$ARCHIVE_ENCRYPT_GPG_HOME" --import-ownertrust || return 1
	#
	# NOTE: Removed in favor of trust-model
	# If you're non-interactively trusting a key, there's no benefit to keeping
	# the trust model.
	#
	# WARNING: Use full (not long, not short) key IDs!

	# Try encrypting something to verify functionality
	local TEMP_FILE="$(mktemp)" || return 1
	if ! (echo "Current date/time: $(date)" | $ARCHIVE_ENCRYPT_FILTER > "$TEMP_FILE"); then
		echo "Error: failed to encrypt using GPG!" >&2
		rm "$TEMP_FILE" || return 1
		return 1
	fi
	# Clean up
	rm "$TEMP_FILE" || return 1
}

archive_run_backup ()
{
	# Validate system first
	if ! archive_check_system; then
		echo "[!] Error running backup: system not ready" >&2
		return 1
	fi

	# Obtain lock
	if ! archive_exlock_now; then
		echo "[!] Error running backup: archive system already running backup or restore" >&2
		return 1
	fi

	# Run prebackup command
	if ! archive_hook_prebackup_cmd; then
		echo "[!] Error running backup: archive_hook_prebackup_cmd failed" >&2
		archive_unlock
		return 1
	fi

	# Prepare working directory
	# > Prepare directories
	if ! mkdir --parents "$ARCHIVE_WORKDIR_PATH"; then
		echo "[!] Error running backup: failed to create working directory '$ARCHIVE_WORKDIR_PATH'" >&2
		archive_unlock
		return 1
	fi

	# > Ensure tight permissions
	if [[ "$ARCHIVE_DEBUG_DISABLE_SECURE_PATH" != "true" ]]; then
		# Allowed, change to root
		chown root:root "$ARCHIVE_WORKDIR_PATH" || return 1
	else
		# Disallowed, warn
		echo "WARNING: Ownership of archive work directory is unchanged!" >&2
		echo "         Set ARCHIVE_DEBUG_DISABLE_SECURE_PATH = true to fix." >&2
	fi
	chmod 700 "$ARCHIVE_WORKDIR_PATH" || return 1

	# Verify log file is accessible
	if ! touch "$ARCHIVE_WORKDIR_LOG_FILE"; then
		echo "[!] Error running backup: failed to create log file '$ARCHIVE_WORKDIR_LOG_FILE'" >&2
		# Clean up temporary directory
		rm --recursive "$ARCHIVE_WORKDIR_PATH"
		archive_unlock
		return 1
	fi

	echo "[$(date --rfc-3339=seconds)] [archive] Starting backup..." >> "$ARCHIVE_WORKDIR_LOG_FILE"

	# Run each available backup module
	#
	# run-parts:
	#   --verbose:        Show all
	#   --report:         Show only failed
	#   --exit-on-error:  Exit as soon as a script fails
	#
	if ! run-parts --lsbsysinit --exit-on-error --verbose \
		--arg="backup" --arg="$ARCHIVE_WORKDIR_PATH" \
		"$ARCHIVE_MODULE_PATH" >> "$ARCHIVE_WORKDIR_LOG_FILE" 2>&1; then
		echo "[!] Error running backup: failed to run modules in '$ARCHIVE_MODULE_PATH'" >&2
		echo "Standard output:"
		echo "$(< "$ARCHIVE_WORKDIR_LOG_FILE")"
		# Clean up temporary directory
		rm --recursive "$ARCHIVE_WORKDIR_PATH"
		archive_unlock
		return 1
	fi

	echo "[$(date --rfc-3339=seconds)] [archive] Backup ready for upload (expected end of log)" >> "$ARCHIVE_WORKDIR_LOG_FILE"

	# Upload backup via upload command
	# Upload the working directory now that backup has finished
	if ! archive_hook_upload_cmd "$ARCHIVE_WORKDIR_PATH"; then
		echo "[!] Error running backup: archive_hook_upload_cmd failed" >&2
		echo "Standard output:"
		echo "$(< "$ARCHIVE_WORKDIR_LOG_FILE")"
		# Clean up temporary directory
		rm --recursive "$ARCHIVE_WORKDIR_PATH"
		archive_unlock
		return 1
	fi

	# Remove working directory
	if ! rm --recursive "$ARCHIVE_WORKDIR_PATH"; then
		echo "[!] Error running backup: failed to remove working directory '$ARCHIVE_WORKDIR_PATH'" >&2
		archive_unlock
		return 1
	fi

	# Run postbackup command
	if ! archive_hook_postbackup_cmd; then
		echo "[!] Error running backup: archive_hook_postbackup_cmd failed" >&2
		archive_unlock
		return 1
	fi

	# Remove lock
	archive_unlock
}

archive_run_restore ()
{
	local EXPECTED_ARGS=1
	if [[ $# -ne $EXPECTED_ARGS ]]; then
		echo "Usage: `basename $0` [archive_run_restore] {path to unencrypted archive directory}" >&2
		return 1
	fi
	local ARCHIVE_RESTORE_INPUT="$1"

	# Check incoming archive
	if [ ! -d "$ARCHIVE_RESTORE_INPUT" ]; then
		echo "[!] Error running restore: incoming archive '$ARCHIVE_RESTORE_INPUT' does not exist" >&2
		return 1
	fi

	# Check if encrypted files exist
	# See https://stackoverflow.com/questions/6363441/check-if-a-file-exists-with-wildcard-in-shell-script
	if test -n "$(find "$ARCHIVE_RESTORE_INPUT" -iname '*.pgp' -print -quit)"; then
		echo "[!] Error running restore: incoming archive has encrypted files." >&2
		echo "    Decrypt files before attempting to run a restore (no '.pgp' files)." >&2
		return 1
	fi

	echo "[$(date --rfc-3339=seconds)] [archive] Validating system..."

	# Validate system
	if ! archive_check_system; then
		echo "[!] Error running restore: system not ready" >&2
		return 1
	fi

	# Obtain lock
	if ! archive_exlock_now; then
		echo "[!] Error running restore: archive system already running backup or restore" >&2
		return 1
	fi

	# Prepare working directory
	# > Prepare directories
	if ! mkdir --parents "$ARCHIVE_WORKDIR_PATH"; then
		echo "[!] Error running restore: failed to create working directory '$ARCHIVE_WORKDIR_PATH'" >&2
		archive_unlock
		return 1
	fi

	# > Ensure tight permissions
	if [[ "$ARCHIVE_DEBUG_DISABLE_SECURE_PATH" != "true" ]]; then
		# Allowed, change to root
		chown root:root "$ARCHIVE_WORKDIR_PATH" || return 1
	else
		# Disallowed, warn
		echo "WARNING: Ownership of archive work directory is unchanged!" >&2
		echo "         Set ARCHIVE_DEBUG_DISABLE_SECURE_PATH = true to fix." >&2
	fi
	chmod 700 "$ARCHIVE_WORKDIR_PATH" || return 1

	echo "[$(date --rfc-3339=seconds)] [archive] Starting restore..."

	# Copy archive to working path
	if ! cp --recursive "$ARCHIVE_RESTORE_INPUT"/* "$ARCHIVE_WORKDIR_PATH"; then
		echo "[!] Error running restore: failed to copy incoming archive '$ARCHIVE_RESTORE_INPUT' to working directory '$ARCHIVE_WORKDIR_PATH'" >&2
		archive_unlock
		return 1
	fi

	# Run each available restore module
	#
	# run-parts:
	#   --verbose:        Show all
	#   --report:         Show only failed
	#   --exit-on-error:  Exit as soon as a script fails
	#
	# Don't exit-on-error, try to restore as much as possible!
	#
	if ! run-parts --lsbsysinit --verbose \
		--arg="restore" --arg="$ARCHIVE_WORKDIR_PATH" \
		"$ARCHIVE_MODULE_PATH"; then
		echo "[!] Error running restore: failed to run modules in '$ARCHIVE_MODULE_PATH'" >&2
		# Clean up temporary directory
		rm --recursive "$ARCHIVE_WORKDIR_PATH"
		archive_unlock
		return 1
	fi

	# Remove working directory
	if ! rm --recursive "$ARCHIVE_WORKDIR_PATH"; then
		echo "[!] Error running backup: failed to remove working directory '$ARCHIVE_WORKDIR_PATH'" >&2
		archive_unlock
		return 1
	fi

	# Remove lock
	archive_unlock

	echo "[$(date --rfc-3339=seconds)] [archive] Restore done"
}
