#!/bin/bash

# Process Monitor Service
#
# This script monitors processes by checking their status in a MySQL database
# and restarts them when they are in alarm state.

# Set up logging
LOG_FILE="/var/log/monitor_service.log"

# Load configuration
CONFIG_FILE="config.ini"

# Temporary MySQL config file
MYSQL_TEMP_CONFIG=$(mktemp)

###############################################################################
# Function: create_mysql_config
# Purpose:  Create a temporary MySQL client config file with credentials.
#           This avoids passing credentials on the command line.
#           Function to create MySQL config file.
###############################################################################

create_mysql_config() {
    # Ensure the temp file exists and is empty
    > "$MYSQL_TEMP_CONFIG"

    # Set secure permissions
    chmod 600 "$MYSQL_TEMP_CONFIG"

    # Write MySQL configuration
    cat > "$MYSQL_TEMP_CONFIG" << EOF
[client]
host=$DB_HOST
user=$DB_USER
password=$DB_PASS
database=$DB_NAME
EOF
}

###############################################################################
# Function: cleanup_mysql_config
# Purpose:  Remove the temporary MySQL config file on script exit.
#           This ensures sensitive information is not left on disk.
#           Function to clean up MySQL config file.
###############################################################################

cleanup_mysql_config() {
    if [ -f "$MYSQL_TEMP_CONFIG" ]; then
        rm -f "$MYSQL_TEMP_CONFIG"
    fi
}

# Set up trap to clean up on exit
trap cleanup_mysql_config EXIT

###############################################################################
# Function: check_log_rotation
# Purpose:  Determine if the log file exceeds the configured size and needs rotation.
# Returns:  0 if rotation needed, 1 otherwise.
###############################################################################

check_log_rotation() {
    # If log file doesn't exist, no rotation needed
    if [ ! -f "$LOG_FILE" ]; then
        return 1
    fi

    # Get file size in KB
    local file_size=$(du -k "$LOG_FILE" | cut -f1)

    # Check if file size exceeds the maximum
    if [ "$file_size" -ge "$MAX_LOG_SIZE" ]; then
        return 0  # Rotation needed
    else
        return 1  # No rotation needed
    fi
}

###############################################################################
# Function: rotate_logs
# Purpose:  Rotate log files, keeping only the configured number of backups.
###############################################################################

rotate_logs() {
    # If log file doesn't exist, nothing to rotate
    if [ ! -f "$LOG_FILE" ]; then
        return
    fi

    # Remove oldest log file if it exists
    if [ -f "${LOG_FILE}.${LOG_FILES_TO_KEEP}" ]; then
        rm -f "${LOG_FILE}.${LOG_FILES_TO_KEEP}"
    fi

    # Rotate existing log files
    for i in $(seq $((LOG_FILES_TO_KEEP - 1)) -1 1); do
        if [ -f "${LOG_FILE}.$i" ]; then
            mv "${LOG_FILE}.$i" "${LOG_FILE}.$((i + 1))"
        fi
    done

    # Rotate current log file
    if [ -f "$LOG_FILE" ]; then
        mv "$LOG_FILE" "${LOG_FILE}.1"
    fi

    # Create new empty log file
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"

    # Log rotation event to the new log file
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp - INFO - Log file rotated, previous log saved as ${LOG_FILE}.1" >> "$LOG_FILE"
}

###############################################################################
# Function: log
# Purpose:  Write a timestamped log message, rotating logs if needed.
###############################################################################

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Check if log rotation is needed
    if check_log_rotation; then
        rotate_logs
    fi

    # Format: YYYY-MM-DD HH:MM:SS [LEVEL] - Message
    echo "$timestamp  [$level] - $message" | tee -a "$LOG_FILE"
    
    # If level is ERROR or higher, also log to syslog
    if [[ "$level" == "ERROR" || "$level" == "CRITICAL" ]]; then
        logger -p daemon.err "$timestamp [$level] $message"
    fi
}

###############################################################################
# Function: read_config
# Purpose:  Read configuration from config.ini
#           Parse the config.ini file and export required variables.
#           Validates presence and numeric type for critical settings.
###############################################################################

