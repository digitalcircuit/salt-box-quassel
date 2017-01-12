#!/bin/bash
#--------------------------------------------------
# Load user root directory
_LOCAL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# > This script should be one directory lower than the root directory
source "$_LOCAL_DIR/../var-root-dir.sh"
#--------------------------------------------------

QUASSEL_WEB_WORKDIR="$USER_ROOT_DIR/qweb"
QUASSEL_WEB_GITDIR="$QUASSEL_WEB_WORKDIR/quassel-webserver"

# Check if running before updating; if so, don't allow update
QWEB_SERVICE_NAME="quassel-web.service"

qweb_running () {
	if systemctl -q is-active "$QWEB_SERVICE_NAME"; then
		return 0
	else
		return 1
	fi
}

# Based on git_auto_update from system-automatic-setup.sh, submodule config-system-setup.sh
qweb_install ()
{
	# Git handling
	local GIT_URL="https://github.com/magne4000/quassel-webserver.git"
	local GIT_WORKDIR="$QUASSEL_WEB_WORKDIR"
	local GIT_REPODIR="$QUASSEL_WEB_GITDIR"

	local GIT_CHECKOUT="${1:-''}"
	EXPECTED_ARGS=1
	if [ $# -gt $EXPECTED_ARGS ]; then
		echo "Usage: `basename $0` qweb_install {optional: branch or commit hash, defaults to nothing}" >&2
		return 1
	fi
	
	if qweb_running; then
		echo " * Quassel Web running, please stop it first! (systemctl stop $QWEB_SERVICE_NAME)"
		return 1
	fi

	mkdir --parents "$GIT_WORKDIR" || return 1
	
	cd "$GIT_WORKDIR" || return 1
	
	if [ ! -d "$GIT_REPODIR" ]; then
		echo " * Downloading repository '$GIT_URL'..."
		git clone "$GIT_URL" || return 1
		# Move to repository before trying to check out
		cd "$GIT_REPODIR" || return 1
		if [[ "$GIT_CHECKOUT" != "" ]]; then
			echo "Custom install: checking out branch or hash '$GIT_CHECKOUT'"
			git checkout "$GIT_CHECKOUT" || return 1
		fi
		echo " > Setting up NodeJS..."
		npm install --production || return 1
	else
		echo " * Updating repository '$GIT_URL'..."
		cd "$GIT_REPODIR" || return 1
		
		GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
		if [[ "$GIT_BRANCH" == "HEAD" ]]; then
			# FIXME: We're not on a branch, can't git pull directly.
			# Temporarily check 'master' to update
			git checkout master || return 1
		fi
		
		git pull || return 1
		if [[ "$GIT_CHECKOUT" != "" ]]; then
			echo "Custom update: checking out branch or hash '$GIT_CHECKOUT'"
			git checkout "$GIT_CHECKOUT" || return 1
		fi
		echo " > Updating NodeJS..."
		npm prune && npm update || return 1
		cd "$GIT_WORKDIR"
	fi
	
}

qweb_has_update() {
	if [ ! -d "$QUASSEL_WEB_GITDIR" ]; then
		# Quassel Web not installed, has an update
		return 0
	fi
	
	EXPECTED_ARGS=1
	if [ $# -gt $EXPECTED_ARGS ]; then
		echo "Usage: `basename $0` qweb_has_update {optional: upstream branch or commit hash, defaults to '@{u}'}" >&2
		return 1
	fi
	
	# Installed, now check Git
	cd "$QUASSEL_WEB_GITDIR"
	# Update status...
	git remote update
	
	# Check status
	# Thanks to https://stackoverflow.com/questions/3258243/check-if-pull-needed-in-git/3278427#3278427
	local UPSTREAM=${1:-'@{u}'}
	local LOCAL=$(git rev-parse @)
	local REMOTE=$(git rev-parse "$UPSTREAM")
	local BASE=$(git merge-base @ "$UPSTREAM")
	
	# Edited: make sure we're on a branch
	GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
	if [[ "$GIT_BRANCH" == "HEAD" && "$UPSTREAM" == "@{u}" ]]; then
		echo "Can't check for updates, not currently on a branch and no specific branch or commit hash specified!  Try specifying 'master' as the branch." >&2
		return 1
	fi

	if [ $LOCAL = $REMOTE ]; then
		# Up-to-date
		return 1
	elif [ $LOCAL = $BASE ]; then
		# Need to pull
		return 0
	elif [ $REMOTE = $BASE ]; then
		# Need to push
		echo "Local repository is further into the future than remote!" >&2
		# Edited: Originally returned 1, to ignore the situation; now returns 0
		# if a checkout step is applied.
		if [[ "$UPSTREAM" != "@{u}" ]]; then
			return 0
		else
			return 1
		fi
	else
		# Diverged
		echo "Local repository no longer aligns with remote!" >&2
		return 1
	fi
}

qweb_update() {
	local GIT_CHECKOUT="${1:-''}"
	local GIT_UPSTREAM="@{u}"
	if [[ $GIT_CHECKOUT != "" ]]; then
		GIT_UPSTREAM="$GIT_CHECKOUT"
	fi

	EXPECTED_ARGS=1
	if [ $# -gt $EXPECTED_ARGS ]; then
		echo "Usage: `basename $0` qweb_update {optional: branch or commit hash, defaults to nothing}" >&2
		return 1
	fi
	
	if qweb_has_update "$GIT_UPSTREAM"; then
		if qweb_running; then
			echo " * Quassel Web running, please stop it first! (systemctl stop $QWEB_SERVICE_NAME)"
			return 1
		fi
		qweb_install "$GIT_CHECKOUT" || return 1
	else
		echo "> No updates for Quassel Web available"
	fi
}

EXPECTED_ARGS=1
if [ $# -ge $EXPECTED_ARGS ]; then
	EXPECTED_ARGS_CUSTOM=2
	CUSTOM_PARAMS=""
	CUSTOM_UPSTREAM="@{u}"
	if [ $# -ge $EXPECTED_ARGS_CUSTOM ]; then
		# Do a custom installation
		# Ignore the prefix of 'install'/'update'/etc
		array=( $* )
		len=${#array[*]}
		# See http://www.cyberciti.biz/faq/linux-unix-appleosx-bash-script-extract-parameters-before-last-args/
		CUSTOM_PARAMS="${array[@]:1:$len}"
		CUSTOM_UPSTREAM="$CUSTOM_PARAMS"
	fi
	case $1 in
		"check" )
			qweb_has_update "$CUSTOM_UPSTREAM"
			# Return the status code
			exit $?
			;;
		"install" )
			qweb_install "$CUSTOM_PARAMS"
			# Return the status code
			exit $?
			;;
		"update" )
			qweb_update "$CUSTOM_PARAMS"
			# Return the status code
			exit $?
			;;
		* )
			echo "Usage: `basename $0` {command: check, install, update}" >&2
			exit 1
			;;
	esac
else
	echo "Usage: `basename $0` {command: check, install, update}" >&2
	exit 1
fi
