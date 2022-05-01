#!/bin/bash
# See http://redsymbol.net/articles/unofficial-bash-strict-mode/
set -euo pipefail

_LOCAL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# Get directory of this file

#-------------------------------------------------------------
if [ -z "${MODULE_ARCHIVE_UTIL_LOADED:-}" ]; then
	source "$_LOCAL_DIR/util-archive.sh"
fi
#-------------------------------------------------------------
# Check if session environment is prepared
if [ -z "${MODULE_ARCHIVE_UTIL_LOADED:-}" ]; then
	# Quit as nothing can happen
	echo "Archive configuration module not loaded, does the file 'util-archive.sh' exist? (will now exit)" >&2
	exit 1
fi
#-------------------------------------------------------------

EXPECTED_ARGS=1
if [ $# -ge $EXPECTED_ARGS ]; then
	case $1 in
		"backup" )
			if ! archive_run_backup; then
				echo "Error running backup" >&2
				exit 1
			fi
			;;
		"check" )
			# Allow non-zero exit to capture return value
			set +e
			archive_check_system
			RETURN_VALUE=$?
			set -e
			# Provide status in a format Salt can parse
			# See https://docs.saltstack.com/en/latest/ref/states/all/salt.states.cmd.html#using-the-stateful-argument
			if [ $RETURN_VALUE -eq 0 ]; then
				echo "changed=no comment='Archive system is ready'"
			else
				echo "changed=no comment='Archive system is not ready (check configuration, backup destination, encryption, or if a backup/restore is already in progress)'"
			fi
			# Return status
			exit $RETURN_VALUE
			;;
		"restore" )
			EXPECTED_ARGS=2
			if [ $# -ge $EXPECTED_ARGS ]; then
				# Ignore the prefix of 'restore'
				array=( $* )
				len=${#array[*]}
				# See http://www.cyberciti.biz/faq/linux-unix-appleosx-bash-script-extract-parameters-before-last-args/
				if ! archive_run_restore "${array[@]:1:$len}"; then
					echo "Error running restore" >&2
					exit 1
				fi
			else
				echo "Usage: `basename "$0"` restore {path to unencrypted archive directory}" >&2
			fi
			;;
		* )
			echo "Usage: `basename "$0"` {command: backup, check, restore}" >&2
			;;
	esac
else
	echo "Usage: `basename "$0"` {command: backup, check, restore}" >&2
fi
