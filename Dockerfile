FROM percona/percona-xtrabackup:latest

USER root

# Copy the backup script into the container
COPY backup_script.sh /usr/local/bin/backup_script.sh
COPY restore_script.sh /usr/local/bin/restore_script.sh

# Make the backup script executable
RUN chmod +x /usr/local/bin/backup_script.sh
RUN chmod +x /usr/local/bin/restore_script.sh

USER 1001

# Set the entrypoint to the backup script
ENTRYPOINT ["/usr/local/bin/backup_script.sh"]