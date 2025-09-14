#!/bin/bash

# Process Monitor Service
#
# This script monitors processes by checking their status in a MySQL database
# and restarts them when they are in alarm state.

# Set up logging
LOG_FILE="/var/log/monitor_service.log"

# Load configuration
CONFIG_FILE="config.ini"

###############################################################################
# Function: check_log_rotation
# Purpose:  Verifică dacă fișierul de log depășește dimensiunea configurată și
#           dacă este necesară rotirea acestuia.
# Returnează: 0 dacă este necesară rotirea, 1 altfel.
###############################################################################

check_log_rotation() {
    # If log file doesn't exist, no rotation needed
    if [ ! -f "$LOG_FILE" ]; then
        return 1
    fi

    # Get file size in KB
    local file_size=$(du -k "$LOG_FILE" | cut -f1)

    # Ensure MAX_LOG_SIZE is set and numeric
    if [ -z "$MAX_LOG_SIZE" ] || ! [[ "$MAX_LOG_SIZE" =~ ^[0-9]+$ ]]; then
        echo "ERROR: MAX_LOG_SIZE is not set or not a valid integer (value: '$MAX_LOG_SIZE')" >&2
        return 1
    fi

    # Check if file size exceeds the maximum
    if [ "$file_size" -ge "$MAX_LOG_SIZE" ]; then
        return 0  # Rotation needed
    else
        return 1  # No rotation needed
    fi
}

###############################################################################
# Function: rotate_logs
# Purpose:  Rotește fișierele de log, păstrând doar numărul configurat de backup-uri.
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
# Purpose:  Scrie un mesaj de log cu timestamp, rotește logul dacă este necesar.
#           Mesajele de nivel ERROR/CRITICAL sunt trimise și către syslog.
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
# Purpose:  Citește și parsează configurația din config.ini.
#           Exportă variabilele necesare și validează valorile critice.
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
# Purpose:  Interoghează baza de date pentru procesele aflate în stare de alarmă
#           (alarma=1, sound=0). Returnează fiecare proces pe o linie.
# Output:   Fiecare linie: process_id|process_name|alarma|sound|notes
###############################################################################

get_alarm_processes() {
    # Creează un fișier temporar unic pentru fiecare query
    local temp_mysql_config
    temp_mysql_config=$(mktemp)

    # Scrie configurația MySQL în fișierul temporar
    cat > "$temp_mysql_config" << EOF
[client]
host=$DB_HOST
user=$DB_USER
password=$DB_PASS
database=$DB_NAME
EOF
    # Use --defaults-file instead of passing credentials on command line
    # Added options to optimize connection handling:
    # --connect-timeout=5: Limit connection time to 5 seconds
    # --quick: Reduce memory usage and speed up query execution
    # --compress: Reduce network traffic
    # --reconnect=FALSE: Prevent automatic reconnection attempts
    # Execută query-ul folosind fișierul temporar
    mysql --defaults-file="$temp_mysql_config" --connect-timeout=5 --quick --compression-algorithms=zlib,uncompressed --reconnect=FALSE -N <<EOF
    SELECT CONCAT(p.process_id, '|', p.process_name, '|', s.alarma, '|', s.sound, '|', s.notes)
    FROM STATUS_PROCESS s
    JOIN PROCESE p ON s.process_id = p.process_id
    WHERE s.alarma = 1 AND s.sound = 0;
EOF

    # Șterge fișierul temporar imediat după query
    rm -f "$temp_mysql_config"
}

###############################################################################
# Function: get_process_config
# Purpose:  Obține o valoare de configurare specifică unui proces, fără fallback
#           la [process.default]. Dacă nu este găsită, se folosește valoarea
#           implicită furnizată ca argument (dacă există).
# Arguments:
#   $1 - numele procesului
#   $2 - numele parametrului
#   $3 - valoare implicită (opțional)
###############################################################################

