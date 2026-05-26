# Wdrozenie Docker — properbackup-test-server

Dokumentacja wdrozenia ProperBackup w kontenerach Docker na serwerze home.pl (`properbackup-test-server.softify.com.pl`).

## Architektura kontenerow

```
                   Internet (port 80)
                        |
                   +---------+
                   |  Nginx  |  (nginx:alpine)
                   |  :80    |
                   +----+----+
                        |
           /            |            \
     /api/* proxy   static files    SPA fallback
          |         (web build)     → /index.html
          v
   +-------------+
   |   Buffer    |  (eclipse-temurin:21-jre-alpine)
   |   :7100     |  Javalin REST API
   +------+------+
          |
   +------+------+
   | PostgreSQL  |  (postgres:16-alpine)
   |   :5432     |
   +-------------+
```

## Struktura plikow na serwerze

```
/opt/properbackup/
├── docker-compose.yml
├── .env                    # chmod 600 — klucze, sekrety
├── buffer/
│   ├── properbackup-buffer.jar
│   └── schema.sql          # DDL bazy danych
├── web/                    # statyczne pliki frontendu (npm run build)
│   ├── index.html
│   ├── assets/
│   └── ...
└── nginx/
    └── default.conf        # konfiguracja reverse proxy
```

## docker-compose.yml

```yaml
version: "3.8"

services:
  db:
    image: postgres:16-alpine
    container_name: properbackup-db
    restart: unless-stopped
    environment:
      POSTGRES_DB: properbackup
      POSTGRES_USER: properbackup
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./buffer/schema.sql:/docker-entrypoint-initdb.d/schema.sql:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U properbackup"]
      interval: 10s
      timeout: 5s
      retries: 5

  buffer:
    image: eclipse-temurin:21-jre-alpine
    container_name: properbackup-buffer
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    ports:
      - "127.0.0.1:7100:7100"
    working_dir: /app
    command: ["java", "-jar", "properbackup-buffer.jar"]
    environment:
      DB_URL: jdbc:postgresql://db:5432/properbackup
      DB_USER: properbackup
      DB_PASSWORD: ${DB_PASSWORD}
      JWT_SECRET: ${JWT_SECRET}
      UPLOAD_TOKEN: ${UPLOAD_TOKEN}
      STRIPE_TEST_SECRET_KEY: ${STRIPE_TEST_SK}
      STRIPE_TEST_PUBLIC_KEY: ${STRIPE_TEST_PK}
      STRIPE_LIVE_SECRET_KEY: ${STRIPE_LIVE_SK}
      STRIPE_LIVE_PUBLIC_KEY: ${STRIPE_LIVE_PK}
      STRIPE_TEST_WEBHOOK_SECRET: ${STRIPE_TEST_WEBHOOK_SECRET}
      STRIPE_LIVE_WEBHOOK_SECRET: ${STRIPE_LIVE_WEBHOOK_SECRET}
      SERVER_URL: http://properbackup-test-server.softify.com.pl
    volumes:
      - ./buffer/properbackup-buffer.jar:/app/properbackup-buffer.jar:ro
      - buffer-storage:/app/storage
      - buffer-inbox:/app/inbox

  nginx:
    image: nginx:alpine
    container_name: properbackup-nginx
    restart: unless-stopped
    depends_on:
      - buffer
    ports:
      - "80:80"
    volumes:
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
      - ./web:/usr/share/nginx/html:ro

volumes:
  pgdata:
  buffer-storage:
  buffer-inbox:
```

## nginx/default.conf

```nginx
server {
    listen 80;
    server_name properbackup-test-server.softify.com.pl;

    root /usr/share/nginx/html;
    index index.html;

    # SPA fallback — kazdy path ktory nie istnieje wraca do index.html
    location / {
        try_files $uri $uri/ /index.html;
    }

    # Reverse proxy do backendu
    location /api/ {
        proxy_pass http://buffer:7100/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        client_max_body_size 1024m;
    }
}
```

## Zmienne srodowiskowe (.env)

```bash
# Baza danych
DB_PASSWORD=<losowy 24-byte base64>

# JWT + upload token
JWT_SECRET=<losowy 32-byte base64>
UPLOAD_TOKEN=<losowy 48 hex>

# Stripe — konto TEST (sandbox)
STRIPE_TEST_SK=sk_test_...
STRIPE_TEST_PK=pk_test_...
STRIPE_TEST_WEBHOOK_SECRET=whsec_...

# Stripe — konto LIVE (lub drugi sandbox)
STRIPE_LIVE_SK=sk_live_...    # lub sk_test_... z drugiego konta sandbox
STRIPE_LIVE_PK=pk_live_...    # lub pk_test_... z drugiego konta sandbox
STRIPE_LIVE_WEBHOOK_SECRET=whsec_...
```

Generowanie bezpiecznych wartosci:
```bash
# DB_PASSWORD
openssl rand -base64 24

# JWT_SECRET
openssl rand -base64 32

# UPLOAD_TOKEN
openssl rand -hex 24
```

**Wazne:** Plik `.env` musi miec uprawnienia `chmod 600`.

## Procedura uruchomienia

```bash
# 1. Sklonuj repozytoria i zbuduj
cd /opt/properbackup

# 2. Zbuduj backend JAR (na maszynie developerskiej)
cd properbackup-buffer
./gradlew shadowJar
scp build/libs/properbackup-buffer-*-all.jar root@server:/opt/properbackup/buffer/properbackup-buffer.jar

# 3. Zbuduj frontend (na maszynie developerskiej)
cd properbackup-web
npm ci && npm run build
scp -r dist/* root@server:/opt/properbackup/web/

# 4. Na serwerze — uruchom stack
ssh root@server
cd /opt/properbackup
docker compose up -d

# 5. Weryfikacja
docker compose ps                          # wszystkie kontenery UP
docker logs properbackup-buffer 2>&1 | tail -20  # brak bledow
curl -s http://localhost/api/ | head -1    # odpowiedz 200
curl -s http://localhost/ | head -1        # frontend HTML
```

## Komendy operacyjne

```bash
# Restart po zmianach .env
docker compose up -d --force-recreate buffer

# Logi backendu (live)
docker logs -f properbackup-buffer

# Sprawdzenie webhookow
docker logs properbackup-buffer 2>&1 | grep -i webhook

# Sprawdzenie bazy
docker exec properbackup-db psql -U properbackup -d properbackup -c "SELECT email, subscription_plan, subscription_expires_at FROM users;"

# Pelen restart stacku
docker compose down && docker compose up -d

# Aktualizacja JARa
docker compose stop buffer
# scp nowy jar...
docker compose up -d buffer
```

## Weryfikacja po wdrozeniu

| Test | Komenda | Oczekiwany wynik |
|------|---------|-----------------|
| Frontend | `curl -s -o /dev/null -w '%{http_code}' http://server/` | `200` |
| API | `curl -s -o /dev/null -w '%{http_code}' http://server/api/` | `200` |
| DB | `docker exec properbackup-db pg_isready -U properbackup` | `accepting connections` |
| Logi | `docker logs properbackup-buffer 2>&1 \| grep ERROR` | Brak bledow |

## Wyniki testu E2E (2026-05-24)

Pelny test E2E przeprowadzony na zywym serwerze:

1. Rejestracja uzytkownika `test-e2e@properbackup.pl`
2. Login → dashboard zaladowany
3. Strona subskrypcji: plany 19 PLN/mies i 190 PLN/rok widoczne
4. Badge **Test Mode** widoczny (stripe_test_mode=true)
5. Stripe Checkout otworzony, karta testowa 4242 zaakceptowana
6. Platnosc przetworzona — subskrypcja aktywowana automatycznie
7. Baza danych: `subscription_plan=monthly`, `expires=2026-06-24`, `ever_subscribed=true`

**Wynik: Wszystkie 7 testow PASSED.**
