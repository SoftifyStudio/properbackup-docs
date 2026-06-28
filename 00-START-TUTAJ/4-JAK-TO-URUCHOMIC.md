# 4. Gdzie co stoi i jak to uruchomić

> Skrót operacyjny. Pełny, autorytatywny opis infrastruktury:
> [`../architecture/deployment-dedicated-server.md`](../architecture/deployment-dedicated-server.md).

## Serwer docelowy (KANONICZNY — storage + deploy)
- **OVH Kimsufi KS-STOR**, Gravelines (FR). Koszt 109 zł netto/mc (~135 brutto).
- Sprzęt: Xeon-D 1521, 16 GB ECC, **4×4 TB HDD RAID5 ≈ ~11 TB** + 500 GB NVMe.
- **Proxmox VE** na NVMe (panel na porcie 8006, login root).
- **RAID5 → `/mnt/storage`** = kanoniczny katalog danych klientów (paczki 900–950 MB).
- Aplikacja w **LXC 100 „properbackup"** (Debian 12, Docker 29.6, JDK 21, Node 20), bind mount `/mnt/storage`.

> 🔐 **Adres IP, dane SSH i nazwa sekretu z hasłem root** są w
> [`../architecture/deployment-dedicated-server.md`](../architecture/deployment-dedicated-server.md) §1/§5
> — nie powielamy ich tutaj (mniej miejsc = mniej powierzchni do wycieku).

## Dostęp
- **Dostęp administracyjny (SSH + panel Proxmox) jest za VPN/firewallem** — z publicznego internetu wszystkie porty są filtered (zweryfikowane 2026-06-28). Szczegóły i dowód: `deployment-dedicated-server.md` §5/§5a.
- SSH do hosta Proxmox + nazwa sekretu z hasłem root: patrz `deployment-dedicated-server.md` §5 (sekret dostępny globalnie w sesjach Devina).
- Wejście do kontenera: `pct enter 100` (lub `pct exec 100 -- bash -lc '<cmd>'`).
- Endpointy aplikacji: buffer `:8080`, web `:80`.

## Stack aplikacji
Docker Compose w **`/opt/properbackup`** (`docker-compose.yml`, `.env`, `schema.sql`, `nginx.conf`, `buffer/`, `web-dist/`):
- `properbackup-buffer-1` (temurin:21-jre) → `:8080`
- `properbackup-postgres-1` (postgres:16-alpine) → `5432` (tylko w LXC)
- `properbackup-web-1` (nginx:alpine) → `:80`

> ⚠ **Uwaga:** obecnie wdrożony stack to **stary build z ręcznych artefaktów**, NIE
> git-checkout najnowszych PR-ów. Wdrożenie najnowszego kodu + pełny E2E to wciąż
> zadanie do zrobienia (patrz [`3-CO-JEST-ZROBIONE.md`](3-CO-JEST-ZROBIONE.md)).

## Serwery pomocnicze
- `properbackup-test-server.softify.com.pl` (home.pl VPS) — tymczasowy/testowy (buffer m.in. na porcie 7100). Nie jest celem produkcyjnym.

## Strona / landing
- Repo `softify-website` (React + Vite + Tailwind, deploy Vercel). Landing produktu: trasa `/properbackup`.
- Lokalnie: `npm install && npm run dev` (→ http://localhost:5173). Build: `npm run build`.
- Formularz zgłoszeń: FormSubmit → `kontakt@softify.com.pl` (bez backendu).

## Repo z kodem (lokalny dev)
Każde repo (`properbackup-buffer`, `-agent`, `-shared`, `-web`, `-mc`, `-stack`) ma własne README/instrukcje.
Brak CI — testy odpalane lokalnie. Merge do `main` robi Daniel ręcznie.
