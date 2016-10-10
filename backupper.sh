#!/bin/bash

global_config_file="/usr/local/etc/backupper/global.conf"

function load_config() {
    if [ -f $global_config_file ]; then
        echo -e "Loading global config..."
        source $global_config_file
    else
        echo -e "[ERROR] Could not load global config file '$global_config_file'."
        exit 1
    fi

    if [ -f $CUSTOM_CONFIG_FILE ]; then
        echo -e "Loading custom config..."
        source $CUSTOM_CONFIG_FILE
    else
        echo -e "[ERROR] Could not load custom config file '$CUSTOM_CONFIG_FILE'."
        exit 1
    fi
}

function parse_config() {
    echo  -e "Parsing config..."
    dirs_to_backup_args=$(
        for dir in ${DIRS_TO_BACKUP}; do
            echo -e -n "${dir%/}/ "
        done
    )
    if [ $EXECUTE_RSYNC_WITH_SUDO == true ]; then
        rsync_flags_args=$(echo -e -n "$RSYNC_FLAGS $RSYNC_SUDO_FLAG")
    else
        rsync_flags_args=$RSYNC_FLAGS
    fi
    mysqldump_flags_args=$MYSQLDUMP_FLAGS
    dest_backups_dir=${DEST_HOST_BACKUPS_DIR%/}
    backup_name=$(date +$BACKUP_NAME_FORMAT)
    dest_logs_dir=${LOG_FOLDER%/}
    log_file=$dest_logs_dir/$backup_name.log
}

function check_config() {
    echo  -e "Checking config..."
    if [ -z "${BACKUP_NAME_FORMAT}" ]; then
        echo -e "[ERROR] Variable 'BACKUP_NAME_FORMAT' is empty or unset."
        backup_error=1
    fi
    if [ -z "${CUSTOM_CONFIG_FILE}" ]; then
        echo -e "[ERROR] Variable 'CUSTOM_CONFIG_FILE' is empty or unset."
        backup_error=1
    fi
    if [ -z "${DEST_HOST_HOSTNAME}" ]; then
        echo -e "[ERROR] Variable 'DEST_HOST_HOSTNAME' is empty or unset."
        backup_error=1
    fi
    if [ -z "${DEST_HOST_PORT}" ]; then
        echo -e "[ERROR] Variable 'DEST_HOST_PORT' is empty or unset."
        backup_error=1
    fi
    if [ -z "${DEST_HOST_USER}" ]; then
        echo -e "[ERROR] Variable 'DEST_HOST_USER' is empty or unset."
        backup_error=1
    fi
    if [ -z "${DEST_HOST_BACKUPS_DIR}" ]; then
        echo -e "[ERROR] Variable 'DEST_HOST_BACKUPS_DIR' is empty or unset."
        backup_error=1
    fi
    if [ -z "${NUMBER_OF_BACKUPS_TO_KEEP}" ]; then
        echo -e "[ERROR] Variable 'NUMBER_OF_BACKUPS_TO_KEEP' is empty or unset."
        backup_error=1
    fi
    if [ -z "${LOG_FOLDER}" ]; then
        echo -e "[ERROR] Variable 'LOG_FOLDER' is empty or unset."
        backup_error=1
    fi
    if [ -z "${NUMBER_OF_LOGS_TO_KEEP}" ]; then
        echo -e "[ERROR] Variable 'NUMBER_OF_LOGS_TO_KEEP' is empty or unset."
        backup_error=1
    fi
    if [ -z "${EXECUTE_RSYNC_WITH_SUDO}" ]; then
        echo -e "[ERROR] Variable 'EXECUTE_RSYNC_WITH_SUDO' is empty or unset."
        backup_error=1
    fi
    if [ ! -z "$MYSQL_DATABASES" ]; then
        if [ -z "${MYSQL_USER}" ]; then
            echo -e "[ERROR] Variable 'MYSQL_USER' is empty or unset."
            backup_error=1
        fi
        if [ -z "${MYSQL_PASSWORD}" ]; then
            echo -e "[ERROR] Variable 'MYSQL_PASSWORD' is empty or unset."
            backup_error=1
        fi
    fi
}

function create_backup_dir() {
    ssh -p $DEST_HOST_PORT $DEST_HOST_USER@$DEST_HOST_HOSTNAME \
        "mkdir --parents $dest_backups_dir/$backup_name"
    create_backup_dir_exit_value=$?
    if [ $create_backup_dir_exit_value -ne 0 ]; then
        echo -e "[ERROR] Error creating backup dir '$backup_name'."
        backup_error=1
    else
        echo -e "Backup dir '$backup_name' created successfully."
    fi
}

