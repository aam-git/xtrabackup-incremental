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
        tar -cvf "$ARCHIVE_NAME" "$BASE_DIR" "$INCREMENTAL_DIR"*
        rm -rf "$BASE_DIR" "$INCREMENTAL_DIR"*
        date +%s > "${BASE_DIR}/last_archive_timestamp"

        # Delete archives older than retention period
        find "$ARCHIVE_DIR" -name 'backup_*.tar.gz' -mtime +$(( $(date -d "$BACKUP_RETENTION" +%s) / 86400 )) -exec rm {} \;
    }

    # Function to count incremental backups
    count_increments() {
        find "$INCREMENTAL_DIR" -mindepth 1 -maxdepth 1 -type d -printf '.' | wc -c
    }

    # Function to get the base directory for the next incremental backup
    get_incremental_base_dir() {
        if [ -f "${INCREMENTAL_DIR}/latest_increment" ]; then
            cat "${INCREMENTAL_DIR}/latest_increment"
        else
            echo "$BASE_DIR"
        fi
    }

    # Function to update the latest incremental backup reference
    update_latest_increment() {
        echo "$1" > "${INCREMENTAL_DIR}/latest_increment"
    }

    CURRENT_TIME=$(date +%s)

    # Ensure BASE_DIR exists
    mkdir -p "$BASE_DIR"

    # Ensure last_archive_timestamp file exists
    if [ ! -f "${BASE_DIR}/last_archive_timestamp" ]; then
        echo $CURRENT_TIME > "${BASE_DIR}/last_archive_timestamp"
    fi

    # Now read the last archive time
    LAST_ARCHIVE_TIME=$(cat "${BASE_DIR}/last_archive_timestamp")

    INCREMENT_COUNT=$(count_increments)

    # Check conditions for archiving: time elapsed or too many increments
    if { [ $((CURRENT_TIME - LAST_ARCHIVE_TIME)) -ge 86400 ] || [ $INCREMENT_COUNT -ge 24 ]; } && { [ -d "$BASE_DIR" ] || [ $INCREMENT_COUNT -gt 0 ]; }; then
        archive_backups
    fi

    # Check if base backup needs to be created
    if [ ! -d "$BASE_DIR" ] || [ ! -f "${BASE_DIR}/xtrabackup_info" ]; then
        echo "Creating base backup..."
        xtrabackup --backup --host=$MYSQL_HOST --user=$MYSQL_USER --password=$MYSQL_PASSWORD --target-dir=$BASE_DIR --databases="$DATABASES"
        # Reset the latest incremental backup reference
        rm -f "${INCREMENTAL_DIR}/latest_increment"
    else
        # Determine the base directory for the next incremental backup
        INCREMENTAL_BASE=$(get_incremental_base_dir)
        NEXT_INC="${INCREMENTAL_DIR}/inc_$(date +%Y%m%d%H%M%S)"
        mkdir -p "$NEXT_INC"
        echo "Creating incremental backup based on $INCREMENTAL_BASE..."
        xtrabackup --backup --host=$MYSQL_HOST --user=$MYSQL_USER --password=$MYSQL_PASSWORD --target-dir="$NEXT_INC" --incremental-basedir="$INCREMENTAL_BASE" --databases="$DATABASES"
        update_latest_increment "$NEXT_INC"
    fi

    # Wait for the next run
    sleep $INTERVAL
done
