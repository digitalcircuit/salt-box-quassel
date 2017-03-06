#!/bin/bash
set -u # Bash - fail on undefined variable

# When adding new domains, Let's Encrypt tool needs "--expand" flag

#RSA_KEY_SIZE="2048"
# Default:      2048
# Alternative:  4096

CERTBOT_TOOL="certbot"

CERTBOT_PATH_BASE="/etc/letsencrypt"
CERTBOT_PATH_KEYS="$CERTBOT_PATH_BASE/live"
CERTBOT_PATH_RENEWAL="$CERTBOT_PATH_BASE/renewal"

# Standalone, webroot via nginx, non-interactive
CERTBOT_TOOL_OPTIONS="--agree-tos --webroot --webroot-path /var/lib/letsencrypt --non-interactive"
CERTBOT_TOOL_OPTIONS_RENEW="--non-interactive"
# > To specify a different RSA key size, use:  --rsa-key-size "$RSA_KEY_SIZE"

QUASSEL_PATH_KEY="/var/lib/quassel/le-privkey.pem"
QUASSEL_PATH_CERT="/var/lib/quassel/le-fullchain.pem"

CERTBOT_LOCAL_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CERTBOT_LOCAL_SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")
CERTBOT_LOCAL_SCRIPT_PATH="$CERTBOT_LOCAL_SCRIPT_DIR/$CERTBOT_LOCAL_SCRIPT_NAME"

# Update the certificates

