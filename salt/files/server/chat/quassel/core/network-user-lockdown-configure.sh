#!/bin/bash
# See http://redsymbol.net/articles/unofficial-bash-strict-mode/
set -euo pipefail

# Load local session config
_LOCAL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

NET_LOCKDOWN_CONFIG_FILE="$_LOCAL_DIR/network-user-lockdown-vars.sh"

# Configuration values
NET_LOCKDOWN_LIMITED_USER=""
NET_LOCKDOWN_ALLOWED_HOSTS=()
NET_LOCKDOWN_ALLOWED_PORTS=()

# iptables custom chain name
NET_LOCKDOWN_IPCHAIN="net-usr-lockdown-out"
NET_LOCKDOWN_IPCHAIN_STAGING="$NET_LOCKDOWN_IPCHAIN-stage"

NET_LOG_PREFIX="[net-lockdown]"

# If true, changes won't be made to the system, only printed to console
NET_LOCKDOWN_DRYRUN=false

# If true, when IPv4 DNS is not reachable and IPv6 is, DNS (port 53) will be
# locked to only allow using the system IPv6 resolver.
# If false, when IPv4 DNS is not reachable, DNS (port 53) will not be limited
# in any way.
NET_LOCKDOWN_DNS_IPV6_SUFFICIENT=false

# Seconds to wait for finding DNS resolver, *# of retries, *2 for IPv4 + IPv6
NET_LOCKDOWN_DNS_TIMEOUT=2
# How many retries for finding DNS resolver, *2 for IPv4 + IPv6
NET_LOCKDOWN_DNS_RETRIES=1

NET_LOCKDOWN_DNS_DIG_OPTS="+time=$NET_LOCKDOWN_DNS_TIMEOUT +tries=$NET_LOCKDOWN_DNS_RETRIES"

