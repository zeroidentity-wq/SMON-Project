#!/bin/bash

# Process Monitor Service
#
# This script monitors processes by checking their status in a MySQL database
# and restarts them when they are in alarm state.
# Designed for RedHat Linux environments.

# Set up logging
LOG_FILE="/var/log/monitor_service.log"

# Load configuration
CONFIG_FILE="config.ini"

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp - $level - $message" | tee -a "$LOG_FILE"
}

# Read configuration from config.ini
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

    # Debug output for validation
    log "DEBUG" "Parsed configuration values:"
    log "DEBUG" "DB_HOST='$DB_HOST'"
    log "DEBUG" "DB_USER='$DB_USER'"
    log "DEBUG" "DB_NAME='$DB_NAME'"
    log "DEBUG" "CHECK_INTERVAL='$CHECK_INTERVAL'"

    # Validate that we got all required values
    if [ -z "$DB_HOST" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASS" ] || [ -z "$DB_NAME" ] || \
       [ -z "$CHECK_INTERVAL" ] || [ -z "$MAX_RESTART_FAILURES" ] || [ -z "$CIRCUIT_RESET_TIME" ]; then
        log "ERROR" "Failed to parse one or more configuration values from $CONFIG_FILE"
        exit 1
    fi

    # Export variables for use in script
    export DB_HOST DB_USER DB_PASS DB_NAME
    export CHECK_INTERVAL MAX_RESTART_FAILURES CIRCUIT_RESET_TIME

    # Verify values are numeric where required
    if ! [[ "$CHECK_INTERVAL" =~ ^[0-9]+$ ]] || \
       ! [[ "$MAX_RESTART_FAILURES" =~ ^[0-9]+$ ]] || \
       ! [[ "$CIRCUIT_RESET_TIME" =~ ^[0-9]+$ ]]; then
        log "ERROR" "Invalid numeric values in configuration"
        exit 1
    fi
}

# Get processes in alarm state
get_alarm_processes() {
    mysql -N -u"$DB_USER" -p"$DB_PASS" -h"$DB_HOST" "$DB_NAME" <<EOF
    SELECT CONCAT(p.process_id, '|', p.process_name, '|', s.alarma, '|', s.sound, '|', s.notes)
    FROM STATUS_PROCESS s
    JOIN PROCESE p ON s.process_id = p.process_id
    WHERE s.alarma = 1 AND s.sound = 0;
EOF
}

# Get process-specific configuration
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

# Execute pre-restart command if configured
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

# Get restart strategy for a process
get_restart_strategy() {
    local process_name="$1"
    local strategy=$(get_process_config "$process_name" "restart_strategy" "auto")
    echo "$strategy"
}

# Restart a process or service
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
                    log "INFO" "RESTART LOG: Successfully restarted service: $process_name"
                    return 0
                fi
                ;;
                
            "process")
                # Direct process management
                if pkill "$process_name"; then
                    log "INFO" "RESTART LOG: Successfully killed process: $process_name"
                    sleep "$restart_delay"
                    if "$process_name" >/dev/null 2>&1 & then
                        log "INFO" "RESTART LOG: Successfully started process: $process_name"
                        return 0
                    fi
                fi
                ;;
                
            "auto"|*)
                # Try service first, then fall back to process
                if systemctl restart "$process_name" 2>/dev/null; then
                    log "INFO" "RESTART LOG: Successfully restarted service: $process_name"
                    return 0
                else
                    log "WARNING" "RESTART LOG: Failed to restart as service, trying as process"
                    if pkill "$process_name"; then
                        log "INFO" "RESTART LOG: Successfully killed process: $process_name"
                        sleep "$restart_delay"
                        if "$process_name" >/dev/null 2>&1 & then
                            log "INFO" "RESTART LOG: Successfully started process: $process_name"
                            return 0
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
    
    mysql -u"$DB_USER" -p"$DB_PASS" -h"$DB_HOST" "$DB_NAME" <<EOF
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

# Circuit breaker implementation
declare -A circuit_breaker
declare -A failure_counts
declare -A last_failure_times

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
        
        # Print initial circuit breaker status
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        printf "%s - DEBUG - Circuit breaker status for %s: Time remaining until reset: %s seconds\r" "$timestamp" "$process_name" "$time_remaining"
        
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
        failure_counts[$process_name]=0
    fi
}

# Main monitoring loop
main() {
    log "INFO" "Starting Process Monitor Service"
    
    # Read configuration
    read_config
    
    while true; do
        start_time=$(date +%s)
        
        # Get processes in alarm state
        while IFS='|' read -r process_id process_name alarma sound notes; do
            if [ -n "$process_id" ]; then
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
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        printf "%s - DEBUG - Next database check in %s seconds\r" "$timestamp" "$time_until_next_check"
        while [ $time_until_next_check -gt 0 ]; do
            sleep 1
            time_until_next_check=$((time_until_next_check - 1))
            printf "\033[2K\r%s - DEBUG - Next database check in %s seconds\r" "$timestamp" "$time_until_next_check"
        done
        echo "" # New line after countdown finishes
    done
}

# Start the monitor
main