get_process_config() {
    local process_name="$1"
    local param="$2"
    local default_value="$3"

    # Obține setarea specifică procesului; fără fallback la [process.default]
    local value=$(sed -n "/^\[process.$process_name\]/,/^\[/p" "$CONFIG_FILE" | grep "^$param[[:space:]]*=" | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # Dacă nu este găsită, folosește valoarea implicită furnizată (dacă există)
    echo "${value:-$default_value}"
}
# TO DO in code
# Helper: check if process has a specific section in config.ini
###############################################################################
# Function: has_process_config
# Purpose:  Verifică dacă există secțiunea [process.<nume>] în config.ini.
# Arguments:
#   $1 - numele procesului
# Returnează: 0 dacă există, 1 dacă nu există
###############################################################################

has_process_config() {
    local process_name="$1"
    if sed -n "/^\[process.${process_name}\]/p" "$CONFIG_FILE" | grep -q "^\[process.${process_name}\]"; then
        return 0
    else
        return 1
    fi
}

# Helper: get the real system name for a process (from config, fallback to process_name)
###############################################################################
# Function: get_system_name
# Purpose:  Returnează numele real al sistemului pentru un proces, dacă este
#           specificat în config, altfel returnează numele procesului.
# Arguments:
#   $1 - numele procesului
###############################################################################

get_system_name() {
    local process_name="$1"
    local system_name=$(get_process_config "$process_name" "system_name" "")
    if [ -n "$system_name" ]; then
        echo "$system_name"
    else
        echo "$process_name"
    fi
}

###############################################################################
# Function: execute_pre_restart
# Purpose:  Rulează o comandă pre-restart pentru un proces dacă este configurată.
# Returnează: 0 la succes, 1 la eșec.
# Arguments:
#   $1 - numele procesului
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
# Purpose:  Rulează o comandă de health check pentru un proces, cu retry până la timeout.
#           Dacă nu există health check configurat, presupune succes.
# Returnează: 0 dacă health check-ul trece, 1 dacă eșuează după timeout.
# Arguments:
#   $1 - numele procesului
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
# Purpose:  Obține strategia de restart pentru un proces (service, process, custom).
# Arguments:
#   $1 - numele procesului
###############################################################################

get_restart_strategy() {
    local process_name="$1"
    local strategy=$(get_process_config "$process_name" "restart_strategy" "")
    echo "$strategy"
}

###############################################################################
# Function: restart_process
# Purpose:  Încearcă să restarteze un proces folosind strategia configurată.
#           Suportă strategiile: service, process, custom. Toate strategiile suportă configurarea
#           restart_command și system_name pentru flexibilitate maximă.
#           Dacă procesul/serviciul nu rulează, îl pornește; dacă rulează, îl restartează.
#           După fiecare încercare, efectuează un health check pentru a verifica succesul.
#           Repetă până la max_attempts, cu pauză restart_delay între încercări.
#
# Parametri:
#   $1 - process_name: Numele logic al procesului (cheia din config.ini).
#
# Comportament:
#   - Obține strategia de restart, numărul maxim de încercări și delay-ul dintre încercări din config.
#   - Obține numele real al serviciului/procesului (system_name) dacă este specificat.
#   - Execută comanda pre-restart dacă este configurată.
#   - Pentru fiecare încercare:
#       - Pentru strategia "service", "custom" sau "process":
#           - Dacă este configurat `restart_command`, îl execută direct.
#           - Altfel, folosește comportamentul implicit:
#               - Pentru "service": `initctl start/restart` cu `system_name`
#               - Pentru "custom": `initctl start/restart` cu `system_name` (fallback)
#               - Pentru "process": `pgrep`/`pkill` cu `system_name` (fallback)
#           - După start/restart, rulează health check-ul configurat.
#       - Dacă health check-ul reușește, funcția returnează 0 (succes).
#       - Dacă health check-ul eșuează, loghează eroarea și reia după restart_delay.
#   - Dacă toate încercările eșuează, returnează 1.
#
# Return:
#   0 - dacă procesul a fost restartat/pornit cu succes și a trecut health check-ul.
#   1 - dacă toate încercările au eșuat.
#
# Exemple de utilizare:
#   restart_process "sshd"
#   restart_process "rsyslogd"
###############################################################################

restart_process() {
    local process_name="$1"
    local strategy=$(get_restart_strategy "$process_name")
    local max_attempts=$(get_process_config "$process_name" "max_attempts" "2")
    local restart_delay=$(get_process_config "$process_name" "restart_delay" "2")
    local system_name=$(get_system_name "$process_name")

    log "INFO" "RESTART LOG: Beginning restart procedure for $process_name (strategy: $strategy, system_name: $system_name)"

    # Execute pre-restart command if any
    if ! execute_pre_restart "$process_name"; then
        return 1
    fi

    local attempt=1
    while [ $attempt -le "$max_attempts" ]; do
        log "INFO" "Attempting restart ($attempt of $max_attempts) for $process_name"

        case "$strategy" in
            "custom")
                # Check for custom restart command
                local restart_command=$(get_process_config "$process_name" "restart_command" "")
                if [ -n "$restart_command" ]; then
                    log "INFO" "Executing custom restart command for $process_name: $restart_command"
                    if eval "$restart_command"; then
                        log "INFO" "Custom restart command executed for: $process_name"
                    else
                        log "ERROR" "Custom restart command failed for: $process_name"
                    fi
                else
                    # fallback to initctl if no custom command
                    if ! initctl status "$system_name" 2>/dev/null | grep -q "start/running"; then
                        log "INFO" "Service $system_name is not running. Attempting to start."
                        if initctl start "$system_name" 2>/dev/null; then
                            log "INFO" "Service start command executed for: $system_name"
                        else
                            log "ERROR" "Service start command failed for: $system_name"
                        fi
                    else
                        if initctl restart "$system_name" 2>/dev/null; then
                            log "INFO" "Service restart command executed for: $system_name"
                        else
                            log "ERROR" "Service restart command failed for: $system_name"
                        fi
                    fi
                fi
                # Health check
                if perform_health_check "$process_name"; then
                    log "INFO" "RESTART LOG: Successfully started/restarted and verified service: $system_name"
                    return 0
                else
                    log "ERROR" "RESTART LOG: Start/Restart command succeeded but health check failed for: $system_name"
                fi
                ;;
            "service")
                # Check for custom restart command first (if configured)
                local restart_command=$(get_process_config "$process_name" "restart_command" "")
                if [ -n "$restart_command" ]; then
                    log "INFO" "Executing custom restart command for $process_name: $restart_command"
                    if eval "$restart_command"; then
                        log "INFO" "Custom restart command executed for: $process_name"
                    else
                        log "ERROR" "Custom restart command failed for: $process_name"
                    fi
                else
                    # fallback to initctl if no custom command
                    if ! initctl status "$system_name" 2>/dev/null | grep -q "start/running"; then
                        log "INFO" "Service $system_name is not running. Attempting to start."
                        if initctl start "$system_name" 2>/dev/null; then
                            log "INFO" "Service start command executed for: $system_name"
                        else
                            log "ERROR" "Service start command failed for: $system_name"
                        fi
                    else
                        if initctl restart "$system_name" 2>/dev/null; then
                            log "INFO" "Service restart command executed for: $system_name"
                        else
                            log "ERROR" "Service restart command failed for: $system_name"
                        fi
                    fi
                fi
                # Health check
                if perform_health_check "$process_name"; then
                    log "INFO" "RESTART LOG: Successfully started/restarted and verified service: $system_name"
                    return 0
                else
                    log "ERROR" "RESTART LOG: Start/Restart command succeeded but health check failed for: $system_name"
                fi
                ;;
            "process")
                # Check for custom restart command first (if configured)
                local restart_command=$(get_process_config "$process_name" "restart_command" "")
                if [ -n "$restart_command" ]; then
                    log "INFO" "Executing custom restart command for $process_name: $restart_command"
                    if eval "$restart_command"; then
                        log "INFO" "Custom restart command executed for: $process_name"
                    else
                        log "ERROR" "Custom restart command failed for: $process_name"
                    fi
                else
                    # fallback to pgrep/pkill if no custom command
                    if ! pgrep "$system_name" >/dev/null 2>&1; then
                        log "INFO" "Process $system_name is not running. Attempting to start."
                        if "$system_name" >/dev/null 2>&1 & then
                            log "INFO" "Process start command executed for: $system_name"
                        else
                            log "ERROR" "Process start command failed for: $system_name"
                        fi
                    else
                        pkill "$system_name"
                        sleep "$restart_delay"
                        if "$system_name" >/dev/null 2>&1 & then
                            log "INFO" "Process restart command executed for: $system_name"
                        else
                            log "ERROR" "Process restart command failed for: $system_name"
                        fi
                    fi
                fi
                # Health check
                if perform_health_check "$process_name"; then
                    log "INFO" "RESTART LOG: Successfully started/restarted and verified process: $system_name"
                    return 0
                else
                    log "ERROR" "RESTART LOG: Start/Restart command succeeded but health check failed for: $system_name"
                fi
                ;;
            *)
                log "ERROR" "RESTART LOG: Unknown or unsupported restart strategy for $process_name: $strategy"
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
###############################################################################
# Function: update_alarm_status
# Purpose:  Actualizează statusul de alarmă în baza de date pentru un proces.
#           (Doar pentru testare, utilizatorul final va avea doar SELECT)
# Arguments:
#   $1 - process_id
# Returnează: 0 la succes, 1 la eșec.
###############################################################################

