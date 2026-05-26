# Docker Deployment + E2E Test na serwerze produkcyjnym

**Data:** 2026-05-24
**Serwer:** properbackup-test-server.softify.com.pl (home.pl)

## Co zostalo zrobione

### Wdrozenie Docker
- Postawiono pelny stack Docker na serwerze home.pl:
  - **PostgreSQL 16** (alpine) — baza danych z automatycznym schema.sql
  - **Buffer** (Eclipse Temurin 21 JRE) — backend Javalin REST API na porcie 7100
  - **Nginx** (alpine) — reverse proxy na porcie 80, SPA fallback
- Skonfigurowano docker-compose.yml z health checks i woluminami
- Nginx reverse proxy: `/api/*` → buffer:7100, `/` → statyczne pliki frontendu
- Wszystkie klucze Stripe sandbox zaladowane przez .env (chmod 600)
- Backend automatycznie utworzyl produkty i ceny w Stripe (19 PLN/mies, 190 PLN/rok)

### Test E2E na zywym serwerze
- Rejestracja uzytkownika test-e2e@properbackup.pl
- Login i weryfikacja dashboardu
- Strona subskrypcji: plany widoczne z prawidlowymi cenami
- Badge "Test Mode" wyswietlany (stripe_test_mode=true w DB)
- Stripe Checkout: karta testowa 4242 4242 4242 4242 zaakceptowana
- Platnosc przetworzona automatycznie przez webhook
- Subskrypcja aktywowana w bazie: monthly, wygasa 2026-06-24

### Wynik
**Wszystkie 7 testow E2E: PASSED**

## Pliki
- `deployment/docker-deployment.md` — pelna dokumentacja wdrozenia Docker
- docker-compose.yml, nginx/default.conf, .env — konfiguracja na serwerze /opt/properbackup/

## Uwagi
- Webhook secrets (whsec_...) musza byc skonfigurowane w Stripe Dashboard dla pelnego flow
- Serwer uzywa sandbox Stripe — bezpieczne testowanie bez prawdziwych platnosci
- Aby zmienic klucze .env: `docker compose up -d --force-recreate buffer`
