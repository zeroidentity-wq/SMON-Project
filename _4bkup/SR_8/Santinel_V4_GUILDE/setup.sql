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
-- STATUS_PROCESS: process_id, alarma, sound, notes
INSERT INTO STATUS_PROCESS (process_id, alarma, sound, notes) VALUES
(1, 0, 0, 'SSH server'),
(2, 0, 0, 'Firewall daemon'),
(3, 0, 0, 'Network Manager'),
(4, 0, 0, 'System logging daemon'),
(5, 0, 0, 'NTP client/server'),
(6, 0, 0, 'PolicyKit authorization manager'),
(7, 0, 0, 'User login management'),
(8, 0, 0, 'Printing system'),
(9, 0, 0, 'Mail transfer agent'),
(10, 0, 0, 'Dynamic system tuning daemon'),
(11, 0, 0, 'Audit daemon'),
(12, 0, 0, 'Cron daemon'),
(13, 0, 0, 'Apache HTTP server'),
(14, 0, 0, 'MariaDB database server'),
(15, 0, 0, 'Docker engine'),
(16, 0, 0, 'Podman engine');

-- PROCESE: process_id, process_name
INSERT INTO PROCESE (process_id, process_name) VALUES
(1, 'sshd'),
(2, 'firewalld'),
(3, 'NetworkManager'),
(4, 'rsyslogd'),
(5, 'chronyd'),
(6, 'polkitd'),
(7, 'systemd-logind'),
(8, 'cupsd'),
(9, 'postfix'),
(10, 'tuned'),
(11, 'auditd'),
(12, 'crond'),
(13, 'httpd'),
(14, 'mariadbd'),
(15, 'dockerd'),
(16, 'podman');

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