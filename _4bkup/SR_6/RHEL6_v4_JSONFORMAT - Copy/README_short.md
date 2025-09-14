# Process Monitor Service

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

# Dacă apar CRLF-uri pe fișierele copiate din Windows
sed -i 's/\r$//' monitor_service.sh config.ini monitor_service.conf test_alarm.sh
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

#### Manual page for service
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
<hr>  

#### TO DO Audit modificări fișiere (auditd)

Pentru a înregistra cine și când modifică `monitor_service.sh` sau fișierele de configurare, folosește Linux Audit (auditd). Aceasta oferă detalii precum utilizatorul de login original (auid), procesul care a făcut modificarea, timpul exact și terminalul/IP-ul.

1) Verifică/pornește auditd
```bash
sudo auditctl -s
# Dacă nu rulează, instalează și pornește serviciul auditd conform distribuției tale
```

2) Adaugă reguli persistente pentru fișiere
```bash
echo '-w /opt/monitor_service/monitor_service.sh -p wa -k monitor_service_changes' | sudo tee /etc/audit/rules.d/monitor_service.rules
echo '-w /opt/monitor_service/config.ini -p wa -k monitor_service_changes' | sudo tee -a /etc/audit/rules.d/monitor_service.rules
sudo augenrules --load
```
- `-w`: urmărește calea fișierului
- `-p wa`: loghează write și schimbări de atribute (chmod/chown etc.)
- `-k`: cheie (tag) pentru căutare ușoară

Opțional: monitorizează întregul director
```bash
echo '-w /opt/monitor_service -p wa -k monitor_service_changes' | sudo tee /etc/audit/rules.d/monitor_service.rules
sudo augenrules --load
```

3) Testează și investighează evenimentele
```bash
# După o modificare a fișierului, caută evenimentele marcate cu key-ul setat
sudo ausearch -k monitor_service_changes -i

# Rapoarte sumare pe fișiere
sudo aureport -f -i --summary
```

4) Trimitere către syslog (opțional)
- Instalează/activează pluginurile audispd (ex. pachetul „audispd-plugins”).
- Activează `syslog` în `/etc/audisp/plugins.d/syslog.conf` (set `active = yes`).
- Evenimentele audit pot fi apoi procesate/alertate de rsyslog.

Note:
- `auid` este identitatea de login inițială (utilă când s-a folosit `sudo`).
- Pentru protecție temporară poți bloca modificările: `sudo chattr +i /opt/monitor_service/monitor_service.sh` (dezactivezi cu `sudo chattr -i ...`).

#### TO DO : Restart comenzi multiple
`&&` pentru “execută următoarea doar dacă cea anterioară reușește”  
`;` pentru “execută indiferent”  
`||` pentru “execută următoarea doar dacă anterioara eșuează”

#### Random test-alarm

```bash
./test_alarm.sh --random --min-delay 10 --max-delay 30 --max-at-once 2 &
```

#### De ce JSON pentru log-uri
Structurat și ușor de procesat: Fiecare câmp are cheie/valoare; unelte (ELK/OpenSearch, Loki/Grafana, Splunk) pot indexa instant fără regex fragile.
 
### JSON logging (config și utilizare)

- Config în `[logging]` din `config.ini`:
  - `format = json` sau `text`
  - `json_pretty = false` (dacă e `true` și există `jq`, consola va afișa pretty, fișierul rămâne one-line)

- Output-ul ajunge în ` /var/log/monitor_service.log` și syslog pentru nivelurile `ERROR/CRITICAL`.

- Exemple cu `jq`:
  ```bash
  # Doar erori
  jq 'select(.level=="error")' /var/log/monitor_service.log

  # Probe/Evenimente lente (dacă există duration_ms)
  jq 'select(.duration_ms!=null and .duration_ms>5000)' /var/log/monitor_service.log

  # Filtrare după serviciu și corelare
  jq 'select(.service=="monitor_service" and .corr_id=="abc123")' /var/log/monitor_service.log
  ```

- Format tipic JSON emis:
  ```json
  {"timestamp":"2025-09-09T10:25:13.482Z","level":"info","service":"monitor_service","host":"srv-01","pid":1234,"message":"Probe completed"}
  ```