ipt_cmd() {
	local EXPECTED_ARGS=1
	if [ $# -lt $EXPECTED_ARGS ]; then
		echo "Usage: `basename $0` [ipt_cmd] {iptables and ip6tables command}" >&2
		return 1
	fi
	# Capture return value
	set +e
	if [ "$NET_LOCKDOWN_DRYRUN" = true ]; then
		echo "\$ iptables --wait $*"
	else
		iptables --wait $*
	fi
	local RETVAL=$?
	set -e
	return $RETVAL
}

ip6t_cmd() {
	local EXPECTED_ARGS=1
	if [ $# -lt $EXPECTED_ARGS ]; then
		echo "Usage: `basename $0` [ipt_cmd] {iptables and ip6tables command}" >&2
		return 1
	fi
	# Capture return value
	set +e
	if [ "$NET_LOCKDOWN_DRYRUN" = true ]; then
		echo "\$ ip6tables --wait $*"
	else
		ip6tables --wait $*
	fi
	local RETVAL=$?
	set -e
	return $RETVAL
}

# Join elements of an array
# See https://stackoverflow.com/questions/1527049/how-can-i-join-elements-of-an-array-in-bash
lockdown_join_by() {
	local EXPECTED_ARGS=2
	if [ $# -lt $EXPECTED_ARGS ]; then
		echo "Usage: `basename $0` [join_by] {separator} {variable array}" >&2
		return 1
	fi

	local IFS="$1"
	shift
	echo "$*"
}

lockdown_ipt_has_chain() {
	local EXPECTED_ARGS=1
	if [ $# -ne $EXPECTED_ARGS ]; then
		echo "Usage: `basename $0` [lockdown_ipt_has_chain] {iptables chain name}" >&2
		return 1
	fi

	local IPCHAIN="$1"

	if [ "$NET_LOCKDOWN_DRYRUN" = true ]; then
		# Assume no chain in dry run
		return 1
	fi

	if ipt_cmd --wait --list "$IPCHAIN" &>/dev/null; then
		return 0
	else
		return 1
	fi
}

lockdown_ip6t_has_chain() {
	local EXPECTED_ARGS=1
	if [ $# -ne $EXPECTED_ARGS ]; then
		echo "Usage: `basename $0` [lockdown_ip6t_has_chain] {ip6tables chain name}" >&2
		return 1
	fi

	local IPCHAIN="$1"
	
	if [ "$NET_LOCKDOWN_DRYRUN" = true ]; then
		# Assume no chain in dry run
		return 1
	fi

	if ip6t_cmd --wait --list "$IPCHAIN" &>/dev/null; then
		return 0
	else
		return 1
	fi
}

lockdown_ipt_purge_chain() {
	local EXPECTED_ARGS=1
	if [ $# -ne $EXPECTED_ARGS ]; then
		echo "Usage: `basename $0` [lockdown_ipt_purge_chain] {iptables chain name}" >&2
		return 1
	fi

	local IPCHAIN="$1"

	if lockdown_ipt_has_chain "$IPCHAIN"; then
		# Flush chain
		ipt_cmd --flush "$IPCHAIN" || return 1
		# Delete chain
		ipt_cmd --delete-chain "$IPCHAIN" || return 1
	fi
}

lockdown_ip6t_purge_chain() {
	local EXPECTED_ARGS=1
	if [ $# -ne $EXPECTED_ARGS ]; then
		echo "Usage: `basename $0` [lockdown_ip6t_purge_chain] {iptables chain name}" >&2
		return 1
	fi

	local IPCHAIN="$1"

	if lockdown_ip6t_has_chain "$IPCHAIN"; then
		# Flush chain
		ip6t_cmd --flush "$IPCHAIN" || return 1
		# Delete chain
		ip6t_cmd --delete-chain "$IPCHAIN" || return 1
		return 0
	else
		# Nothing to do
		return 0
	fi
}

lockdown_ipt_has_user_out() {
	local EXPECTED_ARGS=2
	if [ $# -ne $EXPECTED_ARGS ]; then
		echo "Usage: `basename $0` [lockdown_ipt_has_user_out] {iptables chain name} {username}" >&2
		return 1
	fi

	local IPCHAIN="$1"
	local USER="$2"

	if [ "$NET_LOCKDOWN_DRYRUN" = true ]; then
		# Assume no output in dry run
		return 1
	fi
	
	if ipt_cmd --check OUTPUT --match owner --uid-owner "$USER" \
		--match comment --comment "match_restricted_user" \
		--jump "$IPCHAIN" &>/dev/null; then
		return 0
	else
		return 1
	fi
}

lockdown_ip6t_has_user_out() {
	local EXPECTED_ARGS=2
	if [ $# -ne $EXPECTED_ARGS ]; then
		echo "Usage: `basename $0` [lockdown_ip6t_has_user_out] {iptables chain name} {username}" >&2
		return 1
	fi

	local IPCHAIN="$1"
	local USER="$2"

	if [ "$NET_LOCKDOWN_DRYRUN" = true ]; then
		# Assume no output in dry run
		return 1
	fi
	
	if ip6t_cmd --check OUTPUT --match owner --uid-owner "$USER" \
		--match comment --comment "match_restricted_user" \
		--jump "$IPCHAIN" &>/dev/null; then
		return 0
	else
		return 1
	fi
}

lockdown_ipt_purge_user_out() {
	local EXPECTED_ARGS=2
	if [ $# -ne $EXPECTED_ARGS ]; then
		echo "Usage: `basename $0` [lockdown_ipt_purge_user_out] {iptables chain name} {username}" >&2
		return 1
	fi

	local IPCHAIN="$1"
	local USER="$2"

	if lockdown_ipt_has_user_out "$IPCHAIN" "$USER"; then
		# Delete the rule
		ipt_cmd --delete OUTPUT --match owner --uid-owner "$USER" \
			--match comment --comment "match_restricted_user" \
			--jump "$IPCHAIN" || return 1
	fi
}

lockdown_ip6t_purge_user_out() {
	local EXPECTED_ARGS=2
	if [ $# -ne $EXPECTED_ARGS ]; then
		echo "Usage: `basename $0` [lockdown_ip6t_purge_user_out] {iptables chain name} {username}" >&2
		return 1
	fi

	local IPCHAIN="$1"
	local USER="$2"

	if lockdown_ip6t_has_user_out "$IPCHAIN" "$USER"; then
		# Delete the rule
		ip6t_cmd --delete OUTPUT --match owner --uid-owner "$USER" \
			--match comment --comment "match_restricted_user" \
			--jump "$IPCHAIN" || return 1
	fi
}

lockdown_resolve() {
	local EXPECTED_ARGS=2
	if [ $# -ne $EXPECTED_ARGS ]; then
		echo "Usage: `basename $0` [lockdown_resolve] {ipv4/ipv6} {domain name or IP address}" >&2
		return 1
	fi

	local CHECK_IPV6=false
	case "$1" in
		"ipv4" | "v4" | "4" )
			CHECK_IPV6=false
			;;
		"ipv6" | "v6" | "6" )
			CHECK_IPV6=true
			;;
		* )
			echo "Usage: `basename $0` [lockdown_resolve] {ipv4/ipv6} {domain name or IP address}" >&2
			return 1
			;;
	esac

	local HOST="$2"


	# When running with root, drop privileges for network operations
	local DROP_ROOT_CMD="sudo --user=nobody"
	if [ "$NET_LOCKDOWN_DRYRUN" = true ]; then
		# Don't require sudo when not making changes
		DROP_ROOT_CMD=""
	fi

	if [ "$CHECK_IPV6" = true ]; then
		$DROP_ROOT_CMD getent ahostsv6 "$HOST" | cut --fields=1 --delimiter=" " | sort --unique
	else
		$DROP_ROOT_CMD getent ahostsv4 "$HOST" | cut --fields=1 --delimiter=" " | sort --unique
	fi
}

lockdown_get_dns_v4_server() {
	local INVALID_DOMAIN="example.invalid"

	local DNS_SERVER_RESULT=""

	# Do it in the C locale
	# Take a maximum of 2 seconds
	DNS_SERVER_RESULT=$(LC_ALL=C dig -4 "$INVALID_DOMAIN" $NET_LOCKDOWN_DNS_DIG_OPTS 2>/dev/null | grep "SERVER:" | sed "s/^;; SERVER: \(.*\)#.*$/\1/" || true)
	# Add "@nope.invalid" after INVALID_DOMAIN to test fail with
	# an IPv4 DNS server auto-assigned

	# Make sure it's valid
	if lockdown_resolve "ipv4" "$DNS_SERVER_RESULT" >/dev/null ; then
		# Valid IPv4 result
		echo "$DNS_SERVER_RESULT"
		return 0
	else
		return 1
	fi
}

lockdown_get_dns_v6_server() {
	local INVALID_DOMAIN="example.invalid"

	local DNS_SERVER_RESULT=""

	# Do it in the C locale
	# Take a maximum of 2 seconds
	DNS_SERVER_RESULT=$(LC_ALL=C dig -6 "$INVALID_DOMAIN" $NET_LOCKDOWN_DNS_DIG_OPTS 2>/dev/null | grep "SERVER:" | sed "s/^;; SERVER: \(.*\)#.*$/\1/" || true)
	# Add "@2606:4700:4700::1111" after INVALID_DOMAIN to test pass without
	# an IPv6 DNS server auto-assigned

	# Make sure it's valid
	if lockdown_resolve "ipv6" "$DNS_SERVER_RESULT" >/dev/null ; then
		# Valid IPv6 result
		echo "$DNS_SERVER_RESULT"
		return 0
	else
		return 1
	fi
}

lockdown_has_root() {
	if [ "$NET_LOCKDOWN_DRYRUN" = true ]; then
		return 0
	else
		if [ "$(whoami)" != "root" ]; then
			return 1
		else
			return 0
		fi
	fi
}

lockdown_load_config() {
	if [ ! -f "$NET_LOCKDOWN_CONFIG_FILE" ]; then
		echo "Quassel setup file '$NET_LOCKDOWN_CONFIG_FILE' does not exist" >&2
		return 1
	fi
	# Load blank defaults
	NET_LOCKDOWN_LIMITED_USER=""
	NET_LOCKDOWN_ALLOWED_HOSTS=()
	NET_LOCKDOWN_ALLOWED_PORTS=()
	# Load setup file
	source "$NET_LOCKDOWN_CONFIG_FILE"
	# Validate variables
	if [ -z "$NET_LOCKDOWN_LIMITED_USER" ]; then
		echo "NET_LOCKDOWN_LIMITED_USER not found in setup file '$NET_LOCKDOWN_CONFIG_FILE'" >&2
		return 1
	fi
	# See https://stackoverflow.com/questions/14810684/check-whether-a-user-exists
	local NET_USER_EXISTS=$(id -u "$NET_LOCKDOWN_LIMITED_USER" > /dev/null 2>&1; echo $?) 
	if [ $NET_USER_EXISTS -ne 0 ]; then
		echo "NET_LOCKDOWN_LIMITED_USER '$NET_LOCKDOWN_LIMITED_USER' does not exist, set by setup file '$NET_LOCKDOWN_CONFIG_FILE'" >&2
		return 1
	fi
	if [ -z "$NET_LOCKDOWN_ALLOWED_HOSTS" ]; then
		echo "NET_LOCKDOWN_ALLOWED_HOSTS not found in setup file '$NET_LOCKDOWN_CONFIG_FILE'" >&2
		return 1
	fi
	if [ ${#NET_LOCKDOWN_ALLOWED_HOSTS[@]} -eq 0 ]; then
		echo "NET_LOCKDOWN_ALLOWED_HOSTS does not specify any allowed hosts in setup file '$NET_LOCKDOWN_CONFIG_FILE'" >&2
		return 1
	fi
	if [ -z "$NET_LOCKDOWN_ALLOWED_PORTS" ]; then
		echo "NET_LOCKDOWN_ALLOWED_PORTS not found in setup file '$NET_LOCKDOWN_CONFIG_FILE'" >&2
		return 1
	fi
	if [ ${#NET_LOCKDOWN_ALLOWED_PORTS[@]} -eq 0 ]; then
		echo "NET_LOCKDOWN_ALLOWED_PORTS does not specify any allowed hosts in setup file '$NET_LOCKDOWN_CONFIG_FILE'" >&2
		return 1
	fi
}

lockdown_set_active() {
	local EXPECTED_ARGS=1
	if [ $# -ne $EXPECTED_ARGS ]; then
		echo "Usage: `basename $0` [lockdown_set_active] {true/false}" >&2
		return 1
	fi

	local LOCKDOWN_SET_ACTIVE=false
	if [ "$1" = true ]; then
		LOCKDOWN_SET_ACTIVE=true
	elif [ "$1" = false ]; then
		LOCKDOWN_SET_ACTIVE=false
	else
		echo "Usage: `basename $0` [lockdown_set_active] {true/false}" >&2
		return 1
	fi

	if [ "$LOCKDOWN_SET_ACTIVE" = true ]; then
		# Collect DNS server, make sure it's valid
		local DNS_SERVER_FOUND=false
		# > IPv4
		local DNS_SERVER_V4=""
		local DNS_SERVER_V4_VALID=false
		# Track errors
		set +e
		DNS_SERVER_V4="$(lockdown_get_dns_v4_server)"
		local RETVAL=$?
		set -e
		# Check results
		if [ $RETVAL -eq 0 ]; then
			# Valid result, limit to DNS resolver
			DNS_SERVER_FOUND=true
			DNS_SERVER_V4_VALID=true
		fi
		# > IPv6
		local DNS_SERVER_V6=""
		local DNS_SERVER_V6_VALID=false
		# Track errors
		set +e
		DNS_SERVER_V6="$(lockdown_get_dns_v6_server)"
		local RETVAL=$?
		set -e
		# Check results
		if [ $RETVAL -eq 0 ]; then
			# Valid result, limit to DNS resolver
			if [ "$NET_LOCKDOWN_DNS_IPV6_SUFFICIENT" = true ]; then
				# Only mark DNS as valid if IPv6 is sufficient
				DNS_SERVER_FOUND=true
			fi
			DNS_SERVER_V6_VALID=true
		fi

		# Collect addresses
		local RESOLVED_IPV4S=()
		local RESOLVED_IPV6S=()

		for HOSTNAME in "${NET_LOCKDOWN_ALLOWED_HOSTS[@]}"; do
			local IP_ADDR_V4=""
			local IP_ADDR_V6=""
			local REVAL=0
			# > IPv4
			# Resolve, tracking if errors occur
			set +e
			IP_ADDR_V4=$(lockdown_resolve "ipv4" "$HOSTNAME")
			RETVAL=$?
			set -e

			if [ $RETVAL -ne 0 ]; then
				# Something went wrong, log and continue
				echo "$NET_LOG_PREFIX Could not resolve '$HOSTNAME' for IPv4" >&2
			else
				# Multiple results are returned on multiple lines
				# See https://superuser.com/questions/284187/bash-iterating-over-lines-in-a-variable
				while read -r RESOLVED_IPV4_ADDR; do
					# Add IP address to list if unique
					# NOTE: This fails if spaces exist in addresses and new address is a substring
					# E.g. item "a b" would show as holding "a"
					# See https://stackoverflow.com/questions/3685970/check-if-a-bash-array-contains-a-value
					if [ ${#RESOLVED_IPV4S[@]} -eq 0 ]; then
						# No addresses in list, add first item
						RESOLVED_IPV4S=("$RESOLVED_IPV4_ADDR")
					elif [[ ! " ${RESOLVED_IPV4S[@]} " =~ " ${RESOLVED_IPV4_ADDR} " ]]; then
						# Not in list, add it
						RESOLVED_IPV4S+=("$RESOLVED_IPV4_ADDR")
					fi
				done <<< "$IP_ADDR_V4"
				# Take in the IPv4 list
			fi
	
			# > IPv6
			# Resolve, tracking if errors occur
			set +e
			IP_ADDR_V6=$(lockdown_resolve "ipv6" "$HOSTNAME")
			RETVAL=$?
			set -e
	
			if [ $RETVAL -ne 0 ]; then
				# Something went wrong, log and continue
				echo "$NET_LOG_PREFIX Could not resolve '$HOSTNAME' for IPv6" >&2
			else
				# Multiple results are returned on multiple lines
				# See https://superuser.com/questions/284187/bash-iterating-over-lines-in-a-variable
				while read -r RESOLVED_IPV6_ADDR; do
					# Add IP address to list if unique
					# NOTE: This fails if spaces exist in addresses and new address is a substring
					# E.g. item "a b" would show as holding "a"
					# See https://stackoverflow.com/questions/3685970/check-if-a-bash-array-contains-a-value
					if [ ${#RESOLVED_IPV6S[@]} -eq 0 ]; then
						# No addresses in list, add first item
						RESOLVED_IPV6S=("$RESOLVED_IPV6_ADDR")
					elif [[ ! " ${RESOLVED_IPV6S[@]} " =~ " ${RESOLVED_IPV6_ADDR} " ]]; then
						# Not in list, add it
						RESOLVED_IPV6S+=("$RESOLVED_IPV6_ADDR")
					fi
				done <<< "$IP_ADDR_V6"
				# Take in the IPv6 list
			fi
			
			#echo "DEBUG: Resolved hostname '$HOSTNAME' = '$IP_ADDR_V4' (v4), '$IP_ADDR_V6' (v6)"
		done

		# Format ports
		local RESOLVED_PORTS=$(lockdown_join_by "," "${NET_LOCKDOWN_ALLOWED_PORTS[@]}")

		# Sanity check - are any IPs allowed?  If not, keep the existing rules.
		local ALLOWED_IP_COUNT=$((${#RESOLVED_IPV4S[@]} + ${#RESOLVED_IPV6S[@]}))
		if [ $ALLOWED_IP_COUNT -eq 0 ]; then
			echo "$NET_LOG_PREFIX No valid resolved IP addresses, not updating rules (check NET_LOCKDOWN_ALLOWED_HOSTS, '${NET_LOCKDOWN_ALLOWED_HOSTS[@]}')" >&2
			# Delete staging rules
			# > IPv4
			ipt_cmd --flush "$NET_LOCKDOWN_IPCHAIN_STAGING"
			ipt_cmd --delete-chain "$NET_LOCKDOWN_IPCHAIN_STAGING"
			# > IPv6
			ip6t_cmd --flush "$NET_LOCKDOWN_IPCHAIN_STAGING"
			ip6t_cmd --delete-chain "$NET_LOCKDOWN_IPCHAIN_STAGING"
			# Return error
			return 1
		fi

		# Create chains
		# > IPv4
		if lockdown_ipt_has_chain "$NET_LOCKDOWN_IPCHAIN_STAGING"; then
			ipt_cmd --flush "$NET_LOCKDOWN_IPCHAIN_STAGING"
		else
			ipt_cmd --new-chain "$NET_LOCKDOWN_IPCHAIN_STAGING"
		fi
		# > IPv6
		if lockdown_ip6t_has_chain "$NET_LOCKDOWN_IPCHAIN_STAGING"; then
			ip6t_cmd --flush "$NET_LOCKDOWN_IPCHAIN_STAGING"
		else
			ip6t_cmd --new-chain "$NET_LOCKDOWN_IPCHAIN_STAGING"
		fi

		# Set up rules
		# > IPv4
		# Allow existing connections (e.g. if DNS changes)
		ipt_cmd --append "$NET_LOCKDOWN_IPCHAIN_STAGING" --match conntrack \
			--match comment --comment "existing_connections" \
			--ctstate ESTABLISHED --jump ACCEPT
		# Allow loopback
		ipt_cmd --append "$NET_LOCKDOWN_IPCHAIN_STAGING" --out-interface lo \
			--match comment --comment "loopback_connections" \
			--jump ACCEPT

		# Allow system DNS
		# Restrict to the system resolver if enabled and possible (see above)
		if [ "$DNS_SERVER_V4_VALID" = true ]; then
			# System resolver available, limit to specified resolver
			ipt_cmd --append "$NET_LOCKDOWN_IPCHAIN_STAGING" --protocol tcp --dport 53 \
				--destination $DNS_SERVER_V4 \
				--match comment --comment "DNS_TCP_system" \
				--jump ACCEPT
			ipt_cmd --append "$NET_LOCKDOWN_IPCHAIN_STAGING" --protocol udp --dport 53 \
				--destination $DNS_SERVER_V4 \
				--match comment --comment "DNS_UDP_system" \
				--jump ACCEPT
		elif [ "$DNS_SERVER_FOUND" = false ]; then
			# System resolver unknown, allow all DNS queries
			ipt_cmd --append "$NET_LOCKDOWN_IPCHAIN_STAGING" --protocol tcp --dport 53 \
				--match comment --comment "DNS_TCP_fallback" \
				--jump ACCEPT
			ipt_cmd --append "$NET_LOCKDOWN_IPCHAIN_STAGING" --protocol udp --dport 53 \
				--match comment --comment "DNS_UDP_fallback" \
				--jump ACCEPT
		fi
		# If only DNS_SERVER_V6_VALID, then block IPv4 DNS resolution

		# Allow specified ports for each IP address
		for IP_ADDR_V4 in "${RESOLVED_IPV4S[@]}"; do
			ipt_cmd --append "$NET_LOCKDOWN_IPCHAIN_STAGING" --protocol tcp \
				--match multiport --dports "$RESOLVED_PORTS" \
				--destination "$IP_ADDR_V4" \
				--match comment --comment "lockdown_IPv4" \
				--jump ACCEPT
		done
		# Set default policy to drop/block
		ipt_cmd --append "$NET_LOCKDOWN_IPCHAIN_STAGING" \
			--match comment --comment "default_policy_drop_IPv4" \
			--jump DROP
		# Custom chains can't have a policy
		#ipt_cmd --policy "$NET_LOCKDOWN_IPCHAIN_STAGING" DROP

		# > IPv6
		# Allow existing connections (e.g. if DNS changes)
		ip6t_cmd --append "$NET_LOCKDOWN_IPCHAIN_STAGING" --match conntrack \
			--match comment --comment "existing_connections" \
			--ctstate ESTABLISHED --jump ACCEPT
		# Allow loopback
		ip6t_cmd --append "$NET_LOCKDOWN_IPCHAIN_STAGING" --out-interface lo \
			--match comment --comment "loopback_connections" \
			--jump ACCEPT

		# Allow system DNS
		# Restrict to the system resolver if enabled and possible (see above)
		if [ "$DNS_SERVER_V6_VALID" = true ]; then
			# System resolver available, limit to specified resolver
			ip6t_cmd --append "$NET_LOCKDOWN_IPCHAIN_STAGING" --protocol tcp --dport 53 \
				--destination $DNS_SERVER_V6 \
				--match comment --comment "DNS_TCP_system" \
				--jump ACCEPT
			ip6t_cmd --append "$NET_LOCKDOWN_IPCHAIN_STAGING" --protocol udp --dport 53 \
				--destination $DNS_SERVER_V6 \
				--match comment --comment "DNS_UDP_system" \
				--jump ACCEPT
		elif [ "$DNS_SERVER_FOUND" = false ]; then
			# System resolver unknown, allow all DNS queries
			ip6t_cmd --append "$NET_LOCKDOWN_IPCHAIN_STAGING" --protocol tcp --dport 53 \
				--match comment --comment "DNS_TCP_fallback" \
				--jump ACCEPT
			ip6t_cmd --append "$NET_LOCKDOWN_IPCHAIN_STAGING" --protocol udp --dport 53 \
				--match comment --comment "DNS_UDP_fallback" \
				--jump ACCEPT
		fi
		# If only DNS_SERVER_V4_VALID, then block IPv6 DNS resolution

		# Allow specified ports for each IP address
		for IP_ADDR_V6 in "${RESOLVED_IPV6S[@]}"; do
			ip6t_cmd --append "$NET_LOCKDOWN_IPCHAIN_STAGING" --protocol tcp \
				--match multiport --dports "$RESOLVED_PORTS" \
				--destination "$IP_ADDR_V6" \
				--match comment --comment "lockdown_IPv6" \
				--jump ACCEPT
		done
		# Set default policy to drop/block
		ip6t_cmd --append "$NET_LOCKDOWN_IPCHAIN_STAGING" \
			--match comment --comment "default_policy_drop_IPv6" \
			--jump DROP
		# Custom chains can't have a policy
		#ipt_cmd --policy "$NET_LOCKDOWN_IPCHAIN_STAGING" DROP

		# Apply the new staging rules
		# > IPv4
		ipt_cmd --append OUTPUT --match owner --uid-owner "$NET_LOCKDOWN_LIMITED_USER" \
			--match comment --comment "match_restricted_user" \
			--jump "$NET_LOCKDOWN_IPCHAIN_STAGING"
		# > IPv6
		ip6t_cmd --append OUTPUT --match owner --uid-owner "$NET_LOCKDOWN_LIMITED_USER" \
			--match comment --comment "match_restricted_user" \
			--jump "$NET_LOCKDOWN_IPCHAIN_STAGING"

		# Disable and delete old rules (if existing)
		# > IPv4
		lockdown_ipt_purge_user_out "$NET_LOCKDOWN_IPCHAIN" "$NET_LOCKDOWN_LIMITED_USER"
		lockdown_ipt_purge_chain "$NET_LOCKDOWN_IPCHAIN"
		# > IPv6
		lockdown_ip6t_purge_user_out "$NET_LOCKDOWN_IPCHAIN" "$NET_LOCKDOWN_LIMITED_USER"
		lockdown_ip6t_purge_chain "$NET_LOCKDOWN_IPCHAIN"

		# Rename activated new rules
		# > IPv4
		ipt_cmd --rename-chain "$NET_LOCKDOWN_IPCHAIN_STAGING" "$NET_LOCKDOWN_IPCHAIN"
		# > IPv6
		ip6t_cmd --rename-chain "$NET_LOCKDOWN_IPCHAIN_STAGING" "$NET_LOCKDOWN_IPCHAIN"
	else
		# Remove output jump rules
		# Don't fail on any lines, to try to clean up as much as possible
		lockdown_ipt_purge_user_out "$NET_LOCKDOWN_IPCHAIN" "$NET_LOCKDOWN_LIMITED_USER" \
			|| echo "$NET_LOG_PREFIX Could not delete iptables OUTPUT rule" >&2
		lockdown_ipt_purge_user_out "$NET_LOCKDOWN_IPCHAIN_STAGING" "$NET_LOCKDOWN_LIMITED_USER" \
			|| echo "$NET_LOG_PREFIX Could not delete ip6tables OUTPUT rule"
		lockdown_ip6t_purge_user_out "$NET_LOCKDOWN_IPCHAIN" "$NET_LOCKDOWN_LIMITED_USER" \
			|| echo "$NET_LOG_PREFIX Could not delete iptables OUTPUT staging rule" >&2
		lockdown_ip6t_purge_user_out "$NET_LOCKDOWN_IPCHAIN_STAGING" "$NET_LOCKDOWN_LIMITED_USER" \
			|| echo "$NET_LOG_PREFIX Could not delete ip6tables OUTPUT staging rule"
		# Purge custom chains
		lockdown_ipt_purge_chain "$NET_LOCKDOWN_IPCHAIN" \
			|| echo "$NET_LOG_PREFIX Could not purge iptables network lockdown chain" >&2
		lockdown_ipt_purge_chain "$NET_LOCKDOWN_IPCHAIN_STAGING" \
			|| echo "$NET_LOG_PREFIX Could not purge iptables network lockdown staging chain" >&2
		lockdown_ip6t_purge_chain "$NET_LOCKDOWN_IPCHAIN" \
			|| echo "$NET_LOG_PREFIX Could not purge ip6tables network lockdown chain" >&2
		lockdown_ip6t_purge_chain "$NET_LOCKDOWN_IPCHAIN_STAGING" \
			|| echo "$NET_LOG_PREFIX Could not purge ip6tables network lockdown staging chain" >&2
		# ...it's off the chain!
	fi
}

EXPECTED_ARGS=1
if [ $# -ge $EXPECTED_ARGS ]; then
	case $1 in
		"enable" | "apply" | "refresh" )
			if ! lockdown_has_root; then
				echo "This script must be run with administrator privileges (e.g. sudo)." >&2
				exit 1
			fi
			lockdown_load_config
			lockdown_set_active true
			;;
		"disable" )
			if ! lockdown_has_root; then
				echo "This script must be run with administrator privileges (e.g. sudo)." >&2
				exit 1
			fi
			lockdown_load_config
			lockdown_set_active false
			;;
		* )
			echo "Usage: `basename "$0"` {command: enable/apply/refresh, disable}" >&2
			exit 1
			;;
	esac
else
	echo "Usage: `basename "$0"` {command: enable/apply/refresh, disable}" >&2
	exit 1
fi