read_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log "ERROR" "Configuration file $CONFIG_FILE not found"
        exit 1
    fi

    # Parse database section
    DB_HOST=$(sed -n '/^\[database\]/,/^\[/p' "$CONFIG_FILE" | grep "^host[[:space:]]*=" | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    DB_USER=$(sed -n '/^\[database\]/,/^\[/p' "$CONFIG_FILE" | grep "^user[[:space:]]*=" | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    DB_PASS=$(sed -n '/^\[database\]/,/^\[/p' "$CONFIG_FILE" | grep "^password[[:space:]]*=" | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    DB_NAME=$(sed -n '/^\[database\]/,/^\[/p' "$CONFIG_FILE" | grep "^database[[:space:]]*=" | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # Parse monitor section
    CHECK_INTERVAL=$(sed -n '/^\[monitor\]/,/^\[/p' "$CONFIG_FILE" | grep "^check_interval[[:space:]]*=" | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    MAX_RESTART_FAILURES=$(sed -n '/^\[monitor\]/,/^\[/p' "$CONFIG_FILE" | grep "^max_restart_failures[[:space:]]*=" | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    CIRCUIT_RESET_TIME=$(sed -n '/^\[monitor\]/,/^\[/p' "$CONFIG_FILE" | grep "^circuit_reset_time[[:space:]]*=" | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # Parse logging section
    MAX_LOG_SIZE=$(sed -n '/^\[logging\]/,/^\[/p' "$CONFIG_FILE" | grep "^max_log_size[[:space:]]*=" | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    LOG_FILES_TO_KEEP=$(sed -n '/^\[logging\]/,/^\[/p' "$CONFIG_FILE" | grep "^log_files_to_keep[[:space:]]*=" | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # Set defaults for logging if not specified
    MAX_LOG_SIZE=${MAX_LOG_SIZE:-5120}  # Default to 5MB (in KB)
    LOG_FILES_TO_KEEP=${LOG_FILES_TO_KEEP:-5}  # Default to keeping 5 log files

    # Debug output for validation
    log "DEBUG" "Parsed configuration values:"
    log "DEBUG" "DB_HOST='$DB_HOST'"
    log "DEBUG" "DB_USER='$DB_USER'"
    log "DEBUG" "DB_NAME='$DB_NAME'"
    log "DEBUG" "CHECK_INTERVAL='$CHECK_INTERVAL'"
    log "DEBUG" "MAX_LOG_SIZE='$MAX_LOG_SIZE'"
    log "DEBUG" "LOG_FILES_TO_KEEP='$LOG_FILES_TO_KEEP'"

    # Validate that we got all required values
    if [ -z "$DB_HOST" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASS" ] || [ -z "$DB_NAME" ] || \
       [ -z "$CHECK_INTERVAL" ] || [ -z "$MAX_RESTART_FAILURES" ] || [ -z "$CIRCUIT_RESET_TIME" ]; then
        log "ERROR" "Failed to parse one or more configuration values from $CONFIG_FILE"
        exit 1
    fi

    # Export variables for use in script
    export DB_HOST DB_USER DB_PASS DB_NAME
    export CHECK_INTERVAL MAX_RESTART_FAILURES CIRCUIT_RESET_TIME
    export MAX_LOG_SIZE LOG_FILES_TO_KEEP

    # Verify values are numeric where required
    if ! [[ "$CHECK_INTERVAL" =~ ^[0-9]+$ ]] || \
       ! [[ "$MAX_RESTART_FAILURES" =~ ^[0-9]+$ ]] || \
       ! [[ "$CIRCUIT_RESET_TIME" =~ ^[0-9]+$ ]] || \
       ! [[ "$MAX_LOG_SIZE" =~ ^[0-9]+$ ]] || \
       ! [[ "$LOG_FILES_TO_KEEP" =~ ^[0-9]+$ ]]; then
        log "ERROR" "Invalid numeric values in configuration"
        exit 1
    fi
}

###############################################################################
# Function: get_alarm_processes
# Purpose:  Query the database for processes in alarm state (alarma=1, sound=0)
#           Get processes in alarm state
# Output:   Each line: process_id|process_name|alarma|sound|notes
###############################################################################

get_alarm_processes() {
    # Use --defaults-file instead of passing credentials on command line
    # Added options to optimize connection handling:
    # --connect-timeout=5: Limit connection time to 5 seconds
    # --quick: Reduce memory usage and speed up query execution
    # --compress: Reduce network traffic
    # --reconnect=FALSE: Prevent automatic reconnection attempts
    mysql --defaults-file="$MYSQL_TEMP_CONFIG" --connect-timeout=5 --quick --compress --reconnect=FALSE -N <<EOF
    SELECT CONCAT(p.process_id, '|', p.process_name, '|', s.alarma, '|', s.sound, '|', s.notes)
    FROM STATUS_PROCESS s
    JOIN PROCESE p ON s.process_id = p.process_id
    WHERE s.alarma = 1 AND s.sound = 0;
EOF
}

###############################################################################
# Function: get_process_config
# Purpose:  Retrieve a process-specific configuration value, falling back to
#           [process.default] or a provided default if not found.
#           Get process-specific configuration
# Arguments:
#   $1 - process name
#   $2 - parameter name
#   $3 - default value (optional)
###############################################################################

get_process_config() {
    local process_name="$1"
    local param="$2"
    local default_value="$3"

    # Try to get process-specific setting
    local value=$(sed -n "/^\[process.$process_name\]/,/^\[/p" "$CONFIG_FILE" | grep "^$param[[:space:]]*=" | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # If not found, try default process settings
    if [ -z "$value" ]; then
        value=$(sed -n "/^\[process.default\]/,/^\[/p" "$CONFIG_FILE" | grep "^$param[[:space:]]*=" | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    fi

    # If still not found, use provided default
    echo "${value:-$default_value}"
}


###############################################################################
# Function: execute_pre_restart
# Purpose:  Run a pre-restart command for a process if configured.
# Returns:  0 on success, 1 on failure.
###############################################################################

execute_pre_restart() {
    local process_name="$1"
    local pre_command=$(get_process_config "$process_name" "pre_restart_command" "")

    if [ -n "$pre_command" ]; then
        log "INFO" "Executing pre-restart command for $process_name: $pre_command"
        if ! eval "$pre_command"; then
            log "ERROR" "Pre-restart command failed for $process_name"
            return 1
        fi
    fi
    return 0
}

###############################################################################
# Function: perform_health_check
# Purpose:  Run a health check command for a process, retrying until timeout.
#           Perform health check after restart
# Returns:  0 if health check passes, 1 if it fails after timeout.
###############################################################################

perform_health_check() {
    local process_name="$1"
    local health_command=$(get_process_config "$process_name" "health_check_command" "")
    local health_timeout=$(get_process_config "$process_name" "health_check_timeout" "5")

    # If no health check command is configured, assume success
    if [ -z "$health_command" ]; then
        log "INFO" "No health check command configured for $process_name, assuming success"
        return 0
    fi

    # Replace %s with process name if present in the command
    health_command=$(echo "$health_command" | sed "s/%s/$process_name/g")

    log "INFO" "Performing health check for $process_name: $health_command"

    # Try health check with timeout
    local start_time=$(date +%s)
    local end_time=$((start_time + health_timeout))
    local current_time=$start_time
    local success=false
    local attempt=1

    while [ $current_time -lt $end_time ]; do
        if eval "$health_command" >/dev/null 2>&1; then
            success=true
            break
        fi

        # Print progress for user, but not to logs
        # Use a format that won't be captured by system logs and shows actual seconds
        printf "\rHealth check attempt failed for %s, retrying in 1 second... (attempt %d)" "$process_name" "$attempt"
        sleep 1
        current_time=$(date +%s)
        attempt=$((attempt + 1))
    done
    echo ""  # Print a newline after all attempts

    if [ "$success" = true ]; then
        log "INFO" "Health check passed for $process_name"
        return 0
    else
        log "ERROR" "Health check failed for $process_name after $health_timeout seconds"
        return 1
    fi
}

###############################################################################
# Function: get_restart_strategy
# Purpose:  Get the restart strategy for a process (service, process, custom, auto).
###############################################################################

get_restart_strategy() {
    local process_name="$1"
    local strategy=$(get_process_config "$process_name" "restart_strategy" "auto")
    echo "$strategy"
}

###############################################################################
# Function: restart_process
# Purpose:  Attempt to restart a process using its configured strategy.
#           Handles service, process, custom, and auto strategies.
#           Retries up to max_attempts with delay.
# Returns:  0 on success, 1 on failure.
###############################################################################

restart_process() {
    local process_name="$1"
    local strategy=$(get_restart_strategy "$process_name")
    local max_attempts=$(get_process_config "$process_name" "max_attempts" "2")
    local restart_delay=$(get_process_config "$process_name" "restart_delay" "2")

    log "INFO" "RESTART LOG: Beginning restart procedure for $process_name (strategy: $strategy)"

    # Execute pre-restart command if any
    if ! execute_pre_restart "$process_name"; then
        return 1
    fi

    local attempt=1
    while [ $attempt -le "$max_attempts" ]; do
        log "INFO" "Attempting restart ($attempt of $max_attempts) for $process_name"

        case "$strategy" in
            "service")
                # Try systemd service restart
                if systemctl restart "$process_name" 2>/dev/null; then
                    log "INFO" "RESTART LOG: Service restart command executed for: $process_name"
                    # Perform health check after restart
                    if perform_health_check "$process_name"; then
                        log "INFO" "RESTART LOG: Successfully restarted and verified service: $process_name"
                        return 0
                    else
                        log "ERROR" "RESTART LOG: Service restart command succeeded but health check failed for: $process_name"
                    fi
                fi
                ;;

            "process")
                # Direct process management : kill and restart
                if pkill "$process_name"; then
                    log "INFO" "RESTART LOG: Successfully killed process: $process_name"
                    sleep "$restart_delay"
                    if "$process_name" >/dev/null 2>&1 & then
                        log "INFO" "RESTART LOG: Process start command executed for: $process_name"
                        # Perform health check after restart
                        if perform_health_check "$process_name"; then
                            log "INFO" "RESTART LOG: Successfully started and verified process: $process_name"
                            return 0
                        else
                            log "ERROR" "RESTART LOG: Process start command succeeded but health check failed for: $process_name"
                        fi
                    fi
                fi
                ;;

            "custom")
                # Get custom restart command
                local restart_command=$(get_process_config "$process_name" "restart_command" "")

                # Check if restart command is configured
                if [ -z "$restart_command" ]; then
                    log "ERROR" "RESTART LOG: No restart command configured for $process_name with custom strategy"
                    return 1
                fi

                # Replace %s with process name if present in the command
                restart_command=$(echo "$restart_command" | sed "s/%s/$process_name/g")

                log "INFO" "RESTART LOG: Executing custom restart command for $process_name: $restart_command"

                # Execute custom restart command
                if eval "$restart_command" >/dev/null 2>&1; then
                    log "INFO" "RESTART LOG: Custom restart command executed for: $process_name"
                    # Perform health check after restart
                    if perform_health_check "$process_name"; then
                        log "INFO" "RESTART LOG: Successfully restarted and verified process: $process_name"
                        return 0
                    else
                        log "ERROR" "RESTART LOG: Custom restart command succeeded but health check failed for: $process_name"
                    fi
                else
                    log "ERROR" "RESTART LOG: Custom restart command failed for: $process_name"
                fi
                ;;

            "auto"|*)
                # Try service first, then fall back to process
                if systemctl restart "$process_name" 2>/dev/null; then
                    log "INFO" "RESTART LOG: Service restart command executed for: $process_name"
                    # Perform health check after restart
                    if perform_health_check "$process_name"; then
                        log "INFO" "RESTART LOG: Successfully restarted and verified service: $process_name"
                        return 0
                    else
                        log "ERROR" "RESTART LOG: Service restart command succeeded but health check failed for: $process_name"
                    fi
                else
                    log "WARNING" "RESTART LOG: Failed to restart as service, trying as process"
                    if pkill "$process_name"; then
                        log "INFO" "RESTART LOG: Successfully killed process: $process_name"
                        sleep "$restart_delay"
                        if "$process_name" >/dev/null 2>&1 & then
                            log "INFO" "RESTART LOG: Process start command executed for: $process_name"
                            # Perform health check after restart
                            if perform_health_check "$process_name"; then
                                log "INFO" "RESTART LOG: Successfully started and verified process: $process_name"
                                return 0
                            else
                                log "ERROR" "RESTART LOG: Process start command succeeded but health check failed for: $process_name"
                            fi
                        fi
                    fi
                fi
                ;;
        esac

        log "ERROR" "RESTART LOG: Attempt $attempt failed for $process_name"
        sleep "$restart_delay"
        attempt=$((attempt + 1))
    done

    log "ERROR" "RESTART LOG: All restart attempts failed for $process_name"
    return 1
}

# Update alarm status in database
update_alarm_status() {
    local process_id="$1"
    local current_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    # TO DO: FUNCTION WILL BE LATER DELETED, it's used only for testing purposes. The new user will have only SELECT permissions.
    # Use --defaults-file instead of passing credentials on command line
    # Added options to optimize connection handling:
    # --connect-timeout=5: Limit connection time to 5 seconds
    # --quick: Reduce memory usage and speed up query execution
    # --compress: Reduce network traffic
    # --reconnect=FALSE: Prevent automatic reconnection attempts
    mysql --defaults-file="$MYSQL_TEMP_CONFIG" --connect-timeout=5 --quick --compress --reconnect=FALSE <<EOF
    UPDATE STATUS_PROCESS 
    SET alarma = 0, notes = CONCAT(notes, ' - Restarted at $current_time')
    WHERE process_id = $process_id;
EOF

    if [ $? -eq 0 ]; then
        log "INFO" "DB UPDATE LOG: Successfully updated alarm status for process_id: $process_id"
        return 0
    else
        log "ERROR" "DB UPDATE LOG: Failed to update alarm status for process_id: $process_id"
        return 1
    fi
}

###############################################################################
# Circuit Breaker Pattern
# Purpose:  Prevents repeated restart attempts for failing processes.
#           Opens circuit after N failures, resets after a cooldown.
###############################################################################

declare -A circuit_breaker
declare -A failure_counts
declare -A last_failure_times

###############################################################################
# Function: check_circuit_breaker
# Purpose:  Check if the circuit breaker is open for a process.
#           If open, skip restart until reset time has elapsed.
# Returns:  0 if closed, 1 if open.
###############################################################################

check_circuit_breaker() {
    local process_name="$1"
    local current_time=$(date +%s)

    # Initialize if not exists
    if [ -z "${circuit_breaker[$process_name]}" ]; then
        circuit_breaker[$process_name]="closed"
        failure_counts[$process_name]=0
        last_failure_times[$process_name]=$current_time
    fi

    # Check if circuit breaker is open
    if [ "${circuit_breaker[$process_name]}" = "open" ]; then
        local time_diff=$((current_time - ${last_failure_times[$process_name]}))
        local time_remaining=$((CIRCUIT_RESET_TIME - time_diff))

        # Print initial circuit breaker status without logging to system logs
        printf "Circuit breaker status for %s: Time remaining until reset: %s seconds\r" "$process_name" "$time_remaining"

        if [ $time_diff -ge "$CIRCUIT_RESET_TIME" ]; then
            echo "" # New line before the next message
            circuit_breaker[$process_name]="closed"
            failure_counts[$process_name]=0
            log "INFO" "Circuit breaker reset for $process_name"
            return 0
        else
            echo "" # New line before the next message
            log "WARNING" "Circuit breaker open for $process_name. Skipping restart."
            return 1
        fi
    fi

    return 0
}

###############################################################################
# Function: update_circuit_breaker
# Purpose:  Update the circuit breaker state after a restart attempt.
#           Opens the circuit if failures exceed threshold.
###############################################################################
update_circuit_breaker() {
    local process_name="$1"
    local success="$2"
    local current_time=$(date +%s)

    if [ "$success" = "false" ]; then
        failure_counts[$process_name]=$((failure_counts[$process_name] + 1))
        last_failure_times[$process_name]=$current_time

        if [ ${failure_counts[$process_name]} -ge "$MAX_RESTART_FAILURES" ]; then
            circuit_breaker[$process_name]="open"
            log "WARNING" "Circuit breaker opened for $process_name after ${failure_counts[$process_name]} failures"
        fi
    else
        # Reset failure count on success
        failure_counts[$process_name]=0
        log "INFO" "Reset failure count for process: $process_name after successful restart"
    fi
}

###############################################################################
# Function: main
# Purpose:  Main monitoring loop. Checks for alarmed processes, attempts restarts,
#           updates database and circuit breaker state, and waits for next interval.
###############################################################################
# Main monitoring loop
main() {
    log "INFO" "Starting Process Monitor Service"

    # Read configuration
    read_config

    # Create MySQL config file with the loaded credentials
    create_mysql_config

    while true; do
        start_time=$(date +%s)

        # Get processes in alarm state
        while IFS='|' read -r process_id process_name alarma sound notes; do
            if [ -n "$process_id" ]; then
                echo " " # Print a space to avoid overwriting the previous line
                log "INFO" "Found process in alarm: $process_name (ID: $process_id)"

                # Check circuit breaker
                if check_circuit_breaker "$process_name"; then
                    # Attempt restart
                    if restart_process "$process_name"; then
                        update_alarm_status "$process_id"
                        update_circuit_breaker "$process_name" "true"
                        log "INFO" "Successfully handled alarm for $process_name"
                    else
                        update_circuit_breaker "$process_name" "false"
                        log "ERROR" "Failed to handle alarm for $process_name"
                    fi
                fi
            fi
        done < <(get_alarm_processes)

        # Calculate and show countdown until next check
        time_until_next_check=$CHECK_INTERVAL
        # Use a format that won't be captured by system logs
        printf "Next database check in %s seconds\r" "$time_until_next_check"
        while [ $time_until_next_check -gt 0 ]; do
            sleep 1
            time_until_next_check=$((time_until_next_check - 1))
            printf "\033[2K\rNext database check in %s seconds\r" "$time_until_next_check"
        done
        echo "" # New line after countdown finishes
    done
}

# Start the monitor
main
