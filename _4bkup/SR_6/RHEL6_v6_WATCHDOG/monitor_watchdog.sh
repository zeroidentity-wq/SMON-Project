#!/bin/bash

# Monitor Service Watchdog
# - Verifică heartbeat-ul scris de monitor_service
# - Dacă este mai vechi decât STALE_AFTER_SECONDS, rulează opțional PRECHECK și apoi restart

LOG_FILE="/var/log/monitor_service_watchdog.log"
SERVICE_NAME="monitor_watchdog"
HOST_NAME="$(hostname 2>/dev/null || echo unknown)"

# Defaults (may be overridden by config.ini)
CONFIG_FILE="config.ini"

log() {
    local level="$1"
    local message="$2"
    local ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$ts  [$level] - $message" | tee -a "$LOG_FILE"
    if [[ "$level" == "ERROR" || "$level" == "CRITICAL" ]]; then
        logger -p daemon.err "$ts [$level] $message"
    fi
}

read_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log "ERROR" "Configuration file $CONFIG_FILE not found"
        exit 1
    fi
    HEARTBEAT_FILE=$(sed -n '/^\[self_recovery\]/,/^\[/p' "$CONFIG_FILE" | grep "^heartbeat_file[[:space:]]*=" | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    STALE_AFTER_SECONDS=$(sed -n '/^\[self_recovery\]/,/^\[/p' "$CONFIG_FILE" | grep "^stale_after_seconds[[:space:]]*=" | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    SELF_RECOVERY_RESTART_CMD=$(sed -n '/^\[self_recovery\]/,/^\[/p' "$CONFIG_FILE" | grep "^restart_command[[:space:]]*=" | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    SELF_RECOVERY_PRECHECK_CMD=$(sed -n '/^\[self_recovery\]/,/^\[/p' "$CONFIG_FILE" | grep "^precheck_command[[:space:]]*=" | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    HEARTBEAT_FILE=${HEARTBEAT_FILE:-/var/run/monitor_service.heartbeat}
    STALE_AFTER_SECONDS=${STALE_AFTER_SECONDS:-300}
    SELF_RECOVERY_RESTART_CMD=${SELF_RECOVERY_RESTART_CMD:-"initctl restart monitor_service || service monitor_service restart || systemctl restart monitor_service"}
}

perform_precheck() {
    local cmd="$1"
    if [ -z "$cmd" ]; then
        return 0
    fi
    log "INFO" "Running precheck command"
    bash -c "$cmd"
    return $?
}

restart_service() {
    local cmd="$1"
    log "WARNING" "Attempting to restart monitor_service via configured command"
    bash -c "$cmd"
    return $?
}

main() {
    read_config
    log "INFO" "Starting monitor watchdog"
    while true; do
        now=$(date +%s)
        if [ -f "$HEARTBEAT_FILE" ]; then
            hb=$(cat "$HEARTBEAT_FILE" 2>/dev/null | tr -cd '0-9')
        else
            hb=0
        fi

        if [ -z "$hb" ] || ! [[ "$hb" =~ ^[0-9]+$ ]]; then
            hb=0
        fi

        age=$((now - hb))
        if [ $age -ge $STALE_AFTER_SECONDS ]; then
            log "ERROR" "Heartbeat stale (age=${age}s >= ${STALE_AFTER_SECONDS}s). Triggering recovery."
            if perform_precheck "$SELF_RECOVERY_PRECHECK_CMD"; then
                if restart_service "$SELF_RECOVERY_RESTART_CMD"; then
                    log "INFO" "Restart command executed"
                else
                    log "ERROR" "Restart command failed"
                fi
            else
                log "ERROR" "Precheck failed; skipping restart"
            fi
            # After handling, wait a bit before next check to avoid rapid loops
            sleep 15
        else
            # Normal case: heartbeat fresh
            sleep 5
        fi
    done
}

main "$@"


