#!/bin/bash
# See http://redsymbol.net/articles/unofficial-bash-strict-mode/
set -euo pipefail

_LOCAL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# Get directory of this file

# Indicates that archive script utilities have been loaded
MODULE_ARCHIVE_UTIL_SCRIPT_LOADED="true"

# Will be loaded from subdirectory

ARCHIVE_SCRIPT_SETTINGS_PATH="$_LOCAL_DIR/config-archive-script.sh"
#-------------------------------------------------------------
if [ -z "${MODULE_ARCHIVE_SCRIPT_SETTINGS_LOADED:-}" ]; then
	source "$ARCHIVE_SCRIPT_SETTINGS_PATH"
fi
#-------------------------------------------------------------
# Check if session environment is prepared
if [ -z "${MODULE_ARCHIVE_SCRIPT_SETTINGS_LOADED:-}" ]; then
	# Quit as nothing can happen
	echo "Archive script configuration not loaded, does the file 'config-archive-script.sh' exist? (will now exit)" >&2
	exit 1
fi
#-------------------------------------------------------------

archive_script_print_usage ()
{
	echo "Usage: `basename $0` {command: backup, check, restore}" >&2
}

archive_script_check_paths ()
{
	if [ ! -d "$AMOD_ARCHIVE_PATH_ROOT" ]; then
		echo "Archive root path '$AMOD_ARCHIVE_PATH_ROOT' does not exist" >&2
		return 1
	fi
	
	AMOD_ARCHIVE_DIR="$AMOD_ARCHIVE_PATH_ROOT/$AMOD_BACKUP_NAME"
	AMOD_BACKUP_PRIMARY_FILENAME="$AMOD_ARCHIVE_DIR/$AMOD_BACKUP_PRIMARY_NAME"
	
	# Make script-specific path if not existing
	if [ ! -d "$AMOD_ARCHIVE_DIR" ]; then
		if ! mkdir "$AMOD_ARCHIVE_DIR"; then
			echo "Could not create local storage folder '$AMOD_ARCHIVE_DIR'" >&2
			return 1
		fi
	fi
}

