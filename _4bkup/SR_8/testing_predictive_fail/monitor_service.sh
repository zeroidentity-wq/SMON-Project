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

# Temporary MySQL config file
MYSQL_TEMP_CONFIG=$(mktemp)

# Function to create MySQL config file
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

# Function to clean up temporary MySQL config file
cleanup_mysql_config() {
    if [ -f "$MYSQL_TEMP_CONFIG" ]; then
        rm -f "$MYSQL_TEMP_CONFIG"
    fi
}

# Set up trap to clean up on exit
trap cleanup_mysql_config EXIT

# Function to check if log rotation is needed
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

# Function to rotate log files
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

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Check if log rotation is needed
    if check_log_rotation; then
        rotate_logs
    fi

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

    # Parse logging section
    MAX_LOG_SIZE=$(sed -n '/^\[logging\]/,/^\[/p' "$CONFIG_FILE" | grep "^max_log_size[[:space:]]*=" | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    LOG_FILES_TO_KEEP=$(sed -n '/^\[logging\]/,/^\[/p' "$CONFIG_FILE" | grep "^log_files_to_keep[[:space:]]*=" | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # Parse predictive section
    PREDICTIVE_ENABLED=$(sed -n '/^\[predictive\]/,/^\[/p' "$CONFIG_FILE" | grep "^enabled[[:space:]]*=" | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    COLLECTION_INTERVAL=$(sed -n '/^\[predictive\]/,/^\[/p' "$CONFIG_FILE" | grep "^collection_interval[[:space:]]*=" | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    HISTORY_RETENTION_DAYS=$(sed -n '/^\[predictive\]/,/^\[/p' "$CONFIG_FILE" | grep "^history_retention_days[[:space:]]*=" | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    CONFIDENCE_THRESHOLD=$(sed -n '/^\[predictive\]/,/^\[/p' "$CONFIG_FILE" | grep "^confidence_threshold[[:space:]]*=" | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    MIN_DATA_POINTS=$(sed -n '/^\[predictive\]/,/^\[/p' "$CONFIG_FILE" | grep "^min_data_points[[:space:]]*=" | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    RESOURCE_MONITORING=$(sed -n '/^\[predictive\]/,/^\[/p' "$CONFIG_FILE" | grep "^resource_monitoring[[:space:]]*=" | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # Set defaults for logging if not specified
    MAX_LOG_SIZE=${MAX_LOG_SIZE:-5120}  # Default to 5MB (in KB)
    LOG_FILES_TO_KEEP=${LOG_FILES_TO_KEEP:-5}  # Default to keeping 5 log files

    # Set defaults for predictive if not specified
    PREDICTIVE_ENABLED=${PREDICTIVE_ENABLED:-0}  # Default to disabled
    COLLECTION_INTERVAL=${COLLECTION_INTERVAL:-60}  # Default to 60 seconds
    HISTORY_RETENTION_DAYS=${HISTORY_RETENTION_DAYS:-30}  # Default to 30 days
    CONFIDENCE_THRESHOLD=${CONFIDENCE_THRESHOLD:-0.7}  # Default to 0.7
    MIN_DATA_POINTS=${MIN_DATA_POINTS:-10}  # Default to 10 data points
    RESOURCE_MONITORING=${RESOURCE_MONITORING:-0}  # Default to disabled

    # Debug output for validation
    log "DEBUG" "Parsed configuration values:"
    log "DEBUG" "DB_HOST='$DB_HOST'"
    log "DEBUG" "DB_USER='$DB_USER'"
    log "DEBUG" "DB_NAME='$DB_NAME'"
    log "DEBUG" "CHECK_INTERVAL='$CHECK_INTERVAL'"
    log "DEBUG" "MAX_LOG_SIZE='$MAX_LOG_SIZE'"
    log "DEBUG" "LOG_FILES_TO_KEEP='$LOG_FILES_TO_KEEP'"
    log "DEBUG" "PREDICTIVE_ENABLED='$PREDICTIVE_ENABLED'"
    log "DEBUG" "COLLECTION_INTERVAL='$COLLECTION_INTERVAL'"
    log "DEBUG" "CONFIDENCE_THRESHOLD='$CONFIDENCE_THRESHOLD'"

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

# Get processes in alarm state
get_alarm_processes() {
    # Use --defaults-file instead of passing credentials on command line
    mysql --defaults-file="$MYSQL_TEMP_CONFIG" -N <<EOF
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

# Perform health check after restart
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

        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        printf "\r%s - DEBUG - Health check attempt failed for %s, retrying in 1 second... (attempt %d)" "$timestamp" "$process_name" "$attempt"
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
                # Direct process management
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

    # Use --defaults-file instead of passing credentials on command line
    mysql --defaults-file="$MYSQL_TEMP_CONFIG" <<EOF
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

# Collect metrics for a process
collect_process_metrics() {
    local process_id="$1"
    local process_name="$2"
    local status="$3"  # 0 = normal, 1 = alarm
    local restart_count=0
    local cpu_usage=""
    local memory_usage=""
    local response_time=""

    # Get restart count from circuit breaker
    if [ -n "${failure_counts[$process_name]}" ]; then
        restart_count=${failure_counts[$process_name]}
    fi

    # Collect resource usage metrics if enabled
    if [ "$RESOURCE_MONITORING" -eq 1 ]; then
        # Get CPU usage for the process
        if pgrep "$process_name" > /dev/null; then
            # Get CPU usage as percentage
            cpu_usage=$(ps -C "$process_name" -o %cpu= | awk '{s+=$1} END {print s}')

            # Get memory usage as percentage
            memory_usage=$(ps -C "$process_name" -o %mem= | awk '{s+=$1} END {print s}')

            log "DEBUG" "Collected resource metrics for $process_name: CPU=$cpu_usage%, MEM=$memory_usage%"
        else
            log "DEBUG" "Process $process_name not running, cannot collect resource metrics"
        fi
    fi

    # For services, we can measure response time
    if [ "$(get_restart_strategy "$process_name")" = "service" ]; then
        local start_time=$(date +%s.%N)
        systemctl status "$process_name" > /dev/null 2>&1
        local status_code=$?
        local end_time=$(date +%s.%N)

        if [ $status_code -eq 0 ]; then
            response_time=$(echo "$end_time - $start_time" | bc)
            log "DEBUG" "Measured response time for $process_name: $response_time seconds"
        fi
    fi

    # Store metrics in database
    store_process_metrics "$process_id" "$status" "$restart_count" "$response_time" "$cpu_usage" "$memory_usage"
}

# Store process metrics in the database
store_process_metrics() {
    local process_id="$1"
    local status="$2"
    local restart_count="$3"
    local response_time="$4"
    local cpu_usage="$5"
    local memory_usage="$6"

    # Handle NULL values for optional metrics
    local response_time_sql="NULL"
    local cpu_usage_sql="NULL"
    local memory_usage_sql="NULL"

    if [ -n "$response_time" ]; then
        response_time_sql="$response_time"
    fi

    if [ -n "$cpu_usage" ]; then
        cpu_usage_sql="$cpu_usage"
    fi

    if [ -n "$memory_usage" ]; then
        memory_usage_sql="$memory_usage"
    fi

    # Insert metrics into PROCESS_HISTORY table
    mysql --defaults-file="$MYSQL_TEMP_CONFIG" <<EOF
    INSERT INTO PROCESS_HISTORY 
    (process_id, status, restart_count, response_time, cpu_usage, memory_usage)
    VALUES 
    ($process_id, $status, $restart_count, $response_time_sql, $cpu_usage_sql, $memory_usage_sql);
EOF

    if [ $? -eq 0 ]; then
        log "DEBUG" "Stored metrics for process_id: $process_id"
    else
        log "ERROR" "Failed to store metrics for process_id: $process_id"
    fi

    # Clean up old history data
    if [ -n "$HISTORY_RETENTION_DAYS" ] && [ "$HISTORY_RETENTION_DAYS" -gt 0 ]; then
        mysql --defaults-file="$MYSQL_TEMP_CONFIG" <<EOF
        DELETE FROM PROCESS_HISTORY 
        WHERE timestamp < DATE_SUB(NOW(), INTERVAL $HISTORY_RETENTION_DAYS DAY);
EOF
    fi
}

# Analyze process metrics for predictive failure detection
analyze_process_metrics() {
    local process_id="$1"
    local process_name="$2"

    log "INFO" "Analyzing metrics for predictive failure detection: $process_name (ID: $process_id)"

    # Check if we have enough data points
    local data_points=$(mysql --defaults-file="$MYSQL_TEMP_CONFIG" -N <<EOF
    SELECT COUNT(*) FROM PROCESS_HISTORY WHERE process_id = $process_id;
EOF
    )

    if [ -z "$data_points" ] || [ "$data_points" -lt "$MIN_DATA_POINTS" ]; then
        log "DEBUG" "Not enough data points for $process_name: $data_points/$MIN_DATA_POINTS"
        return
    fi

    # Analyze restart frequency
    analyze_restart_frequency "$process_id" "$process_name"

    # Analyze resource usage trends if enabled
    if [ "$RESOURCE_MONITORING" -eq 1 ]; then
        analyze_resource_trends "$process_id" "$process_name"
    fi

    # Analyze response time trends for services
    if [ "$(get_restart_strategy "$process_name")" = "service" ]; then
        analyze_response_time_trends "$process_id" "$process_name"
    fi
}

# Analyze restart frequency for a process
analyze_restart_frequency() {
    local process_id="$1"
    local process_name="$2"

    # Get restart counts over time
    local restart_data=$(mysql --defaults-file="$MYSQL_TEMP_CONFIG" -N <<EOF
    SELECT 
        DATE(timestamp) as date, 
        MAX(restart_count) as max_restarts
    FROM PROCESS_HISTORY 
    WHERE process_id = $process_id
    GROUP BY DATE(timestamp)
    ORDER BY date DESC
    LIMIT 7;
EOF
    )

    # Count days with restarts
    local days_with_restarts=0
    local total_restarts=0

    while read -r line; do
        if [ -n "$line" ]; then
            local date=$(echo "$line" | awk '{print $1}')
            local restarts=$(echo "$line" | awk '{print $2}')

            if [ "$restarts" -gt 0 ]; then
                days_with_restarts=$((days_with_restarts + 1))
                total_restarts=$((total_restarts + restarts))
            fi
        fi
    done <<< "$restart_data"

    # Calculate confidence based on restart frequency
    local confidence=0
    if [ "$days_with_restarts" -ge 3 ] && [ "$total_restarts" -ge 5 ]; then
        confidence=0.8

        # Create predictive alert
        if [ $(echo "$confidence >= $CONFIDENCE_THRESHOLD" | bc -l) -eq 1 ]; then
            create_predictive_alert "$process_id" "$process_name" "restart_frequency" "$confidence" \
                "Process has restarted $total_restarts times in the last $days_with_restarts days. Potential instability detected."
        fi
    fi
}

# Analyze resource usage trends
analyze_resource_trends() {
    local process_id="$1"
    local process_name="$2"

    # Get CPU and memory trends
    local resource_data=$(mysql --defaults-file="$MYSQL_TEMP_CONFIG" -N <<EOF
    SELECT 
        AVG(cpu_usage) as avg_cpu,
        MAX(cpu_usage) as max_cpu,
        AVG(memory_usage) as avg_mem,
        MAX(memory_usage) as max_mem
    FROM PROCESS_HISTORY 
    WHERE process_id = $process_id
    AND cpu_usage IS NOT NULL
    AND memory_usage IS NOT NULL
    AND timestamp > DATE_SUB(NOW(), INTERVAL 24 HOUR);
EOF
    )

    if [ -n "$resource_data" ]; then
        local avg_cpu=$(echo "$resource_data" | awk '{print $1}')
        local max_cpu=$(echo "$resource_data" | awk '{print $2}')
        local avg_mem=$(echo "$resource_data" | awk '{print $3}')
        local max_mem=$(echo "$resource_data" | awk '{print $4}')

        # Check for high CPU usage
        if [ $(echo "$avg_cpu > 80" | bc -l) -eq 1 ] || [ $(echo "$max_cpu > 95" | bc -l) -eq 1 ]; then
            local confidence=0.75
            if [ $(echo "$confidence >= $CONFIDENCE_THRESHOLD" | bc -l) -eq 1 ]; then
                create_predictive_alert "$process_id" "$process_name" "high_cpu_usage" "$confidence" \
                    "Process is showing high CPU usage (avg: ${avg_cpu}%, max: ${max_cpu}%). This may lead to performance issues or failures."
            fi
        fi

        # Check for high memory usage
        if [ $(echo "$avg_mem > 80" | bc -l) -eq 1 ] || [ $(echo "$max_mem > 95" | bc -l) -eq 1 ]; then
            local confidence=0.75
            if [ $(echo "$confidence >= $CONFIDENCE_THRESHOLD" | bc -l) -eq 1 ]; then
                create_predictive_alert "$process_id" "$process_name" "high_memory_usage" "$confidence" \
                    "Process is showing high memory usage (avg: ${avg_mem}%, max: ${max_mem}%). This may lead to out-of-memory errors."
            fi
        fi
    fi
}

# Analyze response time trends
analyze_response_time_trends() {
    local process_id="$1"
    local process_name="$2"

    # Get response time trends
    local response_data=$(mysql --defaults-file="$MYSQL_TEMP_CONFIG" -N <<EOF
    SELECT 
        AVG(response_time) as avg_time,
        MAX(response_time) as max_time,
        STDDEV(response_time) as stddev_time
    FROM PROCESS_HISTORY 
    WHERE process_id = $process_id
    AND response_time IS NOT NULL
    AND timestamp > DATE_SUB(NOW(), INTERVAL 24 HOUR);
EOF
    )

    if [ -n "$response_data" ]; then
        local avg_time=$(echo "$response_data" | awk '{print $1}')
        local max_time=$(echo "$response_data" | awk '{print $2}')
        local stddev_time=$(echo "$response_data" | awk '{print $3}')

        # Check for increasing response times
        if [ $(echo "$max_time > ($avg_time * 3)" | bc -l) -eq 1 ] || [ $(echo "$stddev_time > ($avg_time * 0.5)" | bc -l) -eq 1 ]; then
            local confidence=0.7
            if [ $(echo "$confidence >= $CONFIDENCE_THRESHOLD" | bc -l) -eq 1 ]; then
                create_predictive_alert "$process_id" "$process_name" "response_time_degradation" "$confidence" \
                    "Service is showing response time degradation (avg: ${avg_time}s, max: ${max_time}s). This may indicate impending failure."
            fi
        fi
    fi
}

# Create a predictive alert
create_predictive_alert() {
    local process_id="$1"
    local process_name="$2"
    local prediction_type="$3"
    local confidence="$4"
    local description="$5"

    log "WARNING" "PREDICTIVE ALERT: $process_name - $description (confidence: $confidence)"

    # Check if a similar alert already exists
    local existing_alert=$(mysql --defaults-file="$MYSQL_TEMP_CONFIG" -N <<EOF
    SELECT COUNT(*) FROM PREDICTIVE_ALERTS 
    WHERE process_id = $process_id 
    AND prediction_type = '$prediction_type'
    AND resolved = 0
    AND timestamp > DATE_SUB(NOW(), INTERVAL 24 HOUR);
EOF
    )

    if [ "$existing_alert" -eq 0 ]; then
        # Insert new alert
        mysql --defaults-file="$MYSQL_TEMP_CONFIG" <<EOF
        INSERT INTO PREDICTIVE_ALERTS 
        (process_id, prediction_type, confidence, description)
        VALUES 
        ($process_id, '$prediction_type', $confidence, '$description');
EOF

        # Update STATUS_PROCESS to indicate predictive alert
        mysql --defaults-file="$MYSQL_TEMP_CONFIG" <<EOF
        UPDATE STATUS_PROCESS 
        SET predictive_alert = 1,
            notes = CONCAT(notes, ' - Predictive alert: $description')
        WHERE process_id = $process_id;
EOF

        if [ $? -eq 0 ]; then
            log "INFO" "Created predictive alert for $process_name: $prediction_type"
        else
            log "ERROR" "Failed to create predictive alert for $process_name"
        fi
    else
        log "DEBUG" "Similar predictive alert already exists for $process_name"
    fi
}

# Get all processes for metrics collection
get_all_processes() {
    mysql --defaults-file="$MYSQL_TEMP_CONFIG" -N <<EOF
    SELECT CONCAT(p.process_id, '|', p.process_name, '|', s.alarma)
    FROM STATUS_PROCESS s
    JOIN PROCESE p ON s.process_id = p.process_id;
EOF
}

# Main monitoring loop
main() {
    log "INFO" "Starting Process Monitor Service"

    # Read configuration
    read_config

    # Create MySQL config file with the loaded credentials
    create_mysql_config

    # Initialize variables for predictive monitoring
    local last_metrics_collection=0
    local last_predictive_analysis=0

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

        # Predictive failure detection
        if [ "$PREDICTIVE_ENABLED" -eq 1 ]; then
            current_time=$(date +%s)

            # Collect metrics at the specified interval
            if [ $((current_time - last_metrics_collection)) -ge "$COLLECTION_INTERVAL" ]; then
                log "INFO" "Collecting metrics for all processes"

                # Collect metrics for all processes
                while IFS='|' read -r process_id process_name status; do
                    if [ -n "$process_id" ]; then
                        collect_process_metrics "$process_id" "$process_name" "$status"
                    fi
                done < <(get_all_processes)

                last_metrics_collection=$current_time
                log "INFO" "Metrics collection completed"
            fi

            # Analyze metrics for predictive failure detection (every hour)
            if [ $((current_time - last_predictive_analysis)) -ge 3600 ]; then
                log "INFO" "Running predictive failure analysis"

                # Analyze metrics for all processes
                while IFS='|' read -r process_id process_name status; do
                    if [ -n "$process_id" ]; then
                        analyze_process_metrics "$process_id" "$process_name"
                    fi
                done < <(get_all_processes)

                last_predictive_analysis=$current_time
                log "INFO" "Predictive analysis completed"
            fi
        fi

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
