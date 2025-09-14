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

# Afișează alerte predictive
show_predictive_alerts() {
    log "INFO" "Lista alertelor predictive:"
    mysql -N -u"$DB_USER" -p"$DB_PASS" -h"$DB_HOST" "$DB_NAME" <<EOF
    SELECT CONCAT(a.alert_id, ' - ', p.process_name, ' (', 
           a.prediction_type, ', confidence: ', a.confidence, ') - ', 
           a.description, ' - ', 
           CASE WHEN a.resolved = 1 THEN 'rezolvat' ELSE 'activ' END)
    FROM PREDICTIVE_ALERTS a
    JOIN STATUS_PROCESS s ON a.process_id = s.process_id
    JOIN PROCESE p ON s.process_id = p.process_id
    ORDER BY a.timestamp DESC
    LIMIT 20;
EOF
}

# Marchează o alertă predictivă ca rezolvată
resolve_predictive_alert() {
    local alert_id="$1"

    mysql -u"$DB_USER" -p"$DB_PASS" -h"$DB_HOST" "$DB_NAME" <<EOF
    UPDATE PREDICTIVE_ALERTS 
    SET resolved = 1
    WHERE alert_id = $alert_id;
EOF

    if [ $? -eq 0 ]; then
        log "INFO" "Alerta predictivă cu ID $alert_id a fost marcată ca rezolvată"

        # Verifică dacă mai există alerte active pentru acest proces
        local process_id=$(mysql -N -u"$DB_USER" -p"$DB_PASS" -h"$DB_HOST" "$DB_NAME" <<EOF
        SELECT process_id FROM PREDICTIVE_ALERTS WHERE alert_id = $alert_id;
EOF
        )

        local active_alerts=$(mysql -N -u"$DB_USER" -p"$DB_PASS" -h"$DB_HOST" "$DB_NAME" <<EOF
        SELECT COUNT(*) FROM PREDICTIVE_ALERTS 
        WHERE process_id = $process_id AND resolved = 0;
EOF
        )

        if [ "$active_alerts" -eq 0 ]; then
            # Resetează indicatorul de alertă predictivă
            mysql -u"$DB_USER" -p"$DB_PASS" -h"$DB_HOST" "$DB_NAME" <<EOF
            UPDATE STATUS_PROCESS 
            SET predictive_alert = 0
            WHERE process_id = $process_id;
EOF
            log "INFO" "Indicatorul de alertă predictivă a fost resetat pentru procesul cu ID $process_id"
        fi
    else
        log "ERROR" "Nu s-a putut marca alerta predictivă cu ID $alert_id ca rezolvată"
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
        echo "5. Afișează alerte predictive"
        echo "6. Marchează o alertă predictivă ca rezolvată"
        echo "7. Ieșire"
        echo
        read -p "Alegeți o opțiune (1-7): " option

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
                show_predictive_alerts
                ;;
            6)
                show_predictive_alerts
                read -p "Introduceți ID-ul alertei predictive pentru a o marca ca rezolvată: " alert_id
                resolve_predictive_alert "$alert_id"
                ;;
            7)
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
