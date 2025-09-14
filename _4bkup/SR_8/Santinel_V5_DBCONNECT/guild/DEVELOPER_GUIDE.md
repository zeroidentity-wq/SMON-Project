# Process Monitor Service - Developer Guide

This document provides detailed technical information for developers working on the Process Monitor Service. It covers code structure, key functions, design patterns, and guidelines for extending the service.

## Code Structure

### Main Components

The Process Monitor Service consists of the following key files:

1. **monitor_service.sh**: Main service script
2. **config.ini**: Configuration file
3. **monitor_service.service**: Systemd service definition
4. **setup.sql**: Database setup script
5. **test_alarm.sh**: Interactive testing script
6. **simple_test.sh**: Non-interactive testing script

### Script Organization

The `monitor_service.sh` script is organized into functional sections:

1. **Configuration Management**: Functions for reading and validating configuration
2. **Logging**: Functions for logging and log rotation
3. **Database Interaction**: Functions for querying and updating the database
4. **Process Management**: Functions for restarting processes using different strategies
5. **Circuit Breaker Implementation**: Functions for managing the circuit breaker pattern
6. **Main Loop**: The main monitoring loop that ties everything together

## Key Functions

### Configuration Management

#### `read_config()`

Reads and validates configuration from the config.ini file.

```bash
# Read configuration from config.ini
read_config() {
    # Validate config file exists
    # Parse database section
    # Parse monitor section
    # Parse logging section
    # Set defaults for missing values
    # Validate required values
    # Verify numeric values
}
```

#### `get_process_config()`

Retrieves process-specific configuration with fallback to defaults.

```bash
# Get process-specific configuration
get_process_config() {
    local process_name="$1"
    local param="$2"
    local default_value="$3"
    
    # Try process-specific setting
    # Fall back to default process settings
    # Fall back to provided default
}
```

### Logging

#### `log()`

Writes log messages with timestamp and level.

```bash
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Check if log rotation is needed
    # Write to log file and stdout
}
```

#### `check_log_rotation()`

Checks if log rotation is needed based on file size.

```bash
check_log_rotation() {
    # Check if log file exists
    # Get file size
    # Compare with maximum size
}
```

#### `rotate_logs()`

Rotates log files when the maximum size is reached.

```bash
rotate_logs() {
    # Remove oldest log file if it exists
    # Rotate existing log files
    # Rotate current log file
    # Create new empty log file
    # Log rotation event
}
```

### Database Interaction

#### `create_mysql_config()`

Creates a temporary MySQL configuration file for secure database access.

```bash
create_mysql_config() {
    # Create empty file
    # Set secure permissions
    # Write MySQL configuration
}
```

#### `get_alarm_processes()`

Queries the database for processes in alarm state.

```bash
get_alarm_processes() {
    # Query database for processes with alarma=1 and sound=0
    # Return process_id, process_name, alarma, sound, notes
}
```

#### `update_alarm_status()`

Updates the database to clear the alarm state after successful restart.

```bash
update_alarm_status() {
    local process_id="$1"
    # Update database to set alarma=0 and add restart note
}
```

### Process Management

#### `get_restart_strategy()`

Determines the restart strategy for a process.

```bash
get_restart_strategy() {
    local process_name="$1"
    # Get restart strategy from configuration
}
```

#### `restart_process()`

Attempts to restart a process using the configured strategy.

```bash
restart_process() {
    local process_name="$1"
    # Get restart strategy, max attempts, and restart delay
    # Execute pre-restart command if configured
    # Attempt restart using the appropriate strategy
    # Perform health check after restart
}
```

#### `execute_pre_restart()`

Executes a pre-restart command if configured.

```bash
execute_pre_restart() {
    local process_name="$1"
    # Get pre-restart command from configuration
    # Execute command if configured
}
```

#### `perform_health_check()`

Verifies successful restart using the configured health check command.

```bash
perform_health_check() {
    local process_name="$1"
    # Get health check command and timeout
    # Replace %s with process name if present
    # Try health check with timeout and retries
}
```

### Circuit Breaker Implementation