# TO DO: FUNCTION WILL BE LATER DELETED, it's used only for testing purposes. The new user will have only SELECT permissions.
# Use --defaults-file instead of passing credentials on command line
# Added options to optimize connection handling:
# --connect-timeout=5: Limit connection time to 5 seconds
# --quick: Reduce memory usage and speed up query execution
# --compress: Reduce network traffic
# --reconnect=FALSE: Prevent automatic reconnection attempts
update_alarm_status() {
    local process_id="$1"
    local current_time=$(date '+%Y-%m-%d %H:%M:%S')

    # Creează un fișier temporar unic pentru fiecare query
    local temp_mysql_config
    temp_mysql_config=$(mktemp)

    # Scrie configurația MySQL în fișierul temporar
    cat > "$temp_mysql_config" << EOF
[client]
host=$DB_HOST
user=$DB_USER
password=$DB_PASS
database=$DB_NAME
EOF

    # Execută query-ul folosind fișierul temporar
    mysql --defaults-file="$temp_mysql_config" --connect-timeout=5 --quick --compression-algorithms=zlib,uncompressed --reconnect=FALSE <<EOF
    UPDATE STATUS_PROCESS 
    SET alarma = 0, notes = CONCAT(notes, ' - Restarted at $current_time')
    WHERE process_id = $process_id;
EOF

    # Șterge fișierul temporar imediat după query
    rm -f "$temp_mysql_config"

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
# Purpose:  Previne încercările repetate de restart pentru procesele care eșuează.
#           Deschide circuitul după N eșecuri, îl resetează după un cooldown.
###############################################################################

declare -A circuit_breaker
declare -A failure_counts
declare -A last_failure_times

###############################################################################
# Function: check_circuit_breaker
# Purpose:  Verifică dacă circuit breaker-ul este deschis pentru un proces.
#           Dacă este deschis, omite restartul până la expirarea timpului de reset.
# Returnează: 0 dacă e închis, 1 dacă e deschis.
# Arguments:
#   $1 - numele procesului
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
# Purpose:  Actualizează starea circuit breaker-ului după o încercare de restart.
#           Deschide circuitul dacă numărul de eșecuri depășește pragul.
# Arguments:
#   $1 - numele procesului
#   $2 - "true" dacă restartul a reușit, "false" dacă a eșuat
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
# Purpose:  Bucla principală de monitorizare. Verifică procesele în alarmă,
#           încearcă restart, actualizează baza de date și circuit breaker-ul,
#           și așteaptă până la următoarea verificare.
###############################################################################
# Main monitoring loop
main() {
    # Read configuration first
    read_config

    log "INFO" "Starting Process Monitor Service"
    
    # --- CLI argument ---
    if [[ "$1" == "--help" ]]; then
        echo "Usage: $0 [--status] [--restart <process_name>] [--help]"
        echo "  --status                Afișează procesele aflate în stare de alarmă."
        echo "  --restart <process>     Forțează restart pentru procesul specificat."
        echo "  --help                  Afișează acest mesaj de ajutor."
        exit 0
    elif [[ "$1" == "--status" ]]; then
        read_config
        echo "Procese în stare de alarmă (alarma=1, sound=0):"
        get_alarm_processes | while IFS='|' read -r process_id process_name alarma sound notes; do
            if [ -n "$process_id" ]; then
                echo "ID: $process_id | Nume: $process_name | Notes: $notes"
            fi
        done
        exit 0
    elif [[ "$1" == "--restart" && -n "$2" ]]; then
        read_config
        process_name="$2"
        echo "Forțez restart pentru procesul: $process_name"
        if restart_process "$process_name"; then
            echo "Restart reușit pentru $process_name."
        else
            echo "Eroare la restart pentru $process_name."
        fi
        exit 0
    fi
    # --- end CLI argument handling ---

    while true; do
        start_time=$(date +%s)

        # Get processes in alarm state
        while IFS='|' read -r process_id process_name alarma sound notes; do
            # if [ -n "$process_id" ]; then
            
            # Procesează doar dacă process_id și process_name nu sunt goale
            if [ -n "$process_id" ] && [ -n "$process_name" ]; then
                # TO DO in code Ignoră procesele care nu au secțiune dedicată în config.ini
                if ! has_process_config "$process_name"; then
                    log "INFO" "Ignoring process without config section: $process_name (ID: $process_id)"
                    continue
                fi
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
main "$@"
