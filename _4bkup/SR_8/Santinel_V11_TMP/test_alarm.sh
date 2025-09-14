#!/bin/bash

# Script pentru testarea monitor_service.sh
# Acest script setează serviciile în stare de alarmă

# Configurare din același config.ini
CONFIG_FILE="config.ini"

# Funcție pentru logging
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp - $level - $message"
}

# Citește configurația din config.ini
read_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log "ERROR" "Fișierul de configurare $CONFIG_FILE nu a fost găsit"
        exit 1
    fi

    # Parsează secțiunea database
    DB_HOST=$(sed -n '/^\[database\]/,/^\[/p' "$CONFIG_FILE" | grep "^host[[:space:]]*=" | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    DB_USER=$(sed -n '/^\[database\]/,/^\[/p' "$CONFIG_FILE" | grep "^user[[:space:]]*=" | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    DB_PASS=$(sed -n '/^\[database\]/,/^\[/p' "$CONFIG_FILE" | grep "^password[[:space:]]*=" | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    DB_NAME=$(sed -n '/^\[database\]/,/^\[/p' "$CONFIG_FILE" | grep "^database[[:space:]]*=" | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
}

# Afișează serviciile disponibile
show_services() {
    log "INFO" "Lista serviciilor disponibile:"
    mysql -N -u"$DB_USER" -p"$DB_PASS" -h"$DB_HOST" "$DB_NAME" <<EOF
    SELECT CONCAT(p.process_id, ' - ', p.process_name, ' (', 
           CASE WHEN s.alarma = 1 THEN 'în alarmă' ELSE 'normal' END, ')')
    FROM STATUS_PROCESS s
    JOIN PROCESE p ON s.process_id = p.process_id
    ORDER BY p.process_id;
EOF
}

# Setează un serviciu în stare de alarmă
set_service_alarm() {
    local process_id="$1"
    local notes="Test alarm triggered at $(date '+%Y-%m-%d %H:%M:%S')"
    
    mysql -u"$DB_USER" -p"$DB_PASS" -h"$DB_HOST" "$DB_NAME" <<EOF
    UPDATE STATUS_PROCESS 
    SET alarma = 1, 
        sound = 0,
        notes = '$notes'
    WHERE process_id = $process_id;
EOF
    
    if [ $? -eq 0 ]; then
        log "INFO" "Serviciul cu ID $process_id a fost setat în stare de alarmă"
    else
        log "ERROR" "Nu s-a putut seta alarma pentru serviciul cu ID $process_id"
    fi
}

# Setează toate serviciile în stare de alarmă
set_all_services_alarm() {
    local notes="Test alarm triggered at $(date '+%Y-%m-%d %H:%M:%S')"
    
    mysql -u"$DB_USER" -p"$DB_PASS" -h"$DB_HOST" "$DB_NAME" <<EOF
    UPDATE STATUS_PROCESS 
    SET alarma = 1, 
        sound = 0,
        notes = '$notes';
EOF
    
    if [ $? -eq 0 ]; then
        log "INFO" "Toate serviciile au fost setate în stare de alarmă"
    else
        log "ERROR" "Nu s-au putut seta alarmele pentru servicii"
    fi
}

# Resetează toate alarmele
reset_all_alarms() {
    mysql -u"$DB_USER" -p"$DB_PASS" -h"$DB_HOST" "$DB_NAME" <<EOF
    UPDATE STATUS_PROCESS 
    SET alarma = 0, 
        sound = 0,
        notes = 'Reset la $(date '+%Y-%m-%d %H:%M:%S')';
EOF
    
    if [ $? -eq 0 ]; then
        log "INFO" "Toate alarmele au fost resetate"
    else
        log "ERROR" "Nu s-au putut reseta alarmele"
    fi
}

# Main
main() {
    # Citește configurația
    read_config
    
    # Meniu interactiv
    while true; do
        echo
        echo "Test Monitor Service - Meniu"
        echo "1. Afișează toate serviciile"
        echo "2. Setează un serviciu specific în alarmă"
        echo "3. Setează toate serviciile în alarmă"
        echo "4. Resetează toate alarmele"
        echo "5. Ieșire"
        echo
        read -p "Alegeți o opțiune (1-5): " option
        
        case $option in
            1)
                show_services
                ;;
            2)
                show_services
                read -p "Introduceți ID-ul serviciului pentru alarmă: " service_id
                set_service_alarm "$service_id"
                ;;
            3)
                set_all_services_alarm
                ;;
            4)
                reset_all_alarms
                ;;
            5)
                log "INFO" "Ieșire din program"
                exit 0
                ;;
            *)
                log "WARNING" "Opțiune invalidă"
                ;;
        esac
    done
}

# Start script
main
