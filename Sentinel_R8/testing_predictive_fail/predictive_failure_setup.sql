-- Add tables for predictive failure detection

-- Create a table to store historical process status data
CREATE TABLE IF NOT EXISTS PROCESS_HISTORY (
    history_id INT AUTO_INCREMENT PRIMARY KEY,
    process_id INT NOT NULL,
    timestamp DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status TINYINT NOT NULL,  -- 0 = normal, 1 = alarm
    restart_count INT NOT NULL DEFAULT 0,
    response_time FLOAT,  -- in seconds, NULL if not applicable
    cpu_usage FLOAT,      -- percentage, NULL if not collected
    memory_usage FLOAT,   -- percentage, NULL if not collected
    FOREIGN KEY (process_id) REFERENCES STATUS_PROCESS(process_id)
);

-- Create a table to store predictive alerts
CREATE TABLE IF NOT EXISTS PREDICTIVE_ALERTS (
    alert_id INT AUTO_INCREMENT PRIMARY KEY,
    process_id INT NOT NULL,
    timestamp DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    prediction_type VARCHAR(50) NOT NULL,  -- e.g., 'restart_frequency', 'resource_usage', etc.
    confidence FLOAT NOT NULL,  -- 0.0 to 1.0
    description TEXT NOT NULL,
    acknowledged TINYINT NOT NULL DEFAULT 0,
    resolved TINYINT NOT NULL DEFAULT 0,
    FOREIGN KEY (process_id) REFERENCES STATUS_PROCESS(process_id)
);

-- Create indexes for better query performance
CREATE INDEX idx_process_history_process_id ON PROCESS_HISTORY(process_id);
CREATE INDEX idx_process_history_timestamp ON PROCESS_HISTORY(timestamp);
CREATE INDEX idx_predictive_alerts_process_id ON PREDICTIVE_ALERTS(process_id);
CREATE INDEX idx_predictive_alerts_timestamp ON PREDICTIVE_ALERTS(timestamp);

-- Add a column to STATUS_PROCESS to indicate predictive alert status
ALTER TABLE STATUS_PROCESS ADD COLUMN IF NOT EXISTS predictive_alert TINYINT NOT NULL DEFAULT 0;