# Process Monitor Service - Ghid de Utilizare

Acest ghid oferă instrucțiuni pentru administratorii de sistem despre cum să instaleze, configureze, utilizeze și să depaneze Process Monitor Service.

## Cuprins

1. [Introducere](#introducere)
2. [Instalare](#instalare)
3. [Configurare](#configurare)
4. [Utilizarea Serviciului](#utilizarea-serviciului)
5. [Testare](#testare)
6. [Depanare](#depanare)
7. [Întrebări Frecvente](#întrebări-frecvente)

## Introducere

Process Monitor Service este o soluție de monitorizare a sistemului care repornește automat procesele critice atunci când acestea eșuează. Funcționează prin monitorizarea unei baze de date MySQL pentru procesele în stare de alarmă și luarea măsurilor adecvate pentru a le reporni.

### Caracteristici Principale

- Monitorizarea și repornirea automată a proceselor
- Strategii multiple de repornire (service, process, auto)
- Heath Check pentru a confirma repornirile reușite
- Model circuit breaker pentru a preveni încercările excesive de repornire
- Jurnalizare cuprinzătoare cu rotație automată
- Configurabil pentru diferite procese și medii

## Instalare

### Cerințe Preliminare

Înainte de a instala Process Monitor Service, asigurați-vă că sistemul dvs. îndeplinește următoarele cerințe:

- RedHat Linux sau o distribuție compatibilă
- MySQL Server 5.7 sau mai nou
- User MySQL cu privilegii minime de SELECT
- Bash 4.0 sau mai nou
- systemd

### Pași de Instalare

1. **Creați Directorul Serviciului**

   ```bash
   sudo mkdir -p /opt/monitor_service
   ```

2. **Copiați Fișierele Serviciului**

   ```bash
   sudo cp monitor_service.sh config.ini /opt/monitor_service/
   sudo cp monitor_service.service /etc/systemd/system/
   sudo cp monitor_service.8 /usr/share/man/man8/
   ```

3. **Setați Permisiunile Corespunzătoare**

   ```bash
   sudo chmod 755 /opt/monitor_service
   sudo chmod 700 /opt/monitor_service/monitor_service.sh
   sudo chmod 600 /opt/monitor_service/config.ini
   sudo chown -R root:root /opt/monitor_service
   ```

4. **Configurați Baza de Date [Mediul de testare]**

   ```bash
   # Porniți serviciul MySQL dacă nu rulează
   sudo systemctl start mysqld

   # Creați baza de date și tabelele
   sudo mysql < setup.sql
   ```

5. **Configurați Serviciul**

   Editați fișierul de configurare pentru a seta serviciul:

   ```bash
   sudo vim /opt/monitor_service/config.ini
   ```

6. **Activați și Porniți Serviciul**

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable monitor_service
   sudo systemctl start monitor_service
   ```

7. **Actualizați Baza de Date a Paginilor de Manual**

   ```bash
   sudo mandb
   ```

### Verificarea Instalării

Pentru a verifica dacă serviciul este instalat și rulează corect:

1. **Verificați Starea Serviciului**

   ```bash
   sudo systemctl status monitor_service
   ```

   Ar trebui să vedeți "active (running)" în rezultat.

2. **Verificați Fișierul de Jurnal**

   ```bash
   sudo tail -f /var/log/monitor_service.log
   ```

   Ar trebui să vedeți mesaje de pornire și mesaje periodice de verificare a bazei de date.

## Configurare

Process Monitor Service este configurat prin fișierul `config.ini` localizat în `/opt/monitor_service/`.

### Configurare de Bază

Fișierul de configurare este împărțit în mai multe secțiuni:

#### Configurarea Bazei de Date

```ini
[database]
host = localhost
user = user
password = your_password
database = v_process_monitor
```

Actualizați aceste setări pentru a se potrivi cu credențialele bazei de date MySQL.

#### Parametri de Monitorizare

```ini
[monitor]
; Check interval in seconds (5 minutes)
check_interval = 300
; Maximum number of restart failures before circuit breaker opens
max_restart_failures = 3
; Circuit breaker reset time in seconds (30 minutes)
circuit_reset_time = 1800
```

Aceste setări controlează cât de des serviciul verifică procesele în stare de alarmă și cum se comportă circuit breaker-ul.

#### Configurarea Jurnalizării

```ini
[logging]
; Maximum log file size in KB before rotation (default: 5MB)
max_log_size = 5120
; Number of log files to keep (default: 5)
log_files_to_keep = 5
```

Aceste setări controlează comportamentul rotației jurnalelor.

### Configurare Specifică Proceselor

Fiecare proces poate avea propria secțiune de configurare:

```ini
[process.apache2]
restart_strategy = service
pre_restart_command = /usr/sbin/apachectl configtest
health_check_command = systemctl is-active apache2
health_check_timeout = 10
restart_delay = 5
max_attempts = 2
```

#### Parametri de Configurare

| Parametru | Descriere | Implicit |
|-----------|-------------|---------|
| system_name | Numele real al serviciului daca diferă | (numele găsit în baza de date) |
| restart_strategy | Cum să repornească procesul: "service", "process", sau "auto" | auto |
| pre_restart_command | Comandă de rulat înainte de încercarea de repornire (opţional) | (niciunul) |
| restart_command | Comandă de restart (pentru strategia custom) | (niciunul) |
| health_check_command | Comandă pentru a verifica repornirea cu succes | pgrep %s |
| health_check_timeout | Timpul maxim în secunde de așteptare pentru health check | 5 |
| restart_delay | Întârziere în secunde între încercările de repornire | 2 |
| max_attempts | Numărul maxim de încercări de repornire per ciclu | 2 |

### Configurare Implicită pentru Procese

Puteți specifica setări implicite pentru toate procesele:

```ini
[process.default]
restart_strategy = auto
health_check_command = pgrep %s
health_check_timeout = 5
restart_delay = 2
max_attempts = 2
```

`%s` din health_check_command va fi înlocuit cu numele real al procesului.

### Exemple de Configurare

#### Exemplu Server Web

```ini
[process.apache2]
restart_strategy = service
pre_restart_command = /usr/sbin/apachectl configtest
health_check_command = curl -s http://localhost/ > /dev/null
health_check_timeout = 15
restart_delay = 5
max_attempts = 3
```

Această configurare:
- Utilizează strategia de repornire service
- Rulează un test de configurare înainte de repornire
- Verifică repornirea verificând dacă serverul web răspunde la cereri HTTP
- Permite până la 15 secunde pentru ca health check să treacă
- Așteaptă 5 secunde între încercările de repornire
- Încearcă până la 3 încercări de repornire

#### Exemplu Server de Baze de Date

```ini
[process.mysqld]
restart_strategy = service
health_check_command = mysqladmin -u root -p'password' ping
health_check_timeout = 30
restart_delay = 10
max_attempts = 2
```

Această configurare:
- Utilizează strategia de repornire service
- Verifică repornirea verificând dacă MySQL răspunde la ping
- Permite până la 30 de secunde pentru ca health check să treacă
- Așteaptă 10 secunde între încercările de repornire
- Încearcă până la 2 încercări de repornire

## Utilizarea Serviciului

### Gestionarea de Bază a Serviciului

- **Pornirea Serviciului**

  ```bash
  sudo systemctl start monitor_service
  ```

- **Oprirea Serviciului**

  ```bash
  sudo systemctl stop monitor_service
  ```

- **Repornirea Serviciului**

  ```bash
  sudo systemctl restart monitor_service
  ```

- **Verificarea Stării Serviciului**

  ```bash
  sudo systemctl status monitor_service
  ```

### Vizualizarea Jurnalelor

- **Vizualizarea Jurnalelor Serviciului în Journal**

  ```bash
  sudo journalctl -u monitor_service -f
  ```

- **Vizualizarea Fișierului Jurnal al Serviciului**

  ```bash
  sudo tail -f /var/log/monitor_service.log
  ```

### Pagina de Manual

Serviciul include o pagină de manual care poate fi accesată folosind:

```bash
man monitor_service
```

## Testare

Serviciul include scripturi de testare pentru a vă ajuta să verificați funcționalitatea sa.

### Testare Interactivă cu test_alarm.sh

Scriptul `test_alarm.sh` oferă o modalitate interactivă de a testa serviciul de monitorizare:

```bash
chmod +x test_alarm.sh
./test_alarm.sh
```

Acest script vă permite să:
- Vizualizați toate serviciile monitorizate
- Setați servicii specifice în stare de alarmă
- Setați toate serviciile în stare de alarmă
- Resetați toate alarmele

### Flux de Testare

1. Utilizați unul dintre scripturile de testare pentru a seta un serviciu în stare de alarmă
2. Verificați dacă serviciul de monitorizare detectează alarma și încearcă să repornească serviciul
3. Verificați jurnalele pentru a confirma încercarea de repornire și rezultatul acesteia
4. Verificați dacă starea de alarmă este ștearsă din baza de date după repornirea cu succes

## Depanare

### Probleme Comune și Soluții

#### Serviciul Nu Pornește

- **Verificați Fișierele de Jurnal**

  ```bash
  sudo journalctl -u monitor_service
  sudo cat /var/log/monitor_service.log
  ```

  Căutați mesaje de eroare care ar putea indica cauza problemei.

- **Verificați Permisiunile Fișierelor**

  ```bash
  sudo ls -la /opt/monitor_service/
  ```

  Asigurați-vă că scriptul este executabil și fișierul de configurare are permisiunile corecte.

- **Verificați Configurația**

  ```bash
  sudo cat /opt/monitor_service/config.ini
  ```

  Verificați dacă fișierul de configurare este formatat corect și conține setări valide.

#### Probleme de Conexiune la Baza de Date

- **Verificați Serviciul MySQL**

  ```bash
  sudo systemctl status mysqld
  ```

  Asigurați-vă că MySQL rulează.

### Înțelegerea Mesajelor de Jurnal

Fișierul de jurnal (**/var/log/monitor_service.log**) conține informații detaliate despre operațiunea serviciului:

- Mesajele de nivel **INFO** indică operarea normală
- Mesajele de nivel **WARNING** indică probleme potențiale
- Mesajele de nivel **ERROR** indică eșecuri care necesită atenție
- Mesajele de nivel **DEBUG** oferă informații detaliate pentru depanare

#### Exemple de Mesaje de Jurnal

- **Pornirea Serviciului**
  ```
  2023-06-15 10:00:00 - INFO - Starting Process Monitor Service
  ```

- **Verificarea Bazei de Date**
  ```
  2023-06-15 10:05:00 - INFO - Found process in alarm: apache2 (ID: 1)
  ```

- **Încercare de Repornire**
  ```
  2023-06-15 10:05:01 - INFO - RESTART LOG: Beginning restart procedure for apache2 (strategy: service)
  ```

- **Repornire cu Succes**
  ```
  2023-06-15 10:05:10 - INFO - RESTART LOG: Successfully restarted and verified service: apache2
  ```

- **Eșec de Repornire**
  ```
  2023-06-15 10:05:10 - ERROR - RESTART LOG: Service restart command succeeded but health check failed for: apache2
  ```

- **Circuit Breaker**
  ```
  2023-06-15 10:15:10 - WARNING - Circuit breaker opened for apache2 after 3 failures
  ```

## Întrebări Frecvente

### Cum știe serviciul ce procese să monitorizeze?

Serviciul monitorizează procesele listate în tabelul **PROCESE** din baza de date MySQL. Fiecare proces are o intrare corespunzătoare în tabelul **STATUS_PROCESS** care îi urmărește starea de alarmă.

### Cum decide serviciul când să repornească un proces?

Serviciul verifică tabelul **STATUS_PROCESS** pentru procesele cu **alarma=1** şi **sound=0**. Când găsește un proces în stare de alarmă care nu este bifat, încearcă să-l repornească folosind strategia configurată.

### Ce este modelul circuit breaker?

Modelul **circuit breaker** previne încercările excesive de repornire pentru procesele care eșuează. După un număr configurabil de eșecuri, circuit breaker-ul "se deschide" și blochează încercările ulterioare de repornire pentru o perioadă de timp. Acest lucru previne epuizarea resurselor și eșecurile în cascadă.

### Cum pot adăuga health checkuri personalizate?

Puteți adăuga health check personalizat configurând parametrul health_check_command pentru un proces. Această comandă ar trebui să returneze codul de ieșire 0 dacă procesul este ON, sau non-zero dacă este OFF.

### Ce se întâmplă dacă baza de date MySQL este oprită?

Dacă baza de date MySQL este oprită, serviciul va înregistra o eroare și va continua să încerce să se conecteze la intervalul de verificare configurat. Nu va putea detecta sau reporni procese până când conexiunea la baza de date nu este restabilită.

### Cum pot schimba intervalul de verificare?

Editați fișierul config.ini și actualizați parametrul check_interval din secțiunea [monitor]. Valoarea este în secunde.

```ini
[monitor]
check_interval = 300  # 5 minutes
```
