# Process Monitor Service Improvement Tasks

This document contains a prioritized list of actionable improvement tasks for the Process Monitor Service. Each task is marked with a checkbox [ ] that can be checked off when completed.

## Architecture Improvements

2. [ ] Enhance security measures
   - [ ] Remove hardcoded database credentials from config.ini
   - [ ] Implement secure credential storage (e.g., using environment variables or a secrets manager)
   - [ ] Add option to run with reduced privileges instead of requiring root access
   - [ ] Implement proper input validation and sanitization for all database operations

3. [ ] Improve logging and monitoring
   - [ ] Implement structured logging (JSON format)
   - [x] Add log rotation to prevent log file growth
   - [ ] Create a dashboard for visualizing service status
   - [ ] Add metrics collection for monitoring performance

4. [ ] Enhance database interaction
   - [ ] Implement connection pooling for database operations
   - [ ] Add database migration support for schema updates
   - [ ] Implement proper error handling for database connection failures
   - [ ] Add support for alternative database engines

5. [ ] Internationalization and localization
   - [ ] Translate all comments, logs, and user-facing messages to English
   - [ ] Implement proper i18n support for multi-language environments
   - [ ] Create language resource files for easy translation

## Code-Level Improvements

6. [ ] Refactor monitor_service.sh
   - [ ] Split the script into smaller, more maintainable modules
   - [ ] Improve error handling throughout the script
   - [ ] Add more comprehensive input validation
   - [ ] Implement proper signal handling for graceful shutdown

7. [ ] Enhance restart strategies
   - [ ] Add support for custom restart commands
   - [x] Implement more sophisticated health checks before and after restarts
   - [ ] Add support for dependency-aware restart ordering
   - [ ] Implement gradual backoff for restart attempts

8. [ ] Improve circuit breaker implementation
   - [ ] Add partial circuit breaking (per service group)
   - [ ] Implement half-open state for testing recovery
   - [ ] Add configurable thresholds based on service criticality
   - [ ] Implement notification system for circuit breaker events

9. [ ] Enhance test_alarm.sh utility
   - [ ] Add automated testing capabilities
   - [ ] Implement batch operations for multiple services
   - [ ] Add service status history and trending
   - [ ] Create a web-based interface for the testing utility

10. [x] Improve database schema
    - [ ] Add service dependencies table
    - [ ] Implement service grouping for related services
    - [ ] Add historical data tracking for service failures
    - [x] Optimize database queries for better performance

## Documentation Improvements

11. [x] Enhance code documentation
    - [ ] Add function header comments for all functions
    - [ ] Document all variables and their purposes
    - [ ] Add inline comments for complex logic
    - [ ] Create a developer guide with architecture overview

12. [x] Improve user documentation
    - [ ] Create a comprehensive user manual
    - [ ] Add troubleshooting guides for common issues
    - [ ] Create installation guides for different Linux distributions
    - [ ] Add examples for common configuration scenarios

13. [x] Create system documentation
    - [ ] Document system architecture and components
    - [ ] Create database schema documentation
    - [ ] Add deployment diagrams and workflow descriptions
    - [ ] Document security considerations and best practices

## Testing and Quality Assurance

14. [ ] Implement automated testing
    - [ ] Create unit tests for core functions
    - [ ] Implement integration tests for database interactions
    - [ ] Add system tests for end-to-end functionality
    - [ ] Set up continuous integration for automated testing

15. [ ] Improve error handling and resilience
    - [ ] Add comprehensive error handling for all external dependencies
    - [ ] Implement graceful degradation for non-critical failures
    - [ ] Add self-healing capabilities for common failure scenarios
    - [ ] Implement proper logging for all error conditions

## Deployment and Operations

19. [ ] Enhance deployment process
    - [ ] Create automated deployment scripts
    - [ ] Add support for containerized deployment
    - [ ] Implement configuration management integration
    - [ ] Create backup and restore procedures

20. [ ] Improve operational capabilities
    - [ ] Add support for remote management
    - [ ] Implement role-based access control
    - [ ] Create administrative API for programmatic control
    - [ ] Add support for scheduled maintenance windows

# Documentație Tehnică - Process Monitor Service

## Prezentare Generală

Process Monitor Service este un script bash care monitorizează procesele/serviciile prin verificarea stării acestora într-o bază de date MySQL și le repornește automat când sunt în stare de alarmă. Este proiectat pentru medii RedHat Linux și oferă funcționalități avansate de monitorizare, circuit breaker și logging.

## Caracteristici Principale

