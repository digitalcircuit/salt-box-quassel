#!/bin/bash
# Check if running before updating; if so, don't allow update
QUASSEL_SERVICE_NAME="quasselcore.service"

QUASSEL_SERVICE_USER="quasselcore"

QUASSEL_CONFIG_DIR="/var/lib/quassel"

quassel_running () {
	if systemctl -q is-active "$QUASSEL_SERVICE_NAME"; then
		return 0
	else
		return 1
	fi
}

quassel_configure_backend () {
	EXPECTED_ARGS=5
	if [ $# -ne $EXPECTED_ARGS ]; then
		echo "Usage: `basename $0` [quassel_configure_backend] {PSQL user name} {PSQL user password} {PSQL hostname} {PSQL port} {PSQL database name}" >&2
		return 1
	fi
	
	local QUASSEL_PSQL_USER_NAME="$1"
	local QUASSEL_PSQL_USER_PASSWORD="$2"
	local QUASSEL_PSQL_HOSTNAME="$3"
	local QUASSEL_PSQL_PORT="$4"
	local QUASSEL_PSQL_DB_NAME="$5"
	# Set up the PostgreSQL backend
	# NOTE: Quassel currently doesn't succeed in adding a user when first configuring storage backend.
	sudo --user quasselcore quasselcore --select-backend=PostgreSQL --configdir="$QUASSEL_CONFIG_DIR" << QSETUP_ANSWERS
$QUASSEL_PSQL_USER_NAME
$QUASSEL_PSQL_USER_PASSWORD
$QUASSEL_PSQL_HOSTNAME
$QUASSEL_PSQL_PORT
$QUASSEL_PSQL_DB_NAME
invalid_user_no_password


QSETUP_ANSWERS
	# These spaces intentionally left blank
	# NOTE: As mentioned above, Quassel doesn't succeed, so return value will never be true.
	#return $?
	return 0
}

quassel_configure_user () {
	EXPECTED_ARGS=2
	if [ $# -ne $EXPECTED_ARGS ]; then
		echo "Usage: `basename $0` [quassel_configure_user] {Quassel user name} {Quassel user password}" >&2
		return 1
	fi
	
	local QUASSEL_USER_NAME="$1"
	local QUASSEL_USER_PASSWORD="$2"
	# Set up a new user
	sudo --user quasselcore quasselcore --add-user --configdir="$QUASSEL_CONFIG_DIR" << QSETUP_ANSWERS
$QUASSEL_USER_NAME
$QUASSEL_USER_PASSWORD
$QUASSEL_USER_PASSWORD
QSETUP_ANSWERS
	# Return the result
	return $?
}

quassel_is_configured () {
	if grep "StorageSettings=" --quiet "$QUASSEL_CONFIG_DIR/quasselcore.conf"; then
		# Storage backend has been configured
		return 0
	else
		return 1
	fi
}

quassel_configure () {
	local EXPECTED_ARGS=7
	if [ $# -ne $EXPECTED_ARGS ]; then
		echo "Usage: `basename "$0"` [quassel_configure] {PSQL user name} {PSQL user password} {PSQL hostname} {PSQL port} {PSQL database name} {Quassel admin user name} {Quassel admin user password}" >&2
		return 1
	fi
	local QUASSEL_PSQL_USER_NAME="$1"
	local QUASSEL_PSQL_USER_PASSWORD="$2"
	local QUASSEL_PSQL_HOSTNAME="$3"
	local QUASSEL_PSQL_PORT="$4"
	local QUASSEL_PSQL_DB_NAME="$5"
	local QUASSEL_ADMIN_USER_NAME="$6"
	local QUASSEL_ADMIN_USER_PASSWORD="$7"
	
	if ! quassel_is_configured; then
		local QUASSEL_STOPPED=false
		if quassel_running; then
			echo "> Stopping Quassel core (systemctl stop $QUASSEL_SERVICE_NAME)..."
			systemctl stop "$QUASSEL_SERVICE_NAME"
			QUASSEL_STOPPED=true
		fi
		# Set up the storage backend
		echo "> Configuring backend..."
		quassel_configure_backend "$QUASSEL_PSQL_USER_NAME" "$QUASSEL_PSQL_USER_PASSWORD" "$QUASSEL_PSQL_HOSTNAME" "$QUASSEL_PSQL_PORT" "$QUASSEL_PSQL_DB_NAME" || return 1 # Failed
		# Set up the first (admin) user
		echo "> Configuring user..."
		quassel_configure_user "$QUASSEL_ADMIN_USER_NAME" "$QUASSEL_ADMIN_USER_PASSWORD" || return 1 # Failed
		if [ "$QUASSEL_STOPPED" = true ]; then
			echo "> Starting Quassel core (systemctl start $QUASSEL_SERVICE_NAME)..."
			systemctl start "$QUASSEL_SERVICE_NAME"
		fi
		echo "> Configuration complete!"
	else
		echo "> Quassel already configured"
	fi
}

EXPECTED_ARGS=1
if [ $# -ge $EXPECTED_ARGS ]; then
	case $1 in
		"check" )
			quassel_is_configured
			# Return the status code
			exit $?
			;;
		"configure" )
			EXPECTED_ARGS=8 # 1 + 7
			if [ $# -eq $EXPECTED_ARGS ]; then
				quassel_configure "$2" "$3" "$4" "$5" "$6" "$7" "$8"
				# Return the status code
				exit $?
			else
				echo "Usage: `basename $0` configure {PSQL user name} {PSQL user password} {PSQL hostname} {PSQL port} {PSQL database name} {Quassel admin user name} {Quassel admin user password}" >&2
				exit 1
			fi
			;;
		* )
			echo "Usage: `basename $0` {command: check, configure}" >&2
			exit 1
			;;
	esac
else
	echo "Usage: `basename $0` {command: check, configure}" >&2
	exit 1
fi
