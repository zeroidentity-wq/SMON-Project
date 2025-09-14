# Process Monitor Service (Bash Implementation)

## Overview
This service monitors processes by checking their status in a MySQL database and automatically restarts them when they enter an alarm state. Designed specifically for RedHat Linux environments, it provides robust process monitoring and management capabilities with circuit breaker pattern implementation to prevent cascading failures.
> Database queries in `monitor_service.sh` were optimized by adding connection handling options to ensure quick closure after each query. Changes included `--connect-timeout=5`, `--quick`, `--compress`, and `--reconnect=FALSE` for both query functions. This prevents connection congestion from frequent queries.


## Instalare

### 1. Pregătirea sistemului

```bash
# Actualizarea sistemului
sudo dnf update -y

# Instalarea dependențelor necesare
sudo dnf install -y mysql-server mysql-client
```

### 2. Configurarea directorului de serviciu

```bash
# Crearea directorului pentru serviciu
sudo mkdir -p /opt/monitor_service

# Copierea fișierelor necesare
sudo cp monitor_service.sh /opt/monitor_service/
sudo cp config.ini /opt/monitor_service/

# Setarea permisiunilor
sudo chmod 755 /opt/monitor_service
sudo chmod 700 /opt/monitor_service/monitor_service.sh
sudo chmod 600 /opt/monitor_service/config.ini
```

### 3. Configurarea MySQL

```bash
# Pornirea serviciului MySQL
sudo systemctl enable mysqld
sudo systemctl start mysqld

# Rularea scriptului de configurare
sudo mysql < setup.sql
```

### 4. Configurarea serviciului systemd

```bash
# Copierea fișierului de serviciu
sudo cp monitor_service.service /etc/systemd/system/

# Reîncărcarea daemon-ului systemd
sudo systemctl daemon-reload

# Activarea și pornirea serviciului
sudo systemctl enable monitor_service
sudo systemctl start monitor_service
```

```bash
sudo cp monitor_service.8 /usr/share/man/man8/
sudo mandb
man monitor_service
```

```bash
# Verifică drepturile de execuție
chmod +x monitor_service.sh

# Rulează scriptul cu debugging
bash -x ./monitor_service.sh
```

```bash
chmod 644 config.ini
```

Probleme cu permisiunile:
   ```bash
   sudo chown -R root:root /opt/monitor_service
   sudo chmod 700 /opt/monitor_service/monitor_service.sh
   sudo chmod 600 /opt/monitor_service/config.ini
   ```


## Core Functionality
1. **Database Monitoring**
   - Continuously monitors MySQL database for processes in alarm state
   - Tracks process status through STATUS_PROCESS and PROCESE tables
   - Uses efficient SQL queries with JOIN operations

2. **Process Management**
   - Primary method: systemd service management via `systemctl`
   - Fallback method: direct process management using `pkill` and process restart
   - Intelligent handling of both service and standalone processes
   - Health checks after restarts to verify successful recovery

3. **Circuit Breaker Pattern**
   - Prevents continuous restart attempts of failing processes
   - Configurable failure thresholds and reset times
   - Automatic circuit reset after cooling period

4. **Logging System**
   - Comprehensive logging to both file (`/var/log/monitor_service.log`) and syslog
   - Detailed timestamp and log level information
   - Process restart attempts and outcomes tracking
   - Automatic log rotation based on file size
   - Configurable number of log files to keep

## Dependencies
- MySQL Client (`mysql-client` package)
- Bash 4.0 or higher (for associative arrays)
- systemd (for service management)
- Standard Linux utilities (`awk`, `date`, `pkill`)

## Configuration
The service uses `config.ini` with the following sections:

```ini
[database]
host = localhost
user = root
password = your_password
database = v_process_monitor

[monitor]
check_interval = 300        # Check interval in seconds
max_restart_failures = 3    # Maximum restart attempts before circuit breaker opens
circuit_reset_time = 1800   # Time in seconds before circuit breaker resets

[logging]
max_log_size = 5120         # Maximum log file size in KB before rotation (5MB)
log_files_to_keep = 5       # Number of rotated log files to keep

[process.example]
restart_strategy = service  # Strategy: service, process, or auto
pre_restart_command = /path/to/validation/script  # Command to run before restart
health_check_command = systemctl is-active example  # Command to verify successful restart
health_check_timeout = 10   # Maximum time in seconds to wait for health check to pass
restart_delay = 5           # Delay between restart attempts
max_attempts = 2            # Maximum number of restart attempts per cycle
```

### Health Check Configuration
Each process can have a custom health check command that verifies if the process is running correctly after a restart:

- **health_check_command**: Command to run to verify process health (returns 0 for success)
- **health_check_timeout**: Maximum time in seconds to wait for the health check to pass

For the default section, you can use `%s` as a placeholder for the process name:
```ini
[process.default]
health_check_command = pgrep %s  # Will be replaced with actual process name
health_check_timeout = 5
```

## Installation

1. **Create Service Directory:**
```bash
sudo mkdir -p /opt/monitor_service
```

2. **Copy Files:**
```bash
sudo cp monitor_service.sh config.ini /opt/monitor_service/
sudo chmod +x /opt/monitor_service/monitor_service.sh
```

3. **Install Service:**
```bash
sudo cp monitor_service.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable monitor_service
sudo systemctl start monitor_service
```

## Service Management

- **Start Service:**
  ```bash
  sudo systemctl start monitor_service
  ```

- **Check Status:**
  ```bash
  sudo systemctl status monitor_service
  ```

- **View Logs:**
  ```bash
  sudo journalctl -u monitor_service -f
  ```

- **Stop Service:**
  ```bash
  sudo systemctl stop monitor_service
  ```

## Database Schema Requirements

### Table: STATUS_PROCESS
```sql
CREATE TABLE STATUS_PROCESS (
    process_id INT PRIMARY KEY,
    alarma TINYINT,
    sound TINYINT,
    notes TEXT
);
```

### Table: PROCESE
```sql
CREATE TABLE PROCESE (
    process_id INT PRIMARY KEY,
    process_name VARCHAR(255)
);
```

## Improvement Suggestions

1. **Enhanced Security**
   - Implement encrypted storage for database credentials
   - Add support for MySQL SSL connections
   - Run service with minimal required permissions

2. **Monitoring Enhancements**
   - Add email/SMS notifications for critical failures
   - Implement process resource monitoring (CPU, Memory)
   - Add process uptime tracking
   - Include process dependency management

3. **System Integration**
   - Add support for containerized processes
   - Implement API endpoints for status monitoring
   - Add support for clustering and high availability

4. **Configuration Management**
   - Add dynamic configuration reloading
   - Support for YAML/JSON configuration formats
   - Environment variable override support

5. **Logging and Metrics**
   - Add structured logging (JSON format)
   - Implement metrics collection for Prometheus
   - Add log rotation and archiving
   - Create dashboard templates for monitoring

6. **Process Management**
   - Add custom restart strategies per process
   - Implement graceful shutdown procedures
   - Support for process priority levels
   - Extend health check capabilities with HTTP/API endpoint checks

7. **Circuit Breaker Enhancements**
   - Add half-open state for circuit breaker
   - Implement different circuit breaker strategies
   - Add circuit breaker metrics and monitoring

8. **Database Optimizations**
   - Add connection pooling
   - Implement retry mechanisms for database operations
   - Add support for multiple database backends

9. **Testing and Validation**
   - Add unit tests for core functions
   - Create integration test suite
   - Add automated deployment tests
   - Implement chaos testing scenarios

## Troubleshooting

1. **Service Won't Start**
   - Check log files in `/var/log/monitor_service.log`
   - Verify database connectivity
   - Check file permissions

2. **Database Connection Issues**
   - Verify MySQL credentials
   - Check MySQL server status
   - Verify network connectivity

3. **Process Restart Failures**
   - Check process executable permissions
   - Verify service user permissions
   - Review systemd service configuration