- **Monitorizare automată**: Verifică periodic procesele în stare de alarmă din baza de date
- **Strategii multiple de restart**: Suportă restart prin systemd, kill/start process și comenzi personalizate
- **Circuit breaker**: Previne tentativele repetate de restart pentru procesele problematice
- **Health checks**: Verifică starea procesului după restart
- **Logging avansat**: System de logging cu rotație automată
- **Configurare flexibilă**: Configurare prin fișier INI cu setări globale și per-proces

## Arhitectura Sistemului

### Componente Principale

1. **Configurare și Inițializare**
   - Încărcare configurație din `config.ini`
   - Validare parametri
   - Crearea fișierului temporar pentru MySQL

2. **Sistem de Logging**
   - Logging cu timestamp
   - Rotație automată a fișierelor de log
   - Nivele de logging (INFO, ERROR, WARNING, DEBUG)

3. **Conectivitate Bază de Date**
   - Conexiuni MySQL optimizate
   - Autentificare securizată prin fișier temporar
   - Timeout-uri configurabile

4. **Motor de Monitorizare**
   - Interogare periodică a bazei de date
   - Detectare procese în alarmă
   - Circuit breaker pentru procese problematice

5. **Sistem de Restart**
   - Strategii multiple de restart
   - Health checks post-restart
   - Comenzi pre-restart

## Structura Fișierului de Configurare

### Secțiunea [database]
```ini
[database]
host=localhost
user=monitor_user
password=secure_password
database=monitoring_db
```

### Secțiunea [monitor]
```ini
[monitor]
check_interval=30
max_restart_failures=3
circuit_reset_time=300
```

### Secțiunea [logging]
```ini
[logging]
max_log_size=5120
log_files_to_keep=5
```

### Secțiuni Process-Specific
```ini
[process.default]
restart_strategy=auto
max_attempts=2
restart_delay=2
health_check_timeout=5

[process.apache2]
restart_strategy=service
max_attempts=3
restart_delay=5
health_check_command=curl -f http://localhost/health
health_check_timeout=10
pre_restart_command=echo "Preparing Apache restart"
```

## Strategii de Restart

### 1. Auto (Implicită)
- Încearcă restart prin systemd
- Fallback la kill/start process
- Cea mai flexibilă opțiune

### 2. Service
- Folosește exclusiv `systemctl restart`
- Ideal pentru servicii systemd

### 3. Process
- Kill proces + restart manual
- Pentru aplicații standalone

### 4. Custom
- Comandă personalizată de restart
- Flexibilitate maximă

## Circuit Breaker

Sistemul circuit breaker previne tentativele repetate de restart pentru procesele care eșuează consistent:

- **Closed**: Stare normală, permite restart-uri
- **Open**: După depășirea numărului maxim de eșecuri, blochează restart-urile
- **Reset**: După perioada configurată, revine la starea closed

### Parametri Circuit Breaker
- `max_restart_failures`: Numărul maxim de eșecuri consecutive
- `circuit_reset_time`: Timpul de așteptare în secunde pentru reset

## Structura Bazei de Date

### Tabelul PROCESE
```sql
CREATE TABLE PROCESE (
    process_id INT PRIMARY KEY,
    process_name VARCHAR(255) NOT NULL
);
```

### Tabelul STATUS_PROCESS
```sql
CREATE TABLE STATUS_PROCESS (
    process_id INT,
    alarma TINYINT,
    sound TINYINT,
    notes TEXT,
    FOREIGN KEY (process_id) REFERENCES PROCESE(process_id)
);
```

## Fluxul de Execuție

1. **Inițializare**
   - Încărcare configurație
   - Creare fișier MySQL temporar
   - Validare parametri

2. **Bucla Principală**
   - Interogare bază de date pentru procese în alarmă
   - Pentru fiecare proces găsit:
     - Verificare circuit breaker
     - Executare comenzi pre-restart
     - Tentativă de restart
     - Health check post-restart
     - Actualizare stare în baza de date
     - Actualizare circuit breaker

3. **Așteptare**
   - Countdown vizual până la următoarea verificare
   - Interval configurabil

## Logging și Monitorizare

### Tipuri de Log-uri

#### Restart Logs
```
RESTART LOG: Beginning restart procedure for apache2 (strategy: service)
RESTART LOG: Successfully restarted and verified service: apache2
```

#### Database Update Logs
```
DB UPDATE LOG: Successfully updated alarm status for process_id: 123
```

#### Circuit Breaker Logs
```
Circuit breaker opened for mysql after 3 failures
Circuit breaker reset for mysql
```

### Rotația Log-urilor
- Dimensiune maximă configurabilă (implicit 5MB)
- Numărul de fișiere păstrate configurabil (implicit 5)
- Rotație automată când se depășește dimensiunea

## Securitate

### Măsuri de Securitate Implementate

