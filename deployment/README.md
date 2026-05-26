# Wdrozenie

Dokumentacja wdrozeniowa i konfiguracyjna.

| Dokument | Opis |
|----------|------|
| [Docker Deployment](docker-deployment.md) | Wdrozenie w kontenerach Docker (docker-compose, nginx, PostgreSQL) + wyniki E2E |
| [Referencja zmiennych srodowiskowych](env-reference.md) | Kompletna lista env vars z opisami, przykladami i instrukcjami Stripe |
# Wdrozenie ProperBackup na VPS

Kompletny przewodnik po uruchomieniu ProperBackup na VPS z publicznym IP.

## Wymagania

| Komponent | Wersja | Uwagi |
|-----------|--------|-------|
| **VPS** | min. 2 GB RAM, 1 vCPU | Ubuntu 22.04+ / Debian 12+ |
| **Java** | 21+ | OpenJDK |
| **PostgreSQL** | 15+ | Baza danych |
| **Node.js** | 20+ | Build frontendu |
| **Nginx** | latest | Reverse proxy + SSL |
| **Domena** | opcjonalnie | Dla SSL (Let's Encrypt) |

Publiczne IP jest wymagane dla:
- Dostepu uzytkownikow do panelu web
- Webhook endpoint Stripe (Stripe musi moc wyslac POST na Twoj serwer)

## Architektura na serwerze

```
Internet
   │
   ▼
┌──────────────────────────────────────────────┐
│  Nginx (port 80/443)                         │
│  ├── /           → /var/www/properbackup/    │  ← pliki statyczne (frontend)
│  ├── /api/       → localhost:7100            │  ← reverse proxy do backendu
│  └── SSL (Let's Encrypt)                     │
└──────────────────────────────────────────────┘
   │
   ▼
┌──────────────────────────────────────────────┐
│  properbackup-buffer (port 7100)             │
│  ├── REST API (Javalin)                      │
│  ├── Stripe webhooks (/payment/stripe/webhook)│
│  └── Agent ingestion endpoints               │
└──────────────┬───────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────┐
│  PostgreSQL (port 5432)                      │
│  └── baza: properbackup                      │
└──────────────────────────────────────────────┘
```

## Krok 1: Przygotowanie VPS

```bash
# Aktualizacja systemu
sudo apt update && sudo apt upgrade -y

# Instalacja zaleznosci
sudo apt install -y openjdk-21-jdk-headless postgresql nginx certbot python3-certbot-nginx git curl unzip

# Weryfikacja Java
java -version
# openjdk version "21.x.x"
```

## Krok 2: PostgreSQL

```bash
# Tworzenie bazy i uzytkownika
sudo -u postgres psql <<'SQL'
CREATE USER properbackup WITH PASSWORD 'ZMIEN_NA_SILNE_HASLO';
CREATE DATABASE properbackup OWNER properbackup;
GRANT ALL PRIVILEGES ON DATABASE properbackup TO properbackup;
SQL

# Test polaczenia
psql -h localhost -U properbackup -d properbackup -c "SELECT 1;"
```

## Krok 3: Build backendu

```bash
# Klonowanie repozytorium
cd /opt
sudo git clone https://github.com/SoftifyStudio/properbackup-buffer.git
cd properbackup-buffer

# Build
./gradlew installDist

# Wynikowy katalog: build/install/properbackup-buffer/
# Binarka: build/install/properbackup-buffer/bin/properbackup-buffer
```

## Krok 4: Konfiguracja backendu (.env)

```bash
# Kopiuj i edytuj plik konfiguracyjny
sudo cp .env.example /opt/properbackup-buffer/.env
sudo nano /opt/properbackup-buffer/.env
```

Wymagane zmienne:

```bash
# === WYMAGANE ===
PROPERBACKUP_DB_PASSWORD=ZMIEN_NA_SILNE_HASLO
PROPERBACKUP_JWT_SECRET=WYGENERUJ_LOSOWY_STRING_32+_ZNAKOW
PROPERBACKUP_UPLOAD_TOKEN=WYGENERUJ_LOSOWY_TOKEN_DLA_AGENTOW
PROPERBACKUP_PANEL_URL=https://twoja-domena.pl

# === STRIPE (platnosci) ===
# Klucze ze strony https://dashboard.stripe.com/apikeys
STRIPE_TEST_SECRET_KEY=sk_test_...
STRIPE_TEST_PUBLIC_KEY=pk_test_...
STRIPE_TEST_WEBHOOK_SECRET=whsec_...

# Gdy gotowy na produkcje — dodaj klucze live:
# STRIPE_LIVE_SECRET_KEY=sk_live_...
# STRIPE_LIVE_PUBLIC_KEY=pk_live_...
# STRIPE_LIVE_WEBHOOK_SECRET=whsec_live_...

# === OVH STORAGE (opcjonalne — domyslnie local mock) ===
# PROPERBACKUP_OVH_MOCK=false
# OS_AUTH_URL=https://auth.cloud.ovh.net/v3
# OS_PROJECT_ID=...
# OS_USER_DOMAIN_NAME=Default
# OS_USERNAME=...
# OS_PASSWORD=...
# OS_REGION_NAME=GRA
# OS_CONTAINER=properbackup-archive
```

**Generowanie bezpiecznych tokenow:**

```bash
# JWT Secret (32+ znakow)
openssl rand -base64 32

# Upload token
openssl rand -hex 24
```

## Krok 5: Systemd service (backend)

```bash
sudo tee /etc/systemd/system/properbackup-buffer.service > /dev/null <<'EOF'
[Unit]
Description=ProperBackup Buffer
After=postgresql.service network.target
Requires=postgresql.service

[Service]
Type=simple
User=properbackup
Group=properbackup
WorkingDirectory=/opt/properbackup-buffer
EnvironmentFile=/opt/properbackup-buffer/.env
ExecStart=/opt/properbackup-buffer/build/install/properbackup-buffer/bin/properbackup-buffer \
  --port 7100 \
  --storage /var/lib/properbackup/storage \
  --inbox /var/lib/properbackup/inbox \
  --db-url jdbc:postgresql://localhost:5432/properbackup \
  --db-user properbackup \
  --db-pass ${PROPERBACKUP_DB_PASSWORD}
Restart=always
RestartSec=5

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=/var/lib/properbackup
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

# Tworzenie uzytkownika systemowego i katalogow
sudo useradd -r -s /bin/false properbackup 2>/dev/null || true
sudo mkdir -p /var/lib/properbackup/storage /var/lib/properbackup/inbox
sudo chown -R properbackup:properbackup /var/lib/properbackup
sudo chown -R properbackup:properbackup /opt/properbackup-buffer

# Start
sudo systemctl daemon-reload
sudo systemctl enable properbackup-buffer
sudo systemctl start properbackup-buffer

# Sprawdzenie
sudo systemctl status properbackup-buffer
curl -s http://localhost:7100/health || echo "Backend nie odpowiada"
```

## Krok 6: Build frontendu

```bash
cd /opt
sudo git clone https://github.com/SoftifyStudio/properbackup-web.git
cd properbackup-web

# Instalacja zaleznosci
npm install

# Build produkcyjny
# VITE_BUFFER_URL nie trzeba ustawiac — domyslnie uzywa /api (reverse proxy)
npm run build

# Kopiowanie zbudowanych plikow
sudo mkdir -p /var/www/properbackup
sudo cp -r dist/* /var/www/properbackup/
sudo chown -R www-data:www-data /var/www/properbackup
```

## Krok 7: Nginx + SSL

### Bez domeny (tylko IP)

```bash
sudo tee /etc/nginx/sites-available/properbackup > /dev/null <<'EOF'
server {
    listen 80;
    server_name _;

    # Frontend — pliki statyczne
    root /var/www/properbackup;
    index index.html;

    # SPA fallback — wszystkie sciezki do index.html
    location / {
        try_files $uri $uri/ /index.html;
    }

    # Backend API — reverse proxy
    location /api/ {
        proxy_pass http://127.0.0.1:7100/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Wiekszy limit dla uploadow backupow
        client_max_body_size 1024m;

        # SSE (Server-Sent Events) — nie buforuj
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 3600s;
    }

    # Stripe webhook — dedykowany location (bez rate-limiting)
    location /api/payment/stripe/webhook {
        proxy_pass http://127.0.0.1:7100/payment/stripe/webhook;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Stripe-Signature $http_stripe_signature;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/properbackup /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

### Z domena + SSL (Let's Encrypt)

```bash
# 1. Ustaw domena DNS A record → publiczne IP VPS

# 2. Zmien server_name w konfiguracji nginx:
sudo sed -i 's/server_name _;/server_name twoja-domena.pl;/' /etc/nginx/sites-available/properbackup
sudo nginx -t && sudo systemctl reload nginx

# 3. Certbot — automatyczny SSL
sudo certbot --nginx -d twoja-domena.pl --agree-tos --email admin@twoja-domena.pl

# 4. Auto-renewal (certbot domyslnie dodaje cron/timer)
sudo systemctl status certbot.timer
```

## Krok 8: Stripe Webhook

Po uruchomieniu serwera musisz skonfigurowac Stripe aby wyslal webhooki na Twoj endpoint:

1. Idz do https://dashboard.stripe.com/webhooks
2. Kliknij **"Add endpoint"**
3. URL: `https://twoja-domena.pl/api/payment/stripe/webhook` (lub `http://TWOJE_IP/api/payment/stripe/webhook`)
4. Wybierz eventy:
   - `checkout.session.completed`
   - `invoice.paid`
   - `customer.subscription.updated`
   - `customer.subscription.deleted`
5. Skopiuj **Signing secret** (zaczyna sie od `whsec_`)
6. Wklej do `.env` jako `STRIPE_TEST_WEBHOOK_SECRET`
7. Restartuj backend: `sudo systemctl restart properbackup-buffer`

**Dla trybu live** (gdy gotowy na produkcje):
- Stworz osobny webhook endpoint w live mode
- Skopiuj live signing secret do `STRIPE_LIVE_WEBHOOK_SECRET`
- Przelacz uzytkownikow: `UPDATE users SET stripe_test_mode = FALSE WHERE ...`

## Krok 9: Weryfikacja

```bash
# 1. Backend dziala?
curl -s http://localhost:7100/health
# Powinno zwrocic odpowiedz

# 2. Frontend dziala?
curl -s http://localhost/
# Powinno zwrocic HTML

# 3. API przez nginx?
curl -s http://localhost/api/health
# Powinno zwrocic to samo co bezposrednio z backendu

# 4. Z zewnatrz (z innej maszyny)
curl -s http://TWOJE_IP/
curl -s http://TWOJE_IP/api/health

# 5. Stripe webhook test
# W Stripe Dashboard → Webhooks → "Send test webhook"
# Sprawdz logi: sudo journalctl -u properbackup-buffer -f
```

## Krok 10: Aktualizacja (deploy nowej wersji)

```bash
# Backend
cd /opt/properbackup-buffer
sudo -u properbackup git pull origin main
sudo -u properbackup ./gradlew installDist
sudo systemctl restart properbackup-buffer

# Frontend
cd /opt/properbackup-web
git pull origin main
npm install
npm run build
sudo cp -r dist/* /var/www/properbackup/
# Nginx automatycznie serwuje nowe pliki (nie wymaga restartu)
```

## Rozwiazywanie problemow

### Backend nie startuje
```bash
sudo journalctl -u properbackup-buffer -n 50 --no-pager
```

### PostgreSQL — nie mozna sie polaczyc
```bash
# Sprawdz czy dziala
sudo systemctl status postgresql

# Sprawdz pg_hba.conf (metoda autentykacji)
sudo nano /etc/postgresql/*/main/pg_hba.conf
# Upewnij sie ze jest linia:
# local   all   properbackup   md5
# host    all   properbackup   127.0.0.1/32   md5
sudo systemctl reload postgresql
```

### Stripe webhook nie przychodzi
1. Sprawdz czy endpoint jest dostepny z internetu: `curl http://TWOJE_IP/api/payment/stripe/webhook`
2. Sprawdz Stripe Dashboard → Webhooks → "Attempts" (logi doreczen)
3. Sprawdz logi backendu: `sudo journalctl -u properbackup-buffer -f`
4. Upewnij sie ze `STRIPE_TEST_WEBHOOK_SECRET` jest poprawny w `.env`

### Frontend wyswietla bledy API
1. Sprawdz czy proxy nginx dziala: `curl http://localhost/api/health`
2. Sprawdz logi nginx: `sudo tail -f /var/log/nginx/error.log`
3. Sprawdz czy CORS nie blokuje — z nginx reverse proxy CORS nie powinien byc problemem

## Bezpieczenstwo — checklist

- [ ] `.env` ma permissions `600` (tylko owner moze czytac)
- [ ] PostgreSQL nie nasuchuje na publicznym IP (domyslnie localhost)
- [ ] Firewall: tylko porty 80, 443, 22 otwarte (`sudo ufw allow 80,443,22/tcp && sudo ufw enable`)
- [ ] SSH: klucze zamiast hasla (`PasswordAuthentication no` w sshd_config)
- [ ] Stripe webhook secret skonfigurowany (bez niego backend odrzuca wszystkie webhooki — fail-closed)
- [ ] JWT secret silny i unikalny (min. 32 znaki, losowe)
- [ ] Upload token silny i unikalny
- [ ] SSL wlaczony (Let's Encrypt lub wlasny certyfikat)
