#!/bin/bash
# See http://redsymbol.net/articles/unofficial-bash-strict-mode/
set -euo pipefail

# When adding new domains, Let's Encrypt tool needs "--expand" flag

#RSA_KEY_SIZE="2048"
# Default:      2048
# Alternative:  4096

CERTBOT_TOOL="certbot"

CERTBOT_PATH_BASE="/etc/letsencrypt"
CERTBOT_PATH_KEYS="$CERTBOT_PATH_BASE/live"
CERTBOT_PATH_RENEWAL="$CERTBOT_PATH_BASE/renewal"

CERTBOT_NAME_PRIVKEY="privkey.pem"
CERTBOT_NAME_FULLCHAIN="fullchain.pem"

# Standalone, webroot via nginx, non-interactive
CERTBOT_TOOL_OPTIONS="--agree-tos --webroot --webroot-path /var/lib/letsencrypt --non-interactive"
CERTBOT_TOOL_OPTIONS_RENEW="--non-interactive"
CERTBOT_TOOL_OPTIONS_DELETE="$CERTBOT_TOOL_OPTIONS_RENEW"
# > To specify a different RSA key size, use:  --rsa-key-size "$RSA_KEY_SIZE"

# Command to deploy
CERTBOT_HOOK_DEPLOY_CMD="deploy"

CERTBOT_SETUP_HOOKS_DIR_NAME="renewal-hooks-deploy"

CERTBOT_SETUP_DOMAIN_FILE="domains.conf"
CERTBOT_SETUP_KEY_PRIMARY="primary"
CERTBOT_SETUP_KEY_ALT="alternatives"
CERTBOT_SETUP_KEY_EMAIL="email"
CERTBOT_SETUP_KEY_STAGING="staging"

# Runtime configuration
# --------
# Logging
CERTBOT_LOG_PREFIX="*"
CERTBOT_SCRIPT_CMD="`basename "$0"`"

# Path to certificate configuration files
CERTBOT_SETUP_PATH=""
# Renewed cert name/lineage when deployment happens
CERTBOT_HOOK_DEPLOY_RENEWED_LINEAGE=""
# Whether or not certs have been loaded once
CERTBOT_SETUP_CERTS_LOADED=false
# Array of certificate names
declare -a CERTBOT_SETUP_CERT_NAMES
# Associative array of certificate configuration, indexed by name
declare -A CERTBOT_SETUP_CERTS_PRIMARY
declare -A CERTBOT_SETUP_CERTS_ALT
declare -A CERTBOT_SETUP_CERTS_EMAIL
declare -A CERTBOT_SETUP_CERTS_STAGING

certbot_get_certs_reset ()
{
	# Reset loading marker
	CERTBOT_SETUP_CERTS_LOADED=false
	# Clear the name array
	CERTBOT_SETUP_CERT_NAMES=()
	# Clear the associative array
	# Don't use unset/declare as that makes the arrays local
	# See https://stackoverflow.com/questions/10497425/is-it-possible-to-use-array-in-bash
	CERTBOT_SETUP_CERTS_PRIMARY=()
	CERTBOT_SETUP_CERTS_ALT=()
	CERTBOT_SETUP_CERTS_EMAIL=()
	CERTBOT_SETUP_CERTS_STAGING=()
}