1. **Credențiale MySQL**
   - Stocare în fișier temporar cu permisiuni 600
   - Cleanup automat la ieșire
   - Nu apar în argumentele comenzii

2. **Validare Input**
   - Verificare existență fișier configurație
   - Validare valori numerice
   - Verificare parametri obligatorii

3. **Izolare Procese**
   - Fișiere temporare cu permisiuni restrictive
   - Cleanup automat prin trap

## Instalare și Configurare

### Cerințe de Sistem
- RedHat Linux (RHEL/CentOS/Fedora)
- MySQL client
- Bash 4.0+
- Utilitare standard (sed, awk, systemctl)

### Pași de Instalare

1. **Plasarea Scriptului**
```bash
sudo cp process_monitor.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/process_monitor.sh
```

2. **Configurarea**
```bash
# Creare director de configurare
sudo mkdir -p /etc/process_monitor
sudo cp config.ini /etc/process_monitor/

# Editare configurație
sudo nano /etc/process_monitor/config.ini
```

3. **Configurare ca Serviciu**
```bash
# Creare fișier systemd service
sudo tee /etc/systemd/system/process-monitor.service << EOF
[Unit]
Description=Process Monitor Service
After=network.target mysql.service

[Service]
Type=simple
User=root
WorkingDirectory=/etc/process_monitor
ExecStart=/usr/local/bin/process_monitor.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Activare serviciu
sudo systemctl daemon-reload
sudo systemctl enable process-monitor.service
sudo systemctl start process-monitor.service
```

## Depanare și Troubleshooting

### Verificare Status
```bash
# Status serviciu
sudo systemctl status process-monitor.service

# Vizualizare log-uri
sudo tail -f /var/log/monitor_service.log

# Verificare configurație
sudo /usr/local/bin/process_monitor.sh --config-test
```

### Probleme Comune

#### 1. Erori de Conectare MySQL
- Verificare credențiale în config.ini
- Testare conectivitate: `mysql -h host -u user -p`
- Verificare permisiuni utilizator MySQL

#### 2. Procese Nu Se Repornesc
- Verificare strategie restart în configurație
- Testare manuală: `systemctl restart service_name`
- Verificare log-uri pentru detalii erori

#### 3. Performance Issues
- Optimizare interval verificare
- Verificare dimensiune bază de date
- Monitorizare utilizare resurse

### Optimizări de Performance

1. **Conexiuni MySQL**
   - Utilizare conexiuni cu timeout
   - Compresie date
   - Dezactivare reconnect automat

2. **Logging**
   - Rotație automată pentru evitarea fișierelor mari
   - Nivele de logging configurabile

3. **Circuit Breaker**
   - Previne încărcarea sistemului cu restart-uri eșuate

## Extensibilitate

### Adăugare Strategii Noi de Restart
Modificare funcția `restart_process()` pentru strategii suplimentare:

```bash
"docker")
    docker restart "$process_name"
    ;;
```

### Health Checks Personalizate
Configurare comenzi specifice per proces:

```ini
[process.webapp]
health_check_command=curl -f http://localhost:8080/health
health_check_timeout=15
```

### Integrare cu Sisteme de Alerting
Adăugare funcții pentru trimitere notificări:

```bash
send_alert() {
    local message="$1"
    # Integrare cu Slack, email, etc.
}
```

## Anexe

### Exemplu Complet config.ini

```ini
[database]
host=localhost
user=monitor_user
password=MySecurePassword123
database=monitoring_db

[monitor]
check_interval=30
max_restart_failures=3
circuit_reset_time=300

[logging]
max_log_size=5120
log_files_to_keep=5

[process.default]
restart_strategy=auto
max_attempts=2
restart_delay=2
health_check_timeout=5

[process.apache2]
restart_strategy=service
max_attempts=3
restart_delay=5
health_check_command=curl -f http://localhost/health
health_check_timeout=10
pre_restart_command=echo "Preparing Apache restart" | logger

[process.mysql]
restart_strategy=service
max_attempts=2
restart_delay=10
health_check_command=mysqladmin ping
health_check_timeout=15

[process.custom_app]
restart_strategy=custom
restart_command=/opt/custom_app/restart.sh
max_attempts=2
restart_delay=3
health_check_command=/opt/custom_app/health_check.sh
health_check_timeout=20
pre_restart_command=/opt/custom_app/prepare_restart.sh
```

### Script de Test

```bash
#!/bin/bash
# test_monitor.sh - Script pentru testarea process monitor

# Test conectivitate bază de date
test_database_connection() {
    echo "Testing database connection..."
    # Implementare test
}

# Test configurație
test_configuration() {
    echo "Testing configuration..."
    # Implementare test
}

# Rulare toate testele
test_database_connection
test_configuration
echo "All tests completed."
```
