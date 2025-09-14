-- Create the database if it doesn't exist
CREATE DATABASE IF NOT EXISTS v_process_monitor;

-- Use the database
USE v_process_monitor;

-- STATUS_PROCESS (process_id, alarma, sound, notes)
-- PROCESE (process_id, process_name)

-- Create the STATUS_PROCESS table
CREATE TABLE IF NOT EXISTS STATUS_PROCESS (
    process_id INT PRIMARY KEY,
    alarma TINYINT NOT NULL DEFAULT 0,
    sound TINYINT NOT NULL DEFAULT 0,
    notes VARCHAR(100)
);

-- Create the PROCESE table
CREATE TABLE IF NOT EXISTS PROCESE (
    process_id INT PRIMARY KEY,
    process_name VARCHAR(100) NOT NULL,
    FOREIGN KEY (process_id) REFERENCES STATUS_PROCESS(process_id)
);

-- Insert sample data for testing
-- Sample processes that might exist on a Linux system
INSERT INTO STATUS_PROCESS (process_id, alarma, notes) VALUES
(1, 0, 'Apache web server'),
(2, 1, 'MySQL database server'),
(3, 0, 'SSH server'),
(4, 1, 'Nginx web server'),
(5, 0, 'Cron service');

INSERT INTO PROCESE (process_id, process_name) VALUES
(1, 'apache2'),
(2, 'mysqld'),
(3, 'sshd'),
(4, 'nginx'),
(5, 'cron');

-- Add an index for faster queries
CREATE INDEX idx_alarma ON STATUS_PROCESS(alarma);

-- Show the created tables
SHOW TABLES;

-- Display sample data
SELECT sp.process_id, sp.alarma, p.process_name
FROM STATUS_PROCESS sp
JOIN PROCESE p ON sp.process_id = p.process_id
ORDER BY sp.process_id;

-- Display processes in alarm state (for testing)
SELECT sp.process_id, p.process_name
FROM STATUS_PROCESS sp
JOIN PROCESE p ON sp.process_id = p.process_id
WHERE sp.alarma = 1
ORDER BY sp.process_id;