#!/bin/bash
while true; do

	# Backup configuration
	MYSQL_USER=${MYSQL_USER}
	MYSQL_PASSWORD=${MYSQL_PASSWORD}
	MYSQL_HOST=${MYSQL_HOST}
	DATABASES=${DATABASES}

	BASE_DIR=${BASE_DIR}
	INCREMENTAL_DIR=${INCREMENTAL_DIR}
	BACKUP_RETENTION=${BACKUP_RETENTION:-"30 days"}
	ARCHIVE_DIR=${ARCHIVE_DIR}  # Set your archive directory
	
	INTERVAL=${INTERVAL:-3600}

	REQUIRED_VARS=("MYSQL_USER" "MYSQL_PASSWORD" "MYSQL_HOST" "BASE_DIR" "INCREMENTAL_DIR" "DATABASES" "ARCHIVE_DIR"  "INTERVAL")

	for var in "${REQUIRED_VARS[@]}"; do
		if [ -z "${!var}" ]; then
			echo "Error: Environment variable $var is not set."
			exit 1
		fi
	done

	# Function to archive backups and delete old archives
	archive_backups() {
		mkdir -p "$ARCHIVE_DIR"
		ARCHIVE_NAME="${ARCHIVE_DIR}/backup_$(date +%Y%m%d).tar.gz"
		echo "Archiving previous backups..."
		tar -czvf "$ARCHIVE_NAME" "$BASE_DIR" "$INCREMENTAL_DIR"*
		rm -rf "$BASE_DIR" "$INCREMENTAL_DIR"*
		date +%s > "${BASE_DIR}/last_archive_timestamp"

		# Delete archives older than retention period
		find "$ARCHIVE_DIR" -name 'backup_*.tar.gz' -mtime +$(( $(date -d "$BACKUP_RETENTION" +%s) / 86400 )) -exec rm {} \;
	}

	# Check if it's time to archive (24 hours = 86400 seconds)
	if [ -f "$ARCHIVE_TIMESTAMP_FILE" ]; then
		LAST_ARCHIVE_TIME=$(cat "$ARCHIVE_TIMESTAMP_FILE")
		if [ -z "$LAST_ARCHIVE_TIME" ]; then
			LAST_ARCHIVE_TIME=0
		fi
	else
		LAST_ARCHIVE_TIME=0
	fi

	CURRENT_TIME=$(date +%s)
	if [ $(($CURRENT_TIME - $LAST_ARCHIVE_TIME)) -ge 86400 ]; then
		archive_backups
	fi

	# Check if base backup needs to be created
	if [ ! -d "$BASE_DIR" ]; then
		echo "Creating base backup..."
		xtrabackup --backup --host=$MYSQL_HOST --user=$MYSQL_USER --password=$MYSQL_PASSWORD --target-dir=$BASE_DIR --databases=$DATABASES
	else
		# Create incremental backup
		NEXT_INC="${INCREMENTAL_DIR}$(date +%Y%m%d%H%M%S)"
		echo "Creating incremental backup..."
		xtrabackup --backup --host=$MYSQL_HOST --user=$MYSQL_USER --password=$MYSQL_PASSWORD --target-dir=$NEXT_INC --incremental-basedir=$BASE_DIR --databases=$DATABASES
	fi
	
    # Wait for 1 hour (3600 seconds) before the next run
    sleep 3600
done