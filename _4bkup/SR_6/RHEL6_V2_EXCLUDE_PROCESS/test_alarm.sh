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

# Generează un număr întreg aleator între [min, max]
random_between() {
    local min="$1"
    local max="$2"
    echo $((RANDOM % (max - min + 1) + min))
}

# Rulează o iterație de injectare aleatorie de alarme
random_alarm_once() {
    local max_at_once="$1"   # câte procese setăm simultan, cel mult
    local now
    now=$(date '+%Y-%m-%d %H:%M:%S')

    # Alegem un număr aleator între 1 și max_at_once
    local count
    count=$(random_between 1 "$max_at_once")

    # Folosește ORDER BY RAND() LIMIT pentru a marca aleator procese neaflate deja în alarmă
    mysql -u"$DB_USER" -p"$DB_PASS" -h"$DB_HOST" "$DB_NAME" <<EOF
    UPDATE STATUS_PROCESS
    SET alarma = 1,
        sound = 0,
        notes = CONCAT('Random test at $now')
    WHERE alarma = 0
    ORDER BY RAND()
    LIMIT $count;
EOF

    if [ $? -eq 0 ]; then
        log "INFO" "Random alarm inject: setate $count procese în alarmă"
    else
        log "ERROR" "Random alarm inject: eșec la actualizarea bazei de date"
    fi
}

# Buclă continuă care introduce aleator alarme în baza de date
random_alarm_loop() {
    local min_delay="$1"      # secunde
    local max_delay="$2"      # secunde
    local max_at_once="$3"    # maxim procese pe iteratie

    log "INFO" "Pornesc modul aleator: min_delay=${min_delay}s, max_delay=${max_delay}s, max_at_once=${max_at_once}"
    trap 'log "INFO" "Oprire modul aleator"; exit 0' INT TERM

    while true; do
        random_alarm_once "$max_at_once"
        # Alege un sleep aleator între min_delay și max_delay
        local sleep_s
        sleep_s=$(random_between "$min_delay" "$max_delay")
        printf "Următoarea injectare aleatorie în %s secunde\r" "$sleep_s"
        sleep "$sleep_s"
        echo ""
    done
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
    
    # --- CLI argumente rapide ---
    if [[ "$1" == "--help" ]]; then
        echo "Usage: $0 [fără argumente pentru meniu]"
        echo "       $0 --random [--min-delay N] [--max-delay M] [--max-at-once K]"
        echo "       $0 --reset-all"
        exit 0
    elif [[ "$1" == "--reset-all" ]]; then
        reset_all_alarms
        exit 0
    elif [[ "$1" == "--random" ]]; then
        # Valori implicite
        local MIN_DELAY=10
        local MAX_DELAY=30
        local MAX_AT_ONCE=2
        shift
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --min-delay)
                    MIN_DELAY="$2"; shift 2;;
                --max-delay)
                    MAX_DELAY="$2"; shift 2;;
                --max-at-once)
                    MAX_AT_ONCE="$2"; shift 2;;
                *)
                    log "WARNING" "Argument necunoscut pentru --random: $1"; shift;;
            esac
        done
        random_alarm_loop "$MIN_DELAY" "$MAX_DELAY" "$MAX_AT_ONCE"
        exit 0
    fi
    # --- sfârșit CLI ---
    
    # Meniu interactiv
    while true; do
        echo
        echo "Test Monitor Service - Meniu"
        echo "1. Afișează toate serviciile"
        echo "2. Setează un serviciu specific în alarmă"
        echo "3. Setează toate serviciile în alarmă"
        echo "4. Resetează toate alarmele"
        echo "5. Pornește modul aleator (non-stop)"
        echo "6. Ieșire"
        echo
        read -p "Alegeți o opțiune (1-6): " option
        
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
                # Parametri impliciți pentru modul aleator
                read -p "Min delay sec (implicit 10): " in_min
                read -p "Max delay sec (implicit 30): " in_max
                read -p "Max procese/iterație (implicit 2): " in_cnt
                local MIN_DELAY=${in_min:-10}
                local MAX_DELAY=${in_max:-30}
                local MAX_AT_ONCE=${in_cnt:-2}
                random_alarm_loop "$MIN_DELAY" "$MAX_DELAY" "$MAX_AT_ONCE"
                ;;
            6)
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
