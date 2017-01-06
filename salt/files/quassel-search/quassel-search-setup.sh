#!/bin/bash

qrsearch_psql_command () {
	local PSQL_DB_NAME=""
	local PSQL_DB_CMD=""
	EXPECTED_ARGS=2
	if [ $# -ge $EXPECTED_ARGS ]; then
		# Ignore the prefix of 'database name'
		array=( $* )
		len=${#array[*]}
		# See http://www.cyberciti.biz/faq/linux-unix-appleosx-bash-script-extract-parameters-before-last-args/
		PSQL_DB_CMD="${array[@]:1:$len}"
		PSQL_DB_NAME="$1"
	else
		echo "Usage: `basename "$0"` [qrsearch_psql_command] {database name, e.g. 'quassel'} {SQL command}" >&2
	fi
	sudo --user postgres psql "$PSQL_DB_NAME" --pset="format=unaligned" --command="$PSQL_DB_CMD"
	return $?
}

qrsearch_database_update_index () {
	local EXPECTED_ARGS=1
	if [ $# -ne $EXPECTED_ARGS ]; then
		echo "Usage: `basename "$0"` [qrsearch_database_update_index] {database name, e.g 'quassel'}" >&2
		return 1
	fi
	local PSQL_DB_NAME="$1"
	
	echo " * Updating Quassel search database index (may take a while)"
	qrsearch_psql_command "$PSQL_DB_NAME" "UPDATE backlog SET messageid = messageid;" || return 1
}

qrsearch_database_enable () {
	local EXPECTED_ARGS=1
	if [ $# -ne $EXPECTED_ARGS ]; then
		echo "Usage: `basename "$0"` [qrsearch_database_enable] {database name, e.g 'quassel'}" >&2
		return 1
	fi
	local PSQL_DB_NAME="$1"

	# Postgres 9.6 will allow ALTER TABLE name ADD COLUMN IF NOT EXISTS
	# https://stackoverflow.com/questions/12597465/how-to-add-column-if-not-exists-on-postgresql/38721951#38721951
	echo " * Enabling Quassel search in database"
	echo "> Adding backlog columns... (1/4)"
	qrsearch_psql_command "$PSQL_DB_NAME" "ALTER TABLE public.backlog ADD COLUMN tsv tsvector;" || return 1
	echo "> Adding full backlog index... (2/4)"
	qrsearch_psql_command "$PSQL_DB_NAME" "
CREATE INDEX CONCURRENTLY backlog_tsv_idx
  ON public.backlog
  USING gin(tsv);" || return 1
	echo "> Adding filtered backlog index... (3/4)"
	qrsearch_psql_command "$PSQL_DB_NAME" "
CREATE INDEX CONCURRENTLY backlog_tsv_filtered_idx
  ON public.backlog
  USING gin(tsv)
  WHERE (type & 23559) > 0;" || return 1
	echo "> Adding trigger to update backlog index... (4/4)"
	qrsearch_psql_command "$PSQL_DB_NAME" "
CREATE TRIGGER tsvectorupdate
  BEFORE INSERT OR UPDATE
  ON public.backlog
  FOR EACH ROW
  EXECUTE PROCEDURE tsvector_update_trigger('tsv', 'pg_catalog.english', 'message');" || return 1
	 # If other languages desired, update 'pg_catalog.english' above
}

qrsearch_database_disable () {
	local EXPECTED_ARGS=1
	if [ $# -ne $EXPECTED_ARGS ]; then
		echo "Usage: `basename "$0"` [qrsearch_database_disable] {database name, e.g 'quassel'}" >&2
		return 1
	fi
	local PSQL_DB_NAME="$1"

	# Postgres 9.6 will allow ALTER TABLE name ADD COLUMN IF NOT EXISTS
	# https://stackoverflow.com/questions/12597465/how-to-add-column-if-not-exists-on-postgresql/38721951#38721951
	echo " * Disabling Quassel search in database"
	echo "> Removing trigger to update backlog index... (1/4)"
	qrsearch_psql_command "$PSQL_DB_NAME" "DROP TRIGGER tsvectorupdate ON public.backlog;" || return 1
	echo "> Removing full backlog index... (2/4)"
	qrsearch_psql_command "$PSQL_DB_NAME" "DROP INDEX CONCURRENTLY backlog_tsv_idx;" || return 1
	echo "> Removing filtered backlog index... (3/4)"
	qrsearch_psql_command "$PSQL_DB_NAME" "DROP INDEX CONCURRENTLY backlog_tsv_filtered_idx;" || return 1
	echo "> Removing backlog columns... (4/4)"
	qrsearch_psql_command "$PSQL_DB_NAME" "ALTER TABLE public.backlog DROP COLUMN IF EXISTS tsv;" || return 1
}

qrsearch_is_configured () {
	local EXPECTED_ARGS=1
	if [ $# -ne $EXPECTED_ARGS ]; then
		echo "Usage: `basename "$0"` [qrsearch_is_configured] {database name, e.g 'quassel'}" >&2
		return 1
	fi
	local PSQL_DB_NAME="$1"

	if qrsearch_psql_command "$PSQL_DB_NAME" "
SELECT EXISTS (SELECT 1 
FROM information_schema.columns 
WHERE table_name='backlog' and column_name='tsv');" | grep --quiet "^t$"; then
		# 't' is in a single line of output from psql, column exists
		# Search has been configured
		return 0
	else
		return 1
	fi
}

qrsearch_enable () {
	local EXPECTED_ARGS=1
	if [ $# -ne $EXPECTED_ARGS ]; then
		echo "Usage: `basename "$0"` [qrsearch_enable] {database name, e.g 'quassel'}" >&2
		return 1
	fi
	local PSQL_DB_NAME="$1"

	if qrsearch_is_configured "$PSQL_DB_NAME"; then
		echo "> Quassel search already enabled"
		return 0
	fi
	
	echo "> Enabling database index..."
	qrsearch_database_enable "$PSQL_DB_NAME" || return 1
	echo "> Updating database..."
	qrsearch_database_update_index "$PSQL_DB_NAME" || return 1
	echo "> Quassel search enabled."
}

qrsearch_disable () {
	local EXPECTED_ARGS=1
	if [ $# -ne $EXPECTED_ARGS ]; then
		echo "Usage: `basename "$0"` [qrsearch_disable] {database name, e.g 'quassel'}" >&2
		return 1
	fi
	local PSQL_DB_NAME="$1"

	if ! qrsearch_is_configured "$PSQL_DB_NAME"; then
		echo "> Quassel search not enabled"
		return 0
	fi
	
	echo "> Disabling and clearing database index..."
	qrsearch_database_disable "$PSQL_DB_NAME" || return 1
	echo "> Quassel search disabled.  You should run a full vacuum."
}

EXPECTED_ARGS=2
if [ $# -ge $EXPECTED_ARGS ]; then
	case $2 in
		"check" )
			qrsearch_is_configured "$1"
			# Return the status code
			exit $?
			;;
		"enable" )
			qrsearch_enable "$1"
			exit $?
			;;
		"disable" )
			qrsearch_disable "$1"
			exit $?
			;;
		* )
			echo "Usage: `basename $0` {database name, e.g 'quassel'} {command: check, enable, disable}" >&2
			exit 1
			;;
	esac
else
	echo "Usage: `basename $0` {database name, e.g 'quassel'} {command: check, enable, disable}" >&2
	exit 1
fi