#### `check_circuit_breaker()`

Checks if the circuit breaker is open for a process.

```bash
check_circuit_breaker() {
    local process_name="$1"
    # Initialize if not exists
    # Check if circuit breaker is open
    # Reset if enough time has passed
}
```

#### `update_circuit_breaker()`

Updates the circuit breaker state based on restart success/failure.

```bash
update_circuit_breaker() {
    local process_name="$1"
    local success="$2"
    # Increment failure count on failure
    # Open circuit breaker if failure threshold reached
    # Reset failure count on success
}
```

## Design Patterns

### Circuit Breaker Pattern

The service implements the circuit breaker pattern to prevent excessive restart attempts for failing processes:

1. **Closed State**: Normal operation, restart attempts are allowed
2. **Open State**: After multiple failures, restart attempts are blocked
3. **Reset Mechanism**: Circuit breaker automatically resets after a configured time period

Implementation details:

```bash
# Circuit breaker implementation
declare -A circuit_breaker
declare -A failure_counts
declare -A last_failure_times

check_circuit_breaker() {
    # Implementation details
}

update_circuit_breaker() {
    # Implementation details
}
```

### Strategy Pattern

The service uses a strategy pattern for process restart, supporting multiple restart strategies:

1. **service**: Uses systemd to restart the process as a service
2. **process**: Directly kills and restarts the process
3. **auto**: Tries service restart first, then falls back to process restart

Implementation details:

```bash
restart_process() {
    local process_name="$1"
    local strategy=$(get_restart_strategy "$process_name")
    
    case "$strategy" in
        "service")
            # Service restart strategy
            ;;
        "process")
            # Process restart strategy
            ;;
        "auto"|*)
            # Auto restart strategy
            ;;
    esac
}
```

## Security Considerations

### Database Credentials

The service handles database credentials securely:

1. Credentials are read from the config.ini file
2. A temporary file with secure permissions is created for MySQL authentication
3. The temporary file is cleaned up when the script exits

```bash
# Temporary MySQL config file
MYSQL_TEMP_CONFIG=$(mktemp)

# Function to create MySQL config file
create_mysql_config() {
    # Implementation details
}

# Function to clean up temporary MySQL config file
cleanup_mysql_config() {
    # Implementation details
}

# Set up trap to clean up on exit
trap cleanup_mysql_config EXIT
```

### File Permissions

The service requires specific file permissions:

1. The script itself should be executable only by root: `chmod 700`
2. The config.ini file should be readable only by root: `chmod 600`
3. The log file should be writable by the service but readable by others: `chmod 644`

## Error Handling

The service implements robust error handling:

1. **Configuration Validation**: Validates all configuration parameters
2. **Database Connection Errors**: Logs errors and continues operation
3. **Restart Failures**: Implements circuit breaker to prevent excessive restart attempts
4. **Health Check Failures**: Logs failures and considers the restart unsuccessful

## Extending the Service

### Adding New Restart Strategies

To add a new restart strategy:

1. Add a new case in the `restart_process()` function
2. Implement the restart logic for the new strategy
3. Update the documentation to describe the new strategy

Example:

```bash
restart_process() {
    # Existing code...
    
    case "$strategy" in
        # Existing strategies...
        
        "new_strategy")
            # Implement new restart strategy
            ;;
    esac
    
    # Existing code...
}
```

### Adding New Configuration Options

To add new configuration options:

1. Add the option to the appropriate section in config.ini
2. Update the `read_config()` function to parse the new option
3. Add validation for the new option
4. Update the documentation to describe the new option

Example:

```bash
# In read_config()
NEW_OPTION=$(sed -n '/^\[section\]/,/^\[/p' "$CONFIG_FILE" | grep "^new_option[[:space:]]*=" | cut -d'=' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
NEW_OPTION=${NEW_OPTION:-default_value}  # Set default if not specified

# Validate
if ! [[ "$NEW_OPTION" =~ ^[0-9]+$ ]]; then
    log "ERROR" "Invalid value for new_option: $NEW_OPTION"
    exit 1
fi

# Export for use in script
export NEW_OPTION
```