function send_backup() {
    echo -e "Sending backup '$backup_name' to '$DEST_HOST_HOSTNAME'."
    echo -e "-- Begin rsync --"
    rsync $rsync_flags_args -e "ssh -p $DEST_HOST_PORT" $dirs_to_backup_args \
        $DEST_HOST_USER@$DEST_HOST_HOSTNAME:$dest_backups_dir/$LAST_RSYNC_BACKUP_FOLDER/
    rsync_exit_value=$?
    echo -e "-- End rsync --"
    if [ $rsync_exit_value -eq 0 ]; then
        echo -e "Backup '$backup_name' sent successfully."
        ssh -p $DEST_HOST_PORT $DEST_HOST_USER@$DEST_HOST_HOSTNAME \
            "mkdir --parents $dest_backups_dir/$backup_name/files;\
                cp -al $dest_backups_dir/$LAST_RSYNC_BACKUP_FOLDER/* \
                $dest_backups_dir/$backup_name/files/"
    else
        backup_error=1
    fi
}

function get_rsync_error() {
    local exit_value=$1
    if [ $exit_value -eq 0 ]; then
        echo "Success"
    elif [ $exit_value -eq 1 ]; then
        echo "Syntax or usage error"
    elif [ $exit_value -eq 2 ]; then
        echo "Protocol incompatibility"
    elif [ $exit_value -eq 3 ]; then
        echo "Errors selecting input/output files, dirs"
    elif [ $exit_value -eq 4 ]; then
        echo "Requested  action not supported: an attempt was made to \
            manipulate 64-bit files on a platform that cannot support them; \
            or an option was specified that supported by the client and not \
            by the server."
    elif [ $exit_value -eq 5 ]; then
        echo "Error starting client-server protocol"
    elif [ $exit_value -eq 6 ]; then
        echo "Daemon unable to append to log-file"
    elif [ $exit_value -eq 10 ]; then
        echo "Error in socket I/O"
    elif [ $exit_value -eq 11 ]; then
        echo "Error in file I/O"
    elif [ $exit_value -eq 12 ]; then
        echo "Error in rsync protocol data stream"
    elif [ $exit_value -eq 13 ]; then
        echo "Errors with program diagnostics"
    elif [ $exit_value -eq 14 ]; then
        echo "Error in IPC code"
    elif [ $exit_value -eq 20 ]; then
        echo "Received SIGUSR1 or SIGINT"
    elif [ $exit_value -eq 21 ]; then
        echo "Some error echoed by waitpid()"
    elif [ $exit_value -eq 22 ]; then
        echo "Error allocating core memory buffers"
    elif [ $exit_value -eq 23 ]; then
        echo "Partial transfer due to error"
    elif [ $exit_value -eq 24 ]; then
        echo "Partial transfer due to vanished source files"
    elif [ $exit_value -eq 25 ]; then
        echo "The --max-delete limit stopped deletions"
    elif [ $exit_value -eq 30 ]; then
        echo "Timeout in data send/receive"
    elif [ $exit_value -eq 35 ]; then
        echo "Timeout waiting for daemon connection"
    else
        echo "Returned exit value: $exit_value"
    fi
}

function remove_old_backups() {
    local backups
    backups=($(ssh -p $DEST_HOST_PORT $DEST_HOST_USER@$DEST_HOST_HOSTNAME \
        "ls -1t $dest_backups_dir/ --ignore='$LAST_RSYNC_BACKUP_FOLDER'"))
    if [ $? -ne 0 ]; then
        echo -e "[ERROR] Error retrieving list of backups from remote host!"
        echo -e "Old backups will not be deleted."
        backup_error=1
        return
    fi
    local backups_to_remove=(${backups[@]:$NUMBER_OF_BACKUPS_TO_KEEP})
    if [ ${#backups_to_remove[@]} -eq 0 ]; then
        echo -e "There are no old backups to remove."
        return
    fi
    local rm_args=$(
        for backup in ${backups_to_remove[@]}; do
            echo -e -n "$dest_backups_dir/$backup "
        done
    )
    echo -e "Removing ${#backups_to_remove[@]} old backups: ${backups_to_remove[@]}"
    ssh -p $DEST_HOST_PORT $DEST_HOST_USER@$DEST_HOST_HOSTNAME \
        "rm -rf $rm_args"
    if [ $? -ne 0 ]; then
        echo -e "[ERROR] Error removing old backups!"
        backup_error=1
    else
        echo -e "Old backups removed successfully."
    fi
}

function remove_old_logs() {
    local logs
    logs=($(ls -1t $dest_logs_dir/))
    if [ $? -ne 0 ]; then
        echo -e "[ERROR] Error retrieving list of logs!"
        echo -e "Old logs will not be deleted."
        backup_error=1
        return
    fi
    local logs_to_remove=(${logs[@]:$NUMBER_OF_LOGS_TO_KEEP})
    if [ ${#logs_to_remove[@]} -eq 0 ]; then
        echo -e "There are no old logs to remove."
        return
    fi
    local rm_args=$(
        for log in ${logs_to_remove[@]}; do
            echo -e -n "$dest_logs_dir/$log "
        done
    )
    echo -e "Removing ${#logs_to_remove[@]} old logs: ${logs_to_remove[@]}"
    rm -rf $rm_args
    if [ $? -ne 0 ]; then
        echo -e "[ERROR] Error removing old logs!"
        backup_error=1
    else
        echo -e "Old logs removed successfully."
    fi
}

function send_mail() {
    if [ -z "$MAIL_TO" ]; then
        echo -e "There are no email addresses to send log."
    else
        echo -e "Sending email log to '$MAIL_TO'..."
        if [ $backup_error -eq 0 ]; then
            result="(Success)"
        else
            result="(Fail)"
        fi
        local subject="$result Backup '$backup_name' from '$(hostname -f)'"
        mail -s "$subject" $MAIL_TO < "${log_file}"
    fi
}

function backup_mysql_databases() {
    echo -e "Creating mysql dabatases directory..."
    ssh -p $DEST_HOST_PORT $DEST_HOST_USER@$DEST_HOST_HOSTNAME \
        "mkdir --parents $dest_backups_dir/$backup_name/mysql_databases"
    for database in $MYSQL_DATABASES; do
        echo -e "Sending backup of '$database' database to '$DEST_HOST_HOSTNAME'."
        echo -e "-- Begin mysqldump --"
        mysqldump $mysqldump_flags_args -u $MYSQL_USER \
            --password=$MYSQL_PASSWORD $database | gzip -9 -c | \
            ssh -p $DEST_HOST_PORT $DEST_HOST_USER@$DEST_HOST_HOSTNAME \
            "cat > $dest_backups_dir/$backup_name/mysql_databases/$database.sql.gz"
        echo -e "-- End mysqldump --"
    done
}

function send_log_to_dest() {
    echo -e "Sending log to destination host..."
    cat $log_file | ssh -p $DEST_HOST_PORT $DEST_HOST_USER@$DEST_HOST_HOSTNAME \
        "cat > $dest_backups_dir/$backup_name/$backup_name.log"
    if [ $? -ne 0 ]; then
        echo -e "[ERROR] Error sending log to destination host!"
        backup_error=1
    else
        echo -e "Log sent successfully to destination host."
    fi
}

function prepare_log() {
    if [ ! -d $dest_logs_dir ]; then
        echo -e "Creating logs foler '$dest_logs_dir'."
        mkdir --parents $dest_logs_dir
    fi
    exec > $log_file 2>&1
}

## MAIN BEGIN ##

backup_error=0
load_config
check_config
parse_config
prepare_log
create_backup_dir
if [ $create_backup_dir_exit_value -ne 0 ]; then
    send_mail
    exit 1
fi
if [ -z "$DIRS_TO_BACKUP" ]; then
    echo -e "There are no dirs to backup!"
else
    send_backup
    if [ $rsync_exit_value -ne 0 ]; then
        rsync_error_message=$(get_rsync_error $rsync_exit_value)
        echo -e "[ERROR] rsync fail ($rsync_exit_value): $rsync_error_message"
    fi
fi
if [ -z "$MYSQL_DATABASES" ]; then
    echo -e "There are no mysql databases to backup."
else
    backup_mysql_databases
fi
if [ $backup_error -eq 0 ]; then
    remove_old_backups
    remove_old_logs
else
    echo -e "Backup failed! Old backups and logs are not deleted!"
fi
send_mail
send_log_to_dest
exit $backup_error

## MAIN END ##
