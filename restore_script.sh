#!/bin/bash

# Environment variables
BASE_DIR=${BASE_DIR}
INCREMENTAL_DIR=${INCREMENTAL_DIR}
DATA_DIR="/var/lib/mysql"  # MySQL data directory
ARCHIVE_DIR=${ARCHIVE_DIR}  # Directory where archives are stored

# Ask user to stop MySQL server
echo "Please ensure that the MySQL server is stopped before proceeding."
read -p "Press any key to continue once the MySQL server is stopped..."

# Ask user for restore source
echo "Select restore source:"
echo "1 - Current Backups"
echo "2 - Zipped Archive"
read -p "Enter your choice (1 or 2): " RESTORE_CHOICE

# Set paths based on choice
if [ "$RESTORE_CHOICE" == "1" ]; then
    RESTORE_FROM_DIR=$BASE_DIR
elif [ "$RESTORE_CHOICE" == "2" ]; then
    echo "Enter the filename of the zipped archive (located in ${ARCHIVE_DIR}):"
    read -p "Filename: " ZIP_FILE
    RESTORE_FROM_DIR="${ARCHIVE_DIR}/${ZIP_FILE%.tar.gz}"
    mkdir -p "$RESTORE_FROM_DIR"
    tar -xzvf "${ARCHIVE_DIR}/${ZIP_FILE}" -C "$RESTORE_FROM_DIR"
else
    echo "Invalid choice. Exiting."
    exit 1
fi

# Prepare the full backup
xtrabackup --prepare --apply-log-only --target-dir="$RESTORE_FROM_DIR"

# Apply each incremental backup
for INC_BACKUP in $(ls -tr "${INCREMENTAL_DIR}"*); do
    echo "Applying incremental backup: $INC_BACKUP"
    xtrabackup --prepare --apply-log-only --target-dir="$RESTORE_FROM_DIR" --incremental-dir="$INC_BACKUP"
done

# Final preparation without --apply-log-only
xtrabackup --prepare --target-dir="$RESTORE_FROM_DIR"

# Ensure the data directory is empty
rm -rf "$DATA_DIR"/*

# Copy the backup data to MySQL data directory
xtrabackup --copy-back --target-dir="$RESTORE_FROM_DIR"

# Adjust file permissions
chown -R mysql:mysql "$DATA_DIR"

echo "Restore complete. Please start the MySQL server manually."
