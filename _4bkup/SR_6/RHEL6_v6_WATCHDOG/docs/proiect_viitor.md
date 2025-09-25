### Proiect: Process Monitor – plan viitor (UI pe Windows, colectare Linux)

Acest document rezumă deciziile și schema tehnică pentru un sistem de monitorizare și management al proceselor cu UI web pe Windows și agenți pe servere Linux.

---

### Tehnologii principale

- **Backend**: FastAPI (Python), WebSocket/SSE pentru realtime, Redis pentru cozi/semnalizare, PostgreSQL pentru date.
- **Frontend (UI web)**: React + Vite; biblioteci UI (MUI/Ant Design/Tailwind), Recharts/Chart.js pentru grafice.
- **Agenți Linux**: Python + `psutil`, rulați ca serviciu `systemd` pe fiecare server; comunică prin HTTPS cu API-ul central.
- **Observabilitate**: JSON logging, Prometheus/OpenTelemetry (opțional ulterior), Grafana (opțional).
- **Deployment**: Docker Compose pe stația Windows (API, DB, Redis, UI). TLS recomandat pentru expunere externă.

---

### Arhitectură la nivel înalt

- UI rulează în browser pe stația Windows și consumă API-ul FastAPI.
- Fiecare server Linux are un agent care colectează periodic metrici (CPU, memorie, procese, uptime) și le trimite către API.
- API persistă sumarul, împinge actualizări în timp real către UI și pune comenzi (start/stop/restart) în cozi Redis pe agent.
- Fluxuri:
  - Agent → API: `POST /agents/{id}/metrics` (10s), înregistrare agent.
  - UI → API → Agent: comenzi de control rutate asincron (queue Redis), cu audit.
  - API → UI: WebSocket la `/ws` pentru update live/alerte.

---

### Structură directoare propusă (monorepo)

```
process-monitor/
  backend/
    app/
      main.py
      deps.py
      models.py
      schemas.py
      repositories.py
      websocket.py
      auth.py
      actions.py
    requirements.txt
    .env.example
    alembic/ (opțional pentru migrații)
  frontend/
    index.html
    src/
      main.tsx
      api.ts
      hooks/useWS.ts
      pages/{Dashboard.tsx, Processes.tsx}
  agent-linux/
    agent.py
    agent.service
    requirements.txt
  docker-compose.yml
```

---

### API FastAPI – puncte de extensie cheie

- `POST /agents/register` – înregistrare agent (token per agent, mTLS opțional)
- `POST /agents/{id}/metrics` – ingestie metrici periodice
- `GET /servers` – listă sumarizată a serverelor
- `GET /servers/{id}` – detalii server (istoric scurt/ultimele valori)
- `WS /ws` – actualizări realtime pentru UI
- `POST /actions/{agent}` – enqueue acțiune `{cmd: start|stop|restart, target: service}`
- `GET /actions/queue/{agent}` – (opțional) long‑poll pentru agent dacă nu folosim Redis direct

Exemplu payload metrici agent:

```json
{
  "agentId": "srv-redis-01",
  "ts": 1726147200,
  "procs": [
    {"name": "redis-server", "pid": 123, "cpu": 1.2, "memMB": 78, "status": "running"}
  ],
  "load": {"cpu": 8.9, "memUsedMB": 2048, "memTotalMB": 8192},
  "uptimeSec": 123456,
  "alerts": []
}
```

---

### Schelet backend (rezumat)

- Pool `asyncpg` pentru PostgreSQL
- Conexiune Redis pentru cache/cozi: `queue:{agentId}` pentru acțiuni, `agent:{id}:last` pentru ultimul snapshot
- Difuzare realtime către clienții UI printr-un set de conexiuni WebSocket
- CORS configurat pentru `http://localhost:5173`

Dependințe backend:

```txt
fastapi==0.115.2
uvicorn[standard]==0.30.6
asyncpg==0.29.0
redis[hiredis]==5.0.7
pydantic==2.9.2
python-dotenv==1.0.1
```

---

### Frontend (React + Vite) – elemente cheie

- `api.ts` – acces API (`/servers`, acțiuni)
- `useWS.ts` – hook WebSocket pentru recepția live a mesajelor de tip `metrics`/`action_enqueued`
- Pagini inițiale: `Dashboard` (statistici, grafice), `Processes` (listă procese per server, acțiuni start/stop/restart)

---

### Agent Linux (Python + psutil)

- Colectează procese (limitare hard, ex. 500 procese), CPU%, memorie, uptime
- Trimite la 10s către API cu header `X-Agent-Token`
- Rulează ca serviciu `systemd` (`/etc/systemd/system/agent.service`), restart automat

Dependințe agent:

```txt
psutil==5.9.8
requests==2.32.3
```

Model `systemd`:

```ini
[Unit]
Description=Process Monitor Agent
After=network-online.target

[Service]
User=root
Environment=API=http://WINDOWS_HOST_IP:8000
Environment=AGENT_ID=srv-01
Environment=AGENT_TOKEN=replace-me
ExecStart=/usr/bin/python3 /opt/pm-agent/agent.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

---

### Docker Compose (rulat pe stația Windows)

Servicii: `api` (FastAPI), `db` (PostgreSQL), `redis`, `ui` (Vite dev server).

Porturi implicite: API `8000`, UI `5173`, Redis `6379`.

---

### Securitate (MVP și extinderi)

- TLS pentru API (reverse proxy Nginx/Caddy sau terminare TLS în container)
- Token per agent; posibil IP allowlist
- Rate limiting și audit pentru acțiuni de control
- mTLS agent↔API (opțional când expunem în WAN)

---

### Pași de rulare (MVP)

1) Pe Windows, în directorul proiectului: pornește `docker compose up -d`. UI: `http://localhost:5173`.
2) Pe fiecare server Linux:
   - `sudo mkdir -p /opt/pm-agent && sudo cp agent.py /opt/pm-agent/`
   - `sudo pip3 install -r requirements.txt`
   - editează `agent.service` (setează IP/TOKEN)
   - `sudo cp agent.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable --now agent`

---

### Backlog imediat

- Persistență istoric metrici (TimescaleDB sau agregare la minut în PostgreSQL)
- Engine de alerte (reguli în DB; notificări email/Slack/Webhook)
- RBAC, autentificare utilizatori și audit UI
- Endpoint de long‑poll sau consum direct Redis pentru agent (ack, status comenzi)
- Export OpenAPI/Swagger + colecție tests (PyTest) și CI/CD


