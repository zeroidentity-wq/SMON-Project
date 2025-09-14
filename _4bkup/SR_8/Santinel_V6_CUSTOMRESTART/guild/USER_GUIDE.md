# Process Monitor Service - User Guide

This guide provides instructions for system administrators on how to install, configure, use, and troubleshoot the Process Monitor Service.

## Table of Contents

1. [Introduction](#introduction)
2. [Installation](#installation)
3. [Configuration](#configuration)
4. [Using the Service](#using-the-service)
5. [Testing](#testing)
6. [Troubleshooting](#troubleshooting)
7. [Maintenance Tasks](#maintenance-tasks)
8. [Frequently Asked Questions](#frequently-asked-questions)

## Introduction

The Process Monitor Service is a system monitoring solution that automatically restarts critical processes when they fail. It works by monitoring a MySQL database for processes in alarm state and taking appropriate action to restart them.

### Key Features

- Automatic process monitoring and restart
- Multiple restart strategies (service, process, auto)
- Health checks to verify successful restarts
- Circuit breaker pattern to prevent excessive restart attempts
- Comprehensive logging with automatic rotation
- Configurable for different processes and environments

## Installation

### Prerequisites

Before installing the Process Monitor Service, ensure your system meets the following requirements:

- RedHat Linux or compatible distribution
- MySQL Server 5.7 or higher
- Bash 4.0 or higher
- systemd

### Installation Steps

1. **Create the Service Directory**

   ```bash
   sudo mkdir -p /opt/monitor_service
   ```

2. **Copy the Service Files**

   ```bash
   sudo cp monitor_service.sh config.ini /opt/monitor_service/
   sudo cp monitor_service.service /etc/systemd/system/
   sudo cp monitor_service.8 /usr/share/man/man8/
   ```

3. **Set Appropriate Permissions**

   ```bash
   sudo chmod 755 /opt/monitor_service
   sudo chmod 700 /opt/monitor_service/monitor_service.sh
   sudo chmod 600 /opt/monitor_service/config.ini
   sudo chown -R root:root /opt/monitor_service
   ```

4. **Set Up the Database**

   ```bash
   # Start MySQL service if not running
   sudo systemctl start mysqld

   # Create database and tables
   sudo mysql < setup.sql
   ```

5. **Configure the Service**

   Edit the configuration file to set your database credentials and other settings:

   ```bash
   sudo nano /opt/monitor_service/config.ini
   ```

   At minimum, update the database credentials in the [database] section.

6. **Enable and Start the Service**

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable monitor_service
   sudo systemctl start monitor_service
   ```

7. **Update Man Pages Database**

   ```bash
   sudo mandb
   ```

### Verifying Installation

To verify that the service is installed and running correctly:

1. **Check Service Status**

   ```bash
   sudo systemctl status monitor_service
   ```

   You should see "active (running)" in the output.

2. **Check Log File**

   ```bash
   sudo tail -f /var/log/monitor_service.log
   ```

   You should see startup messages and periodic database check messages.

## Configuration

The Process Monitor Service is configured through the `config.ini` file located in `/opt/monitor_service/`.

### Basic Configuration

The configuration file is divided into several sections:

#### Database Configuration

```ini
[database]
host = localhost
user = root
password = your_password
database = v_process_monitor
```

Update these settings to match your MySQL database credentials.

#### Monitoring Parameters

```ini
[monitor]
; Check interval in seconds (5 minutes)
check_interval = 300
; Maximum number of restart failures before circuit breaker opens
max_restart_failures = 3
; Circuit breaker reset time in seconds (30 minutes)
circuit_reset_time = 1800
```

These settings control how often the service checks for processes in alarm state and how the circuit breaker behaves.

#### Logging Configuration

```ini
[logging]
; Maximum log file size in KB before rotation (default: 5MB)
max_log_size = 5120
; Number of log files to keep (default: 5)
log_files_to_keep = 5
```

These settings control log rotation behavior.

### Process-Specific Configuration

Each process can have its own configuration section:

```ini
[process.apache2]
restart_strategy = service
pre_restart_command = /usr/sbin/apachectl configtest
health_check_command = systemctl is-active apache2
health_check_timeout = 10
restart_delay = 5
max_attempts = 2
```

#### Configuration Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| restart_strategy | How to restart the process: "service", "process", or "auto" | auto |
| pre_restart_command | Command to run before restart attempt | (none) |
| health_check_command | Command to verify successful restart | pgrep %s |
| health_check_timeout | Maximum time in seconds to wait for health check | 5 |
| restart_delay | Delay in seconds between restart attempts | 2 |
| max_attempts | Maximum number of restart attempts per cycle | 2 |

### Default Process Configuration

You can specify default settings for all processes:

```ini
[process.default]
restart_strategy = auto
health_check_command = pgrep %s
health_check_timeout = 5
restart_delay = 2
max_attempts = 2
```

The `%s` in the health_check_command will be replaced with the actual process name.

### Configuration Examples

#### Web Server Example

```ini
[process.apache2]
restart_strategy = service
pre_restart_command = /usr/sbin/apachectl configtest
health_check_command = curl -s http://localhost/ > /dev/null
health_check_timeout = 15
restart_delay = 5
max_attempts = 3
```

This configuration:
- Uses the service restart strategy
- Runs a configuration test before restarting
- Verifies the restart by checking if the web server responds to HTTP requests
- Allows up to 15 seconds for the health check to pass
- Waits 5 seconds between restart attempts
- Tries up to 3 restart attempts

#### Database Server Example

```ini
[process.mysqld]
restart_strategy = service
health_check_command = mysqladmin -u root -p'password' ping
health_check_timeout = 30
restart_delay = 10
max_attempts = 2
```

This configuration:
- Uses the service restart strategy
- Verifies the restart by checking if MySQL responds to ping
- Allows up to 30 seconds for the health check to pass
- Waits 10 seconds between restart attempts
- Tries up to 2 restart attempts

## Using the Service

### Basic Service Management

- **Start the Service**

  ```bash
  sudo systemctl start monitor_service
  ```

- **Stop the Service**

  ```bash
  sudo systemctl stop monitor_service
  ```

- **Restart the Service**

  ```bash
  sudo systemctl restart monitor_service
  ```

- **Check Service Status**

  ```bash
  sudo systemctl status monitor_service
  ```

### Viewing Logs

- **View Service Logs in Journal**

  ```bash
  sudo journalctl -u monitor_service -f
  ```

- **View Service Log File**

  ```bash
  sudo tail -f /var/log/monitor_service.log
  ```

### Manual Page

The service includes a manual page that can be accessed using:

```bash
man monitor_service
```

## Testing

The service includes testing scripts to help you verify its functionality.

### Interactive Testing with test_alarm.sh

The `test_alarm.sh` script provides an interactive way to test the monitor service:

```bash
chmod +x test_alarm.sh
./test_alarm.sh
```

This script allows you to:
- View all monitored services
- Set specific services in alarm state
- Set all services in alarm state
- Reset all alarms

### Automated Testing with simple_test.sh

For automated testing, use the `simple_test.sh` script:

```bash
chmod +x simple_test.sh
./simple_test.sh
```

This script:
1. Sets a service (apache2) in alarm state
2. Verifies it was set correctly
3. Provides instructions for completing the test by running the monitor service

### Testing Workflow

1. Use one of the test scripts to set a service in alarm state
2. Verify that the monitor service detects the alarm and attempts to restart the service
3. Check the logs to confirm the restart attempt and its outcome
4. Verify that the alarm state is cleared in the database after successful restart

## Troubleshooting

### Common Issues and Solutions

#### Service Won't Start

- **Check Log Files**

  ```bash
  sudo journalctl -u monitor_service
  sudo cat /var/log/monitor_service.log
  ```

  Look for error messages that might indicate the cause of the problem.

- **Verify File Permissions**

  ```bash
  sudo ls -la /opt/monitor_service/
  ```

  Ensure the script is executable and the config file has the correct permissions.

- **Check Configuration**

  ```bash
  sudo cat /opt/monitor_service/config.ini
  ```

  Verify that the configuration file is correctly formatted and contains valid settings.

#### Database Connection Issues

- **Verify MySQL Service**

  ```bash
  sudo systemctl status mysqld
  ```

  Ensure MySQL is running.

- **Check Database Credentials**

  Ensure the credentials in config.ini are correct.

- **Test Database Connection**

  ```bash
  mysql -u root -p -e "USE v_process_monitor; SELECT * FROM PROCESE;"
  ```

  Verify that you can connect to the database and query the tables.

#### Process Restart Failures

- **Check Process Status**

  ```bash
  systemctl status <process_name>
  ```

  Verify that the process exists and can be managed by systemd.

- **Verify Health Check Command**

  Run the health check command manually to see if it works:

  ```bash
  <health_check_command>
  ```

  The command should return exit code 0 if the process is healthy.

- **Check Pre-restart Command**

  If configured, run the pre-restart command manually to verify it works.

### Understanding Log Messages

The log file (/var/log/monitor_service.log) contains detailed information about the service's operation:

- **INFO** level messages indicate normal operation
- **WARNING** level messages indicate potential issues
- **ERROR** level messages indicate failures that require attention
- **DEBUG** level messages provide detailed information for troubleshooting

#### Example Log Messages

- **Service Start**
  ```
  2023-06-15 10:00:00 - INFO - Starting Process Monitor Service
  ```

- **Database Check**
  ```
  2023-06-15 10:05:00 - INFO - Found process in alarm: apache2 (ID: 1)
  ```

- **Restart Attempt**
  ```
  2023-06-15 10:05:01 - INFO - RESTART LOG: Beginning restart procedure for apache2 (strategy: service)
  ```

- **Restart Success**
  ```
  2023-06-15 10:05:10 - INFO - RESTART LOG: Successfully restarted and verified service: apache2
  ```

- **Restart Failure**
  ```
  2023-06-15 10:05:10 - ERROR - RESTART LOG: Service restart command succeeded but health check failed for: apache2
  ```

- **Circuit Breaker**
  ```
  2023-06-15 10:15:10 - WARNING - Circuit breaker opened for apache2 after 3 failures
  ```

## Maintenance Tasks

### Adding a New Process to Monitor

1. **Add the Process to the Database**

   ```sql
   USE v_process_monitor;
   
   -- Add to STATUS_PROCESS table
   INSERT INTO STATUS_PROCESS (process_id, alarma, sound, notes) 
   VALUES (6, 0, 0, 'New process');
   
   -- Add to PROCESE table
   INSERT INTO PROCESE (process_id, process_name) 
   VALUES (6, 'new_process_name');
   ```

2. **Add Process-Specific Configuration (Optional)**

   Edit `/opt/monitor_service/config.ini` and add a new section:

   ```ini
   [process.new_process_name]
   restart_strategy = service
   health_check_command = systemctl is-active new_process_name
   health_check_timeout = 10
   restart_delay = 5
   max_attempts = 2
   ```

3. **Test the Configuration**

   Use the test_alarm.sh script to set the new process in alarm state and verify that the monitor service can restart it.

### Updating the Service

1. **Stop the Service**

   ```bash
   sudo systemctl stop monitor_service
   ```

2. **Backup the Configuration**

   ```bash
   sudo cp /opt/monitor_service/config.ini /opt/monitor_service/config.ini.bak
   ```

3. **Copy the New Files**

   ```bash
   sudo cp monitor_service.sh /opt/monitor_service/
   ```

4. **Set Permissions**

   ```bash
   sudo chmod 700 /opt/monitor_service/monitor_service.sh
   ```

5. **Start the Service**

   ```bash
   sudo systemctl start monitor_service
   ```

### Backing Up the Database

```bash
mysqldump -u root -p v_process_monitor > v_process_monitor_backup.sql
```

### Restoring the Database

```bash
mysql -u root -p v_process_monitor < v_process_monitor_backup.sql
```

## Frequently Asked Questions

### How does the service know which processes to monitor?

The service monitors processes listed in the PROCESE table in the MySQL database. Each process has a corresponding entry in the STATUS_PROCESS table that tracks its alarm state.

### How does the service decide when to restart a process?

The service checks the STATUS_PROCESS table for processes with alarma=1. When it finds a process in alarm state, it attempts to restart it using the configured strategy.

### What is the circuit breaker pattern?

The circuit breaker pattern prevents excessive restart attempts for failing processes. After a configurable number of failures, the circuit breaker "opens" and blocks further restart attempts for a period of time. This prevents resource exhaustion and cascading failures.

### How can I add custom health checks?

You can add custom health checks by configuring the health_check_command parameter for a process. This command should return exit code 0 if the process is healthy, or non-zero if it's unhealthy.

### Can the service monitor processes on remote servers?

The service is designed to monitor and restart processes on the local system. However, you could potentially use SSH commands in the health_check_command and pre_restart_command to interact with remote servers.

### How can I be notified when a process fails?

The service currently logs all restart attempts and failures. You could extend it by adding a notification mechanism, such as sending emails or integrating with a monitoring system.

### What happens if the MySQL database is down?

If the MySQL database is down, the service will log an error and continue trying to connect at the configured check interval. It won't be able to detect or restart processes until the database connection is restored.

### How can I change the check interval?

Edit the config.ini file and update the check_interval parameter in the [monitor] section. The value is in seconds.

```ini
[monitor]
check_interval = 300  # 5 minutes
```

### Can I use this service with non-systemd systems?

Yes, the service supports direct process management using the "process" restart strategy. However, some features may be limited on non-systemd systems.