# Process Monitor Service (Bash Implementation)

## Overview
This service monitors processes by checking their status in a MySQL database and automatically restarts them when they enter an alarm state. Designed specifically for RedHat Linux environments, it provides robust process monitoring and management capabilities with circuit breaker pattern implementation to prevent cascading failures.

```bash
# Verifică drepturile de execuție
chmod +x monitor_service.sh

# Rulează scriptul cu debugging
bash -x ./monitor_service.sh
```

```bash
chmod 644 config.ini
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

3. **Circuit Breaker Pattern**
   - Prevents continuous restart attempts of failing processes
   - Configurable failure thresholds and reset times
   - Automatic circuit reset after cooling period

4. **Logging System**
   - Comprehensive logging to both file (`/var/log/monitor_service.log`) and syslog
   - Detailed timestamp and log level information
   - Process restart attempts and outcomes tracking

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
   - Add process health check endpoints
   - Support for process priority levels

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

## Support

For issues and feature requests, please check the improvement suggestions or create an issue in the repository.