certbot_renew ()
{
	local EXPECTED_ARGS=1
	if [ $# -ne $EXPECTED_ARGS ]; then
		echo "Usage: `basename "$0"` [certbot_renew] {system hostname}" >&2
		return 1
	fi
	local CERTBOT_DOMAIN="$1"
	# Before, had to use 'certonly' and '--keep-until-expiring'
	# https://community.letsencrypt.org/t/help-us-test-renewal-with-letsencrypt-renew/10562
	"$CERTBOT_TOOL" renew --quiet --post-hook "$CERTBOT_LOCAL_SCRIPT_PATH reload $CERTBOT_DOMAIN" $CERTBOT_TOOL_OPTIONS_RENEW || return 1
	# > To force an update, use --force-renewal
	# > For testing, use --dry-run
}

certbot_reload_nginx ()
{
	echo " * Reloading certificate for Nginx..."
	sudo service nginx reload || return 1
}

certbot_reload_quassel ()
{
	local EXPECTED_ARGS=1
	if [ $# -ne $EXPECTED_ARGS ]; then
		echo "Usage: `basename "$0"` [certbot_reload_quassel] {system hostname}" >&2
		return 1
	fi
	local CERTBOT_DOMAIN="$1"
	
	echo " * Updating certificate copies for Quassel..."
	sudo cp "$CERTBOT_PATH_KEYS/$CERTBOT_DOMAIN/privkey.pem" "$QUASSEL_PATH_KEY" || return 1
	sudo cp "$CERTBOT_PATH_KEYS/$CERTBOT_DOMAIN/fullchain.pem" "$QUASSEL_PATH_CERT" || return 1
	sudo chown quasselcore:quassel "$QUASSEL_PATH_KEY" "$QUASSEL_PATH_CERT" || return 1
	sudo chmod 640 "$QUASSEL_PATH_KEY" "$QUASSEL_PATH_CERT" || return 1
	# Quassel 0.13+: reload certificate via SIGHUP signal
	echo " > Reloading Quassel..."
	sudo service quasselcore reload || return 1
}

certbot_reload ()
{
	local EXPECTED_ARGS=1
	if [ $# -ne $EXPECTED_ARGS ]; then
		echo "Usage: `basename "$0"` [certbot_reload] {system hostname}" >&2
		return 1
	fi
	local CERTBOT_DOMAIN="$1"
	
	certbot_reload_nginx || return 1
	certbot_reload_quassel "$CERTBOT_DOMAIN" || return 1
}

certbot_is_configured () {
	local EXPECTED_ARGS=1
	if [ $# -ne $EXPECTED_ARGS ]; then
		echo "Usage: `basename "$0"` [certbot_is_configured] {system hostname}" >&2
		return 1
	fi
	local CERTBOT_DOMAIN="$1"
	
	if [ -f "$CERTBOT_PATH_RENEWAL/$CERTBOT_DOMAIN.conf" ]; then
		# Certbot has been configured
		return 0
	else
		return 1
	fi
}

certbot_configure () {
	local EXPECTED_ARGS=3
	if [ $# -ne $EXPECTED_ARGS ]; then
		echo "Usage: `basename "$0"` [certbot_configure] {system hostname} {testing mode - true/false} {account recovery email}" >&2
		return 1
	fi
	local CERTBOT_DOMAIN="$1"
	local CERTBOT_TESTING_FLAG="$2"
	local CERTBOT_EMAIL="$3"
	local CERTBOT_TESTING=false
	
	local CERTBOT_EXTRA_FLAGS=""
	
	case "$CERTBOT_TESTING_FLAG" in
		"True" | "true" | "yes" | "t" | "y" )
			CERTBOT_TESTING=true
			;;
		"False" | "false" | "no" | "f" | "n" )
			CERTBOT_TESTING=false
			;;
		* )
			echo "Usage: `basename "$0"` [certbot_configure] {system hostname} {testing mode - true/false} {account recovery email}" >&2
			return 1
			;;
	esac
	
	if [ "$CERTBOT_TESTING" = true ]; then
		# Use the staging server to get test certificates
		CERTBOT_EXTRA_FLAGS="$CERTBOT_EXTRA_FLAGS --test-cert"
	fi
	
	if ! certbot_is_configured "$CERTBOT_DOMAIN"; then
		echo " * Requesting certificates..."
		# Clean up any existing live directories, avoids a crash in 0.9.3.
		#   CertStorageError: live directory exists for quassel.test.zorro.casa
		# TODO: Is there a better way around this?  It wipes out existing live keys.
		if [ -f "$CERTBOT_PATH_KEYS/$CERTBOT_DOMAIN/is_dummy_certs" ]; then			
			sudo rm --recursive "$CERTBOT_PATH_KEYS/$CERTBOT_DOMAIN"
		fi
		"$CERTBOT_TOOL" certonly --email "$CERTBOT_EMAIL" --domains "$CERTBOT_DOMAIN" $CERTBOT_TOOL_OPTIONS $CERTBOT_EXTRA_FLAGS || return 1
		# The first "--domains" is the base folder for certificates, and the primary key.
		# Secondary "--domains" will be added as subjectAltName entries.
		echo "> Configuration complete!"
	else
		echo "> Certbot already configured"
	fi
}

EXPECTED_ARGS=1
if [ $# -ge $EXPECTED_ARGS ]; then
	case $1 in
		"configure" )
			EXPECTED_ARGS=4 # 1 + 3
			if [ $# -eq $EXPECTED_ARGS ]; then
				certbot_configure "$2" "$3" "$4" || exit 1
				certbot_reload "$2" || exit 1
			else
				echo "Usage: `basename $0` configure {system hostname} {testing mode - true/false} {account recovery email}" >&2
				exit 1
			fi
			;;
		"check" )
			EXPECTED_ARGS=2 # 1 + 1
			if [ $# -eq $EXPECTED_ARGS ]; then
				certbot_is_configured "$2"
				# Return the status code
				exit $?
			else
				echo "Usage: `basename $0` check {system hostname}" >&2
				exit 1
			fi
			;;
		"renew" )
			EXPECTED_ARGS=2 # 1 + 1
			if [ $# -eq $EXPECTED_ARGS ]; then
				certbot_renew "$2" || exit 1
				# Reloading is handled by post-renewal hooks
			else
				echo "Usage: `basename $0` renew {system hostname}" >&2
				exit 1
			fi
			;;
		"reload" )
			EXPECTED_ARGS=2 # 1 + 1
			if [ $# -eq $EXPECTED_ARGS ]; then
				certbot_reload "$2" || exit 1
				# Reloading is handled by post-renewal hooks
			else
				echo "Usage: `basename $0` reload {system hostname}" >&2
				exit 1
			fi
			;;
		* )
			echo "Usage: `basename $0` {command: setup, renew, reload}" >&2
			exit 1
			;;
	esac
else
	echo "Usage: `basename $0` {command: setup, renew, reload}" >&2
	exit 1
fi