certbot_get_certs ()
{
	local EXPECTED_ARGS=1
	if [ $# -ne $EXPECTED_ARGS ]; then
		echo "Usage: $CERTBOT_SCRIPT_CMD [certbot_get_certs] {path to certificate setup directory}" >&2
		return 1
	fi
	local CERTS_DIR="$1"

	local REGEX_MATCH_COMMENTED="^\s*#"
	# Any line starting with '#'
	local REGEX_MATCH_ENTRY_GROUPS="^\s*(.*)\s*=\s*?(.*)?\s*$"
	# Parameter key=value

	certbot_get_certs_reset

	# Check for a valid path
	if [ ! -d "$CERTS_DIR" ]; then
		echo "[certbot_get_certs] Certbot setup path $CERTS_DIR does not exist" >&2
		return 1
	fi

	# Fetch all directories in this path
	for CERT_UNTESTED_PATH in ${CERTS_DIR}/*; do
		# Check if directory
		if [ ! -d "${CERT_UNTESTED_PATH}" ]; then
			continue
		fi
		# Path to domain configuration
		local CERT_DOMAINS_FILE="$CERT_UNTESTED_PATH/$CERTBOT_SETUP_DOMAIN_FILE"
		# Check if file exists
		if [ ! -f "$CERT_DOMAINS_FILE" ]; then
			# No configuration file found
			echo "$CERTBOT_LOG_PREFIX [certbot_get_certs] Ignoring directory '$CERT_UNTESTED_PATH' with no '$CERTBOT_SETUP_DOMAIN_FILE'"
			continue
		fi
		# Configuration file found, try to load

		local DOMAIN_CERT_NAME="$(basename $CERT_UNTESTED_PATH)"

		# Primary domain
		local DOMAIN_PRIMARY=""
		# Alternative domains, space separated
		local DOMAINS_ALTERNATIVE=""
		# Email for registering
		local DOMAIN_EMAIL=""
		# Testing/staging mode active
		local DOMAIN_STAGING=false

		while read conf_line; do
			if [[ -z "${conf_line// /}" ]]; then
				# Empty string
				# See https://stackoverflow.com/questions/13509508/check-if-string-is-neither-empty-nor-space-in-shell-script
				continue
			fi
			if [[ $conf_line =~ $REGEX_MATCH_COMMENTED ]]; then
				# Comment, skip
				continue
			fi
			if [[ $conf_line =~ $REGEX_MATCH_ENTRY_GROUPS ]]; then
				# Contains equal sign, check parameters
				# testing=test
				# Group 1.  testing
				# Group 2.  test
				# See https://gist.github.com/justjanne/c7b9bfd2780c4267ba4f1f870994917a
				local PARAM="${BASH_REMATCH[1]}"
				# Lowercase parameter (^^ is uppercase)
				PARAM="${PARAM,,}"
				local VALUE="${BASH_REMATCH[2]}"

				case "$PARAM" in
					"$CERTBOT_SETUP_KEY_PRIMARY" )
						DOMAIN_PRIMARY="$VALUE"
						;;
					"$CERTBOT_SETUP_KEY_ALT" )
						DOMAINS_ALTERNATIVE="$VALUE"
						;;
					"$CERTBOT_SETUP_KEY_EMAIL" )
						DOMAIN_EMAIL="$VALUE"
						;;
					"$CERTBOT_SETUP_KEY_STAGING" )
						# Parse true/false, lowercasing it
						# See https://stackoverflow.com/questions/2264428/how-to-convert-a-string-to-lower-case-in-bash
						case "${VALUE,,}" in
							"true" )
								DOMAIN_STAGING=true
								;;
							"false" )
								DOMAIN_STAGING=false
								;;
							* )
								echo "$CERTBOT_LOG_PREFIX [certbot_get_certs] Unknown value '$VALUE' for key '$PARAM' in '$CERT_DOMAINS_FILE'" >&2
								echo "Expected: true, false" >&2
								return 1
								;;
						esac
						;;
					* )
						echo "$CERTBOT_LOG_PREFIX [certbot_get_certs] Unknown key '$PARAM' in '$CERT_DOMAINS_FILE'" >&2
						echo "Expected one of: [$CERTBOT_SETUP_KEY_PRIMARY, $CERTBOT_SETUP_KEY_ALT, $CERTBOT_SETUP_KEY_EMAIL, $CERTBOT_SETUP_KEY_STAGING]" >&2
						return 1
						;;
				esac
			else
				# Something unexpected
				echo "$CERTBOT_LOG_PREFIX [certbot_get_certs] Unknown line '$conf_line' in '$CERT_DOMAINS_FILE'" >&2
				echo "Expected: [$CERTBOT_SETUP_KEY_PRIMARY, $CERTBOT_SETUP_KEY_ALT, $CERTBOT_SETUP_KEY_EMAIL, $CERTBOT_SETUP_KEY_STAGING]=<value>" >&2
				return 1
			fi
			# End parameter handling
		done < "$CERT_DOMAINS_FILE"

		# File loaded

		# Validate parameters
		# Domain
		if [ -z "$DOMAIN_PRIMARY" ]; then
			echo "Key '$CERTBOT_SETUP_KEY_PRIMARY' needs set to a domain name in '$CERT_DOMAINS_FILE'" >&2
			echo "E.g.: $CERTBOT_SETUP_KEY_PRIMARY=example.com" >&2
			return 1
		fi
		# DOMAINS_ALTERNATIVE can be empty
		# Email
		if [ -z "$DOMAIN_EMAIL" ]; then
			echo "Key '$CERTBOT_SETUP_KEY_EMAIL' needs set to an email address in '$CERT_DOMAINS_FILE'" >&2
			echo "E.g.: $CERTBOT_SETUP_KEY_EMAIL=you@example.com" >&2
			return 1
		fi

		# Append domain information to array
		# (Assuming it's not possible for two directories with same name)
		CERTBOT_SETUP_CERT_NAMES+=("$DOMAIN_CERT_NAME")
		CERTBOT_SETUP_CERTS_PRIMARY["$DOMAIN_CERT_NAME"]="$DOMAIN_PRIMARY"
		CERTBOT_SETUP_CERTS_ALT[$DOMAIN_CERT_NAME]="$DOMAINS_ALTERNATIVE"
		CERTBOT_SETUP_CERTS_EMAIL[$DOMAIN_CERT_NAME]="$DOMAIN_EMAIL"
		CERTBOT_SETUP_CERTS_STAGING[$DOMAIN_CERT_NAME]="$DOMAIN_STAGING"

		# Loaded!  On to the next directory...
	done

	# Loading done!
	CERTBOT_SETUP_CERTS_LOADED=true
}

certbot_sort_cert_names ()
{
	local EXPECTED_ARGS=1
	if [ $# -ne $EXPECTED_ARGS ]; then
		echo "Usage: $CERTBOT_SCRIPT_CMD [certbot_sort_cert_names] {certificate names}" >&2
		return 1
	fi
	local CERT_NAMES="$1"

	# Sort and split
	local CERT_NAMES_SPLIT=$(certbot_sortsplit_cert_names "$CERT_NAMES")

	# Combine newline split back to comma-separated
	# (Print result instead of capturing in a variable)
	echo "${CERT_NAMES_SPLIT//$'\n'/,}" | LC_ALL=C sort
}

certbot_sortsplit_cert_names ()
{
	local EXPECTED_ARGS=1
	if [ $# -ne $EXPECTED_ARGS ]; then
		echo "Usage: $CERTBOT_SCRIPT_CMD [certbot_sortsplit_cert_names] {certificate names}" >&2
		return 1
	fi
	local CERT_NAMES="$1"

	# Split comma to newline, sort
	# (Print result instead of capturing in a variable)
	echo "${CERT_NAMES//,/$'\n'}" | LC_ALL=C sort
}

# All
# --------

certbot_deploy_all ()
{
	local EXPECTED_ARGS=1
	if [ $# -ne $EXPECTED_ARGS ]; then
		echo "Usage: $CERTBOT_SCRIPT_CMD [certbot_deploy_all] {path to certificate setup directory}" >&2
		return 1
	fi
	local CERTS_DIR="$1"

	local CERTBOT_LOG_PREFIX="$CERTBOT_LOG_PREFIX [deploy-all]"

	if [[ "$CERTBOT_SETUP_CERTS_LOADED" != "true" ]]; then
		# Ensure certs are loaded
		certbot_get_certs "$CERTBOT_SETUP_PATH" || return 1
	fi

	# If nothing to configure, all good
	if (( ${#CERTBOT_SETUP_CERT_NAMES[@]} <= 0 )); then
		echo "$CERTBOT_LOG_PREFIX No certificate configuration specified in '$CERTS_DIR'"
		return 0
	fi

	# For each, run any deploy hooks
	# See https://stackoverflow.com/questions/3112687/how-to-iterate-over-associative-arrays-in-bash
	# Exchanged for simpler method of storing all cert names
	for CERT_NAME in "${CERTBOT_SETUP_CERT_NAMES[@]}"; do
		# Deploy each certificate
		certbot_deploy_cert "$CERTS_DIR" "$CERT_NAME" || return 1
	done
}

certbot_renew_all ()
{
	# Before, had to use 'certonly' and '--keep-until-expiring'
	# https://community.letsencrypt.org/t/help-us-test-renewal-with-letsencrypt-renew/10562
	sudo "$CERTBOT_TOOL" renew --quiet $CERTBOT_TOOL_OPTIONS_RENEW || return 1
	# > To force an update, use --force-renewal
	# > For testing, use --dry-run
}

certbot_is_all_configured ()
{
	local EXPECTED_ARGS=1
	if [ $# -ne $EXPECTED_ARGS ]; then
		echo "Usage: $CERTBOT_SCRIPT_CMD [certbot_is_all_configured] {path to certificate setup directory}" >&2
		return 1
	fi
	local CERTS_DIR="$1"

	if [[ "$CERTBOT_SETUP_CERTS_LOADED" != "true" ]]; then
		# Ensure certs are loaded
		certbot_get_certs "$CERTBOT_SETUP_PATH" || return 1
	fi

	# If nothing to configure, all good
	if (( ${#CERTBOT_SETUP_CERT_NAMES[@]} <= 0 )); then
		return 0
	fi

	# For each, check if configured
	for CERT_NAME in "${CERTBOT_SETUP_CERT_NAMES[@]}"; do
		# Check if certificate configured
		certbot_is_configured "$CERTS_DIR" "$CERT_NAME" || return 1
	done
}

certbot_configure_all ()
{
	local EXPECTED_ARGS=1
	if [ $# -ne $EXPECTED_ARGS ]; then
		echo "Usage: $CERTBOT_SCRIPT_CMD [certbot_configure_all] {path to certificate setup directory}" >&2
		return 1
	fi
	local CERTS_DIR="$1"

	local CERTBOT_LOG_PREFIX="$CERTBOT_LOG_PREFIX [configure-all]"

	if [[ "$CERTBOT_SETUP_CERTS_LOADED" != "true" ]]; then
		# Ensure certs are loaded
		certbot_get_certs "$CERTBOT_SETUP_PATH" || return 1
	fi

	# If nothing to configure, all good
	if (( ${#CERTBOT_SETUP_CERT_NAMES[@]} <= 0 )); then
		echo "$CERTBOT_LOG_PREFIX No certificate configuration specified in '$CERTS_DIR'"
		return 0
	fi

	# For each, run configuration
	for CERT_NAME in "${CERTBOT_SETUP_CERT_NAMES[@]}"; do
		certbot_configure_cert "$CERTS_DIR" "$CERT_NAME" || return 1
	done
}

# Individual
# --------

certbot_deploy_cert ()
{
	local EXPECTED_ARGS=2
	if [ $# -ne $EXPECTED_ARGS ]; then
		echo "Usage: $CERTBOT_SCRIPT_CMD [certbot_deploy_cert] {path to certificate setup directory} {certificate name}" >&2
		return 1
	fi
	local CERTS_DIR="$1"
	local CERT_NAME="$2"

	local CERTBOT_LOG_PREFIX="$CERTBOT_LOG_PREFIX [deploy: $CERT_NAME]"

	if [[ "$CERTBOT_SETUP_CERTS_LOADED" != "true" ]]; then
		# Ensure certs are loaded
		certbot_get_certs "$CERTBOT_SETUP_PATH" || return 1
	fi


	# Check if cert directory exists
	local CERT_NAMED_DIR="$CERTS_DIR/$CERT_NAME"
	if [ ! -d "$CERT_NAMED_DIR" ]; then
		echo "$CERTBOT_LOG_PREFIX Certificate '$CERT_NAME' does not exist in '$CERTS_DIR'" >&2
		return 1
	fi

	# Check for any deploy hooks
	local CERT_HOOKS_DIR="$CERT_NAMED_DIR/$CERTBOT_SETUP_HOOKS_DIR_NAME"
	if [ ! -d "$CERT_HOOKS_DIR" ]; then
		# No hooks, skip
		echo "$CERTBOT_LOG_PREFIX Skipping deploy hooks for '$CERT_NAME', '$CERT_HOOKS_DIR' doesn't exist"
		return 0
	fi

	# Check for live certificate
	local CERT_LIVE_DIR="$CERTBOT_PATH_KEYS/$CERT_NAME"
	if [ ! -d "$CERT_LIVE_DIR" ]; then
		# Certificate directory doesn't exist, error
		echo "$CERTBOT_LOG_PREFIX Unable to run deploy hooks for '$CERT_NAME', '$CERT_LIVE_DIR' doesn't exist"
		return 1
	fi

	# Call "run-parts"
	# For debugging, add "--verbose" to run-parts
	echo "$CERTBOT_LOG_PREFIX Processing deploy hooks"
	# Set environment for command
	CERTBOT_SETUP_RENEWED_LINEAGE="$CERT_LIVE_DIR" \
		run-parts --lsbsysinit --report "$CERT_HOOKS_DIR"
}

certbot_is_configured ()
{
	local EXPECTED_ARGS=2
	if [ $# -ne $EXPECTED_ARGS ]; then
		echo "Usage: $CERTBOT_SCRIPT_CMD [certbot_is_configured] {path to certificate setup directory} {certificate name}" >&2
		return 1
	fi
	local CERTS_DIR="$1"
	local CERT_NAME="$2"

	if [[ "$CERTBOT_SETUP_CERTS_LOADED" != "true" ]]; then
		# Ensure certs are loaded
		certbot_get_certs "$CERTBOT_SETUP_PATH" || return 1
	fi

	local CERTBOT_LOG_PREFIX="$CERTBOT_LOG_PREFIX [check: $CERT_NAME]"

	# Check if cert directory exists
	local CERT_NAMED_DIR="$CERTS_DIR/$CERT_NAME"
	if [ ! -d "$CERT_NAMED_DIR" ]; then
		echo "$CERTBOT_LOG_PREFIX Certificate '$CERT_NAME' does not exist in '$CERTS_DIR'" >&2
		return 1
	fi

	# Check for live certificate
	local CERT_LIVE_DIR="$CERTBOT_PATH_KEYS/$CERT_NAME"
	if [ ! -d "$CERT_LIVE_DIR" ]; then
		# Certificate directory doesn't exist, not set up
		return 1
	fi

	# Using the full certificate...
	local CERT_FULLCHAIN="$CERT_LIVE_DIR/$CERTBOT_NAME_FULLCHAIN"

	# Check if common name matches
	# > Load from file
	local CERT_OPENSSL_DATA_COMMON_NAME=$(sudo openssl x509 -noout -subject -nameopt multiline -in "$CERT_FULLCHAIN" | grep "commonName" | cut --delimiter="=" --field=2 | xargs)
	# Coerce openssl into printing...
	# subject=
	#    commonName                = example.com
	# Select "commonName" line
	# Cut after "=" to " example.com"
	# Trim whitespace with xargs

	# > Fetch from configuration
	local CERT_CONF_DATA_COMMON_NAME="${CERTBOT_SETUP_CERTS_PRIMARY["$CERT_NAME"]}"

	# > Compare
	if [[ "$CERT_OPENSSL_DATA_COMMON_NAME" != "$CERT_CONF_DATA_COMMON_NAME" ]]; then
		# Certificate common name doesn't match
		#echo "$CERTBOT_LOG_PREFIX Certificate common name doesn't match"
		#echo "  $CERT_OPENSSL_DATA_COMMON_NAME != $CERT_CONF_DATA_COMMON_NAME"
		return 1
	fi

	# Check certificate subjectAltNames
	# > Load from file
	local REGEX_MATCH_DNS_GROUPS="DNS:([\w.-]*)"
	# Group matching from https://regex101.com/
	#local REGEX_MATCH_DNS_GROUPS="DNS:([\w.-]*),?\s"
	# Escape periods for sed
	local CERT_CONF_DATA_COMMON_NAME_ESCAPED="${CERT_CONF_DATA_COMMON_NAME//./\\.}"
	# Find data
	local CERT_OPENSSL_DATA_SAN=$(sudo openssl x509 -in "$CERT_FULLCHAIN" -noout -text -certopt no_header,no_version,no_serial,no_signame,no_validity,no_issuer,no_pubkey,no_sigdump,no_aux | grep -o -P "$REGEX_MATCH_DNS_GROUPS" | sed -e "/DNS:$CERT_CONF_DATA_COMMON_NAME_ESCAPED/d" -e "s/DNS://g" | LC_ALL=C sort)
	# Print OpenSSL data in text (DNS:a.example.com, DNS:b.example.com, DNS:example.com)
	# grep for matches to DNS:[...]
	# Remove the primary domain if it exists, remove the "DNS:" prefix
	# Sort
	#
	# End result: newline-separated domains

	# > Fetch from configuration
	local CERT_CONF_DATA_SAN="${CERTBOT_SETUP_CERTS_ALT["$CERT_NAME"]}"
	# Sort and split
	CERT_CONF_DATA_SAN="$(certbot_sortsplit_cert_names "$CERT_CONF_DATA_SAN")"

	# > Compare
	if [[ "$CERT_OPENSSL_DATA_SAN" != "$CERT_CONF_DATA_SAN" ]]; then
		# Certificate alternative names don't match
		#echo "$CERTBOT_LOG_PREFIX Certificate alternative names don't match"
		#echo "  $CERT_OPENSSL_DATA_SAN != $CERT_CONF_DATA_SAN"
		return 1
	fi
}

certbot_configure_cert ()
{
	local EXPECTED_ARGS=2
	if [ $# -ne $EXPECTED_ARGS ]; then
		echo "Usage: $CERTBOT_SCRIPT_CMD [certbot_configure_cert] {path to certificate setup directory} {certificate name}" >&2
		return 1
	fi
	local CERTS_DIR="$1"
	local CERT_NAME="$2"

	local CERTBOT_LOG_PREFIX="$CERTBOT_LOG_PREFIX [configure: $CERT_NAME]"

	if [[ "$CERTBOT_SETUP_CERTS_LOADED" != "true" ]]; then
		# Ensure certs are loaded
		certbot_get_certs "$CERTBOT_SETUP_PATH" || return 1
	fi

	if certbot_is_configured "$CERTS_DIR" "$CERT_NAME"; then
		# Already configured, nothing to do
		return 0
	fi

	# Check for live certificate
	local CERT_LIVE_DIR="$CERTBOT_PATH_KEYS/$CERT_NAME"
	if [ -d "$CERT_LIVE_DIR" ]; then
		# Certificate directory exists, clean up
		if [ -f "$CERT_LIVE_DIR/is_dummy_certs" ]; then
			# Dummy certificate, just remove
			echo "$CERTBOT_LOG_PREFIX Deleting existing dummy certificate"
			sudo rm --recursive "$CERT_LIVE_DIR"
		else
			# Certificate from certbot, delete
			echo "$CERTBOT_LOG_PREFIX Deleting existing mismatching certificate"
			sudo "$CERTBOT_TOOL" delete --cert-name "$CERT_NAME" $CERTBOT_TOOL_OPTIONS_DELETE || return 1
		fi
	fi

	# Fetch from configuration
	# Certificate commonName
	local CERT_CONF_DATA_COMMON_NAME="${CERTBOT_SETUP_CERTS_PRIMARY["$CERT_NAME"]}"
	# Certificate subjectAlternativeName
	local CERT_CONF_DATA_SAN="${CERTBOT_SETUP_CERTS_ALT["$CERT_NAME"]}"
	# > Sort (don't split)
	CERT_CONF_DATA_SAN="$(certbot_sort_cert_names "$CERT_CONF_DATA_SAN")"
	# Let's Encrypt account email
	local CERT_CONF_DATA_EMAIL="${CERTBOT_SETUP_CERTS_EMAIL["$CERT_NAME"]}"
	# Staging mode
	local CERT_CONF_DATA_STAGING="${CERTBOT_SETUP_CERTS_STAGING["$CERT_NAME"]}"

	echo "$CERTBOT_LOG_PREFIX Requesting certificate '$CERT_NAME'"
	echo "$CERTBOT_LOG_PREFIX   $CERTBOT_SETUP_KEY_PRIMARY=$CERT_CONF_DATA_COMMON_NAME"
	if [ -n "$CERT_CONF_DATA_SAN" ]; then
		echo "$CERTBOT_LOG_PREFIX   $CERTBOT_SETUP_KEY_ALT=$CERT_CONF_DATA_SAN"
	else
		echo "$CERTBOT_LOG_PREFIX   # No alternative domains specified"
	fi
	echo "$CERTBOT_LOG_PREFIX   $CERTBOT_SETUP_KEY_EMAIL=$CERT_CONF_DATA_EMAIL"
	echo "$CERTBOT_LOG_PREFIX   $CERTBOT_SETUP_KEY_STAGING=$CERT_CONF_DATA_STAGING"

	# Extra command line arguments
	local CERTBOT_EXTRA_FLAGS=""

	if [[ "$CERT_CONF_DATA_STAGING" == "true" ]]; then
		# Use the staging server to get test certificates
		CERTBOT_EXTRA_FLAGS="$CERTBOT_EXTRA_FLAGS --test-cert"
	fi

	# Process the common name and alternative names
	local CERTBOT_EXTRA_DOMAINS=""
	if [ -n "$CERT_CONF_DATA_SAN" ]; then
		CERTBOT_EXTRA_DOMAINS="--domains $CERT_CONF_DATA_SAN"
	fi

	# Request certificate
	sudo "$CERTBOT_TOOL" certonly --cert-name "$CERT_NAME" --email "$CERT_CONF_DATA_EMAIL" --domains "$CERT_CONF_DATA_COMMON_NAME" $CERTBOT_EXTRA_DOMAINS $CERTBOT_TOOL_OPTIONS $CERTBOT_EXTRA_FLAGS || return 1
	# The first "--domains" is the base folder for certificates, and the primary key.
	# Secondary "--domains" will be added as subjectAltName entries.
	# Domains can be comma-separated, e.g. "a.example.com,b.example.com"
}

#echo "### TEST certbot_get_certs ###"
#CERTBOT_SETUP_PATH="/tmp/cert"
#if [[ "$CERTBOT_SETUP_CERTS_LOADED" != "true" ]]; then
#	# Ensure certs are loaded
#	certbot_get_certs "$CERTBOT_SETUP_PATH" || exit 1
#fi
#
#echo "### TEST certbot_deploy_all ###"
#certbot_deploy_all "$CERTBOT_SETUP_PATH"
#
#echo "### TEST certbot_is_all_configured ###"
#if certbot_is_all_configured "$CERTBOT_SETUP_PATH"; then
#	echo "Configured"
#else
#	echo "Not configured"
#fi
#
#echo "### TEST certbot_configure_all ###"
#certbot_configure_all "$CERTBOT_SETUP_PATH"
#
#echo "### DEBUGGING TEST ###"
#exit 0

certbot_print_usage ()
{
	echo "Usage: `basename $0` {path to certificate setup directory} {command: check, configure, renew, $CERTBOT_HOOK_DEPLOY_CMD}" >&2
}

# Load basic configuration
EXPECTED_ARGS=2
if [ $# -ge $EXPECTED_ARGS ]; then
	CERTBOT_SETUP_PATH="$1"
	if [ ! -d "$CERTBOT_SETUP_PATH" ]; then
		echo "Certbot setup path '$CERTBOT_SETUP_PATH' does not exist" >&2
		exit 1
	fi
else
	certbot_print_usage
	exit 1
fi

# Get certificates
certbot_get_certs "$CERTBOT_SETUP_PATH" || exit 1

EXPECTED_ARGS=2
if [ $# -ge $EXPECTED_ARGS ]; then
	case $2 in
		"check" )
			certbot_is_all_configured "$CERTBOT_SETUP_PATH"
			# Return the status code (redundant with Bash strict mode)
			exit $?
			;;
		"configure" )
			certbot_configure_all "$CERTBOT_SETUP_PATH" || exit 1
			certbot_deploy_all "$CERTBOT_SETUP_PATH" || exit 1
			;;
		"renew" )
			certbot_renew_all "$CERTBOT_SETUP_PATH" || exit 1
			# Reloading is handled by deploy hooks
			;;
		"$CERTBOT_HOOK_DEPLOY_CMD" )
			# Called by deploy hooks
			EXPECTED_ARGS=3 # 2 + 1
			if [ $# -eq $EXPECTED_ARGS ]; then
				CERTBOT_HOOK_DEPLOY_RENEWED_LINEAGE="$3"
				# Called by deploy hooks
				certbot_deploy_cert "$CERTBOT_SETUP_PATH" "$CERTBOT_HOOK_DEPLOY_RENEWED_LINEAGE"
				# Return the status code (redundant with Bash strict mode)
				exit $?
			else
				echo "Usage: `basename $0` {path to certificate setup directory} $CERTBOT_HOOK_DEPLOY_CMD {certificate name}" >&2
				exit 1
			fi
			;;
		* )
			certbot_print_usage
			exit 1
			;;
	esac
else
	certbot_print_usage
	exit 1
fi