archive_backup_directory ()
{
	# Usage from script
	#
	# > Backing up specific files/folders
	# BACKUP_OPTIONS=("/etc/app-folder" "/var/backup/archive-no-extension" "Friendly description" "Item1" "File2" "...")
	# archive_backup_directory BACKUP_OPTIONS[@]
	#
	# > Backing up entire directory
	# BACKUP_OPTIONS=("/etc/app-folder" "/var/backup/archive-no-extension" "Friendly description")
	# archive_backup_directory BACKUP_OPTIONS[@]
	#
	# > Backing up entire directory, excluding anything matching patterns
	# BACKUP_OPTIONS=("/etc/app-folder" "/var/backup/archive-no-extension" "Friendly description")
	# BACKUP_EXCLUDE_PATTERNS=("Item1", "Item*.bak")
	# archive_backup_directory BACKUP_OPTIONS[@] BACKUP_EXCLUDE_PATTERNS[@]
	#
	#
	# $1 = Directory
	# $2 = Name of archive to create, without extension (was $3)
	# $3 = Friendly description (was $4)
	# $4 = Paths inside directory (was $2)

	# Backup directories inside the specified root directory to an archive file
	EXPECTED_ARGS=1
	EXPECTED_ARGS_EXCLUDE=2
	EXPECTED_ARGS_ARRAY_LEN_FULL=3
	EXPECTED_ARGS_ARRAY_LEN_SPECIFIED=4

	if [ $# -lt $EXPECTED_ARGS ] || [ $# -gt $EXPECTED_ARGS_EXCLUDE ]; then
		echo "Usage: `basename $0` [archive_backup_directory] array of ({root directory} {name of archive, without extension} {friendly description} {optional: files/folders inside directory to backup}) {optional: array of (paths inside directory to exclude)}" >&2
		return 1
	fi

	declare -a ARGS=("${!1}")
	local DIR_ROOT="${ARGS[@]:0:1}"
	local DIR_ARCHIVE_NAME="${ARGS[@]:1:1}"
	local DIR_DESCRIPTION="${ARGS[@]:2:1}"
	#local array=( $@ )
	#local len=${#array[@]}
	## See http://www.cyberciti.biz/faq/linux-unix-appleosx-bash-script-extract-parameters-before-last-args/
	# See https://superuser.com/questions/454559/word-splitting-does-not-see-my-quotes and https://stackoverflow.com/questions/1063347/passing-arrays-as-parameters-in-bash
	# NEW: ARGS method
	local ARGS_LEN=${#ARGS[@]}
	# Paths to back up:  ${array[@]:3:$ARGS_LEN}

	# Get the name of the input directory
	# See https://stackoverflow.com/questions/3294072/bash-get-last-dirname-filename-in-a-file-path-argument/3294514#3294514
	local DIR_ROOT_TRIMMED="${DIR_ROOT%/}"
	local DIR_ROOT_NAME="${DIR_ROOT_TRIMMED##*/}"

	if [ $# -eq $EXPECTED_ARGS_EXCLUDE ]; then
		local ARGS_USE_EXCLUDE="true"
		declare -a ARGS_EXCLUDE=("${!2}")
	else
		local ARGS_USE_EXCLUDE="false"
	fi

	# Save relative to the parent folder for a consistent package
	#
	# Get the parent folder of the input directory
	# See https://www.gnu.org/software/bash/manual/html_node/Shell-Parameter-Expansion.html
	local DIR_ROOT_PARENT="${DIR_ROOT%/*}"

	if [ $ARGS_LEN -eq $EXPECTED_ARGS_ARRAY_LEN_FULL ]; then
		# Backup full directory
		local DIR_ARCHIVE_PATHS=("$DIR_ROOT")
	elif [ $ARGS_LEN -ge $EXPECTED_ARGS_ARRAY_LEN_SPECIFIED ]; then
		# Backup specific files
		#
		# Trim from end of array
		# See https://stackoverflow.com/questions/1335815/how-to-slice-an-array-in-bash
		local DIR_ARCHIVE_PATHS=("${ARGS[@]:3}")
		#local DIR_ARCHIVE_PATHS=${ARGS[@]:3:$ARGS_LEN}
	else
		echo "Usage: `basename $0` [archive_backup_directory] array of ({root directory} {name of archive, without extension} {friendly description} {optional: files/folders inside directory to backup})" >&2
		return 1
	fi
	
	# Save paths separately
	local DIR_ARCHIVE_PATHS_LEN=${#DIR_ARCHIVE_PATHS[@]}

	# Trim redundant path information
	# "/tmp/test/source"        -> "source"
	# "/tmp/test/source/file_a" -> "source/file_a"
	for ((i=0; i<=$DIR_ARCHIVE_PATHS_LEN - 1; i++)); do
		local DIR_ARCHIVE_PATH="${DIR_ARCHIVE_PATHS[$i]}"
		# Transform relative paths into full paths
		if [[ ! "$DIR_ARCHIVE_PATH" =~ ^"$DIR_ROOT" ]]; then
			# Remove any trailing slash
			DIR_ARCHIVE_PATH="$DIR_ROOT/${DIR_ARCHIVE_PATH%/}"
		fi
		# Trim path information, if specified
		# Trim down to name of root folder, no higher
		DIR_ARCHIVE_PATH="${DIR_ARCHIVE_PATH//$DIR_ROOT_PARENT/}"
		# Remove leading slash
		DIR_ARCHIVE_PATHS[$i]="${DIR_ARCHIVE_PATH#/}"
	done

	#echo "[$(date --rfc-3339=seconds)] Backing up '$DIR_DESCRIPTION'..."

	# Exclude patterns
	local TAR_EXCLUDE_FLAG=""
	if [[ "$ARGS_USE_EXCLUDE" == "true" ]]; then
		# ARGS_EXCLUDE=("pattern*", "pattern2*.ext")

		# Append directory name to exclusion patterns
		# For "/tmp/test"...
		# "source"        -> "test/source"
		# "source/file_a" -> "test/source/file_a"
		local ARGS_EXCLUDE_LEN=${#ARGS_EXCLUDE[@]}

		for ((i=0; i<=$ARGS_EXCLUDE_LEN - 1; i++)); do
			local EXCLUDE_PATTERN="${ARGS_EXCLUDE[$i]}"
			# Transform relative paths into path-prefixed path
			if [[ ! "$DIR_ARCHIVE_PATH" =~ ^"$DIR_ROOT_NAME" ]]; then
				EXCLUDE_PATTERN="$DIR_ROOT_NAME/$EXCLUDE_PATTERN"
			fi
			#ARGS_EXCLUDE[$i]="${EXCLUDE_PATTERN#/}"
			# Append to exclusion flag
			TAR_EXCLUDE_FLAG="$TAR_EXCLUDE_FLAG --exclude=$EXCLUDE_PATTERN"
		done
		## ARGS_EXCLUDE=("test/pattern*", "test/pattern2*.ext")
		#TAR_EXCLUDE_FLAG="--exclude={${ARGS_EXCLUDE[@]}}"
		## {test/pattern*, test/pattern2*.ext}
	fi

	# rsyncable modifes the gzip compression format to be more friendly with rsync
	if [[ "$ARCHIVE_ENCRYPT_ENABLE" == "true" ]]; then
		# > Encrypted
		(GZIP="--rsyncable" nice ionice -c 3 tar --gzip --create --file - --directory "$DIR_ROOT_PARENT" $TAR_EXCLUDE_FLAG ${DIR_ARCHIVE_PATHS[@]} | $ARCHIVE_ENCRYPT_FILTER > "$DIR_ARCHIVE_NAME.$ARCHIVE_BACKUP_TAR_EXT_PGP" ) || return 1
		# -z is gzip, -J is xz (lzma2)
		# ${ARGS[@]:3:$ARGS_LEN} is replaced by ${DIR_ARCHIVE_PATHS[@]}
	else
		# > Direct
		GZIP="--rsyncable" nice ionice -c 3 tar --gzip --create --file "$DIR_ARCHIVE_NAME.$ARCHIVE_BACKUP_TAR_EXT" --directory $TAR_EXCLUDE_FLAG "$DIR_ROOT_PARENT" ${DIR_ARCHIVE_PATHS[@]} || return 1
	fi
}

archive_restore_directory () {
	# Usage from script
	#
	# > Restoring files/folders, overwriting existing
	# archive_restore_directory "/var/backup/archive-no-extension" "/etc/app-folder"
	#
	#
	local EXPECTED_ARGS=2
	if [[ $# -ne $EXPECTED_ARGS ]]; then
		echo "Usage: `basename $0` [archive_restore_directory] {archive name, without extension} {desired directory, overwriting existing files, keeping other files}" >&2
		return 1
	fi

	# Archive file (add unencrypted extension)
	local INPUT_ARCHIVE_FILE="$1.$ARCHIVE_BACKUP_TAR_EXT"
	# Output folder
	local OUTPUT_DESTINATION="$2"

	# Get the parent folder of the destination directory
	# See https://www.gnu.org/software/bash/manual/html_node/Shell-Parameter-Expansion.html
	local OUTPUT_DESTINATION_PARENT="${OUTPUT_DESTINATION%/*}"

	# Get the name of the output directory
	# See https://stackoverflow.com/questions/3294072/bash-get-last-dirname-filename-in-a-file-path-argument/3294514#3294514
	local OUTPUT_DESTINATION_NAME="${OUTPUT_DESTINATION%/}"
	OUTPUT_DESTINATION_NAME="${OUTPUT_DESTINATION_NAME##*/}"
	
	if [ ! -f "$INPUT_ARCHIVE_FILE" ]; then
		echo "Error: unable to restore, input archive file '$INPUT_ARCHIVE_FILE' does not exist" >&2
		return 1
	fi

	if [ ! -d "$OUTPUT_DESTINATION_PARENT" ]; then
		echo "Error: unable to restore, output destination folder parent '$OUTPUT_DESTINATION_PARENT' does not exist" >&2
		return 1
	fi

	# Create the destination directory if needed
	if [ ! -d "$OUTPUT_DESTINATION" ]; then
		mkdir "$OUTPUT_DESTINATION" || return 1
	fi

	# Extract files
	tar --extract --gzip --file "$INPUT_ARCHIVE_FILE" --overwrite --directory "$OUTPUT_DESTINATION_PARENT" "$OUTPUT_DESTINATION_NAME" || return 1
}

archive_backup_psql_db ()
{
	# Backup PostgreSQL database to an archive file
	EXPECTED_ARGS=2

	if [ $# -ne $EXPECTED_ARGS ]; then
		echo "Usage: `basename $0` [archive_backup_psql_db] {name of archive, without extension} {PostgreSQL database name}" >&2
		return 1
	fi

	# Storage archive
	local DIR_ARCHIVE_NAME="$1"
	# PostgreSQL database name
	local PSQL_DB_NAME="$2"

	if [[ "$ARCHIVE_ENCRYPT_ENABLE" == "true" ]]; then
		# > Encrypted
		(nice ionice -c 3 sudo --user=postgres --login pg_dump --no-password --format=custom --compress=9 --dbname="$PSQL_DB_NAME" | $ARCHIVE_ENCRYPT_FILTER > "$DIR_ARCHIVE_NAME.psql.pgp") || return 1
		# PostgreSQL's "custom" format includes compression
		# Customize with --compress=0..9
		# See https://www.postgresql.org/docs/current/app-pgdump.html
		#
		# To restore into plain SQL, use "pg_restore"
	else
		# > Direct
		nice ionice -c 3 sudo --user=postgres --login pg_dump --no-password --format=custom --compress=9 --dbname="$PSQL_DB_NAME" > "$DIR_ARCHIVE_NAME.psql" || return 1
	fi
}

archive_restore_psql_db () {
	# Restore a PostgreSQL database from an archive file, overwriting
	local EXPECTED_ARGS=2
	if [[ $# -ne $EXPECTED_ARGS ]]; then
		echo "Usage: `basename $0` [archive_restore_psql_db] {name of archive, without extension} {PostgreSQL database name}" >&2
		return 1
	fi

	# Archive file (add unencrypted extension)
	local INPUT_ARCHIVE_FILE="$1.psql"
	# PostgreSQL database name
	local PSQL_DB_NAME="$2"

	if [ ! -f "$INPUT_ARCHIVE_FILE" ]; then
		echo "Error: unable to restore, input archive file '$INPUT_ARCHIVE_FILE' does not exist" >&2
		return 1
	fi

	# Extract database, deleting existing database first if it exists
	# Restore with multiple processes
	#
	# Note:
	# pg_restore: options -d/--dbname and -f/--file cannot be used together

	local PSQL_JOBS="$(nproc)"
	# > Move into a temporary directory to allow for multiple restore jobs via
	# 'postgres' user direct access
	local PSQL_TEMP_DIR="$(sudo --user postgres --login -- mktemp -d)"
	local PSQL_TEMP_FILE="$PSQL_TEMP_DIR/source-file.psql"
	mv "$INPUT_ARCHIVE_FILE" "$PSQL_TEMP_FILE" || return 1
	chown postgres:postgres "$PSQL_TEMP_FILE" || return 1
	# > Restore
	if [ ! -f "$PSQL_TEMP_FILE" ]; then
		echo "Error: unable to restore, temporary file '$PSQL_TEMP_FILE' does not exist" >&2
		return 1
	fi
	# > Remove existing database first
	sudo --user=postgres --login psql --quiet --command="DROP DATABASE IF EXISTS $PSQL_DB_NAME;"
	# Database name is ignored when using "--create"
	# --dbname="$PSQL_DB_NAME"
	sudo --user=postgres --login pg_restore --no-password --format=custom --jobs="$PSQL_JOBS" --create --dbname="postgres" "$PSQL_TEMP_FILE" || return 1
	# > Move temporary file back, restore permissions
	mv "$PSQL_TEMP_FILE" "$INPUT_ARCHIVE_FILE" || return 1
	chown root:root "$INPUT_ARCHIVE_FILE" || return 1

	# Analyze to improve performance
	sudo --user=postgres --login psql --quiet --dbname="$PSQL_DB_NAME" --command="VACUUM ANALYZE;" || return 1
}