### Adding Database Fields

To add new fields to the database:

1. Update the setup.sql script to include the new fields
2. Update the `get_alarm_processes()` function to include the new fields
3. Update any other database functions that need to use the new fields
4. Update the documentation to describe the new fields

Example:

```bash
# In get_alarm_processes()
mysql --defaults-file="$MYSQL_TEMP_CONFIG" -N <<EOF
SELECT CONCAT(p.process_id, '|', p.process_name, '|', s.alarma, '|', s.sound, '|', s.new_field, '|', s.notes)
FROM STATUS_PROCESS s
JOIN PROCESE p ON s.process_id = p.process_id
WHERE s.alarma = 1 AND s.sound = 0;
EOF
```

## Testing Guidelines

### Unit Testing

For testing individual functions:

1. Create a test script that sources the main script but doesn't run the main loop
2. Override the database functions to use test data
3. Call the function to be tested with various inputs
4. Verify the outputs match expected results

Example:

```bash
#!/bin/bash
# Source the main script but don't run main
source ./monitor_service.sh

# Override database functions
get_alarm_processes() {
    echo "1|test_process|1|0|Test notes"
}

# Test restart_process function
restart_process "test_process"
# Verify results
```

### Integration Testing

For testing the entire service:

1. Use the test_alarm.sh script to set processes in alarm state
2. Run the monitor_service.sh script
3. Verify that the processes are restarted and the alarm state is cleared
4. Check the logs for expected messages

Example:

```bash
# Set a process in alarm state
./test_alarm.sh  # Select option 2, then process ID 1

# In another terminal, run the service
sudo ./monitor_service.sh

# Verify the process was restarted and alarm cleared
mysql -u root -p -e "USE v_process_monitor; SELECT alarma FROM STATUS_PROCESS WHERE process_id = 1;"
# Should return 0
```

## Performance Considerations

### Database Queries

The service minimizes database load:

1. Queries run only at the configured check interval
2. Efficient SQL queries with JOIN operations
3. Only processes in alarm state are retrieved

### Process Management

The service is designed for efficient process management:

1. Uses systemd when possible for reliable service management
2. Implements health checks to verify successful restarts
3. Uses circuit breaker to prevent excessive restart attempts

### Memory Usage

The service has minimal memory requirements:

1. Uses associative arrays for circuit breaker state
2. Cleans up temporary files
3. Implements log rotation to prevent disk space issues

## Troubleshooting for Developers

### Debugging

To debug the service:

1. Run the script with bash debugging:
   ```bash
   bash -x ./monitor_service.sh
   ```

2. Add additional debug logging:
   ```bash
   log "DEBUG" "Variable value: $variable"
   ```

3. Check the database state:
   ```bash
   mysql -u root -p -e "USE v_process_monitor; SELECT * FROM STATUS_PROCESS JOIN PROCESE USING (process_id);"
   ```

### Common Development Issues

1. **Permission Denied**: Ensure the script has execute permissions and is run as root
2. **Database Connection Failures**: Verify database credentials and connectivity
3. **Process Restart Failures**: Check if the process exists and can be restarted
4. **Health Check Failures**: Verify the health check command works correctly

## Code Style Guidelines

1. **Function Names**: Use lowercase with underscores (snake_case)
2. **Variable Names**: Use uppercase for global variables, lowercase for local variables
3. **Indentation**: Use 4 spaces for indentation
4. **Comments**: Add comments for complex logic and function descriptions
5. **Error Handling**: Check return codes and handle errors appropriately
6. **Logging**: Use appropriate log levels (INFO, WARNING, ERROR, DEBUG)

## Version Control Guidelines

1. **Commit Messages**: Use clear, descriptive commit messages
2. **Branching**: Create feature branches for new features
3. **Testing**: Test changes before committing
4. **Documentation**: Update documentation when making changes

## Conclusion

This developer guide provides a comprehensive overview of the Process Monitor Service code structure, key functions, design patterns, and guidelines for extending the service. By following these guidelines, developers can maintain and extend the service in a consistent and reliable manner.