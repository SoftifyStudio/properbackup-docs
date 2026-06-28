# ProperBackup — Dedykowany serwer OVH (KANONICZNY cel deploy + storage)

> Wersja: 1.0 (2026-06-20)
> Status: **NAJWAZNIEJSZY DOKUMENT INFRASTRUKTURY.** Ten dedykowany serwer jest
> **jedynym docelowym srodowiskiem** ProperBackup — i storage danych klientow, i
> deploy buffer/web/postgres, i miejsce pelnego E2E. Wszystkie inne serwery
> (np. `properbackup-test-server.softify.com.pl` na home.pl) sa tymczasowe /
> pomocnicze. **Decyzje o storage i deploy odnosza sie do TEGO serwera.**

## 1. Sprzet i zamowienie
- Dostawca: **OVH** — Kimsufi **KS-STOR**, zamowienie #252771126
- CPU: Intel **Xeon-D 1521** (4C/8T, 2.4/2.7 GHz)
- RAM: 16 GB DDR4 ECC
- Dyski: **4× 4 TB HDD SATA** (Soft RAID) + **1× 500 GB NVMe SSD**
- Lokalizacja: **Gravelines, Francja**
- Cena: 109 zl netto/mc
- Hostname: `ns3046183.ip-51-255-93.eu`
- **IP: 51.255.93.127**

## 2. Wirtualizacja i storage
- **Proxmox VE** zainstalowany na NVMe (500 GB).
- Web panel: **https://51.255.93.127:8006** (login root).
- **RAID5** na 4× 3.6 TB HDD → **~11 TB uzytecznego** jako `md0`, zamontowane na
  **`/mnt/storage`**. (Po instalacji robi sie initial resync w tle ~5-6h, dysk
  jest uzywalny w trakcie.)
- `/mnt/storage` = **kanoniczny katalog danych klientow** (paczki 900-950 MB,
  patrz session-orchestration-plan.md §0a). Restore = instant, zero unseal.

## 3. Kontener aplikacji (LXC 100 "properbackup")
- Debian 12, **6 rdzeni, 8 GB RAM**, rootfs 30 GB (`local:100/vm-100-disk-0.raw`).
- Bind mount: **`/mnt/storage` → `/mnt/storage`** (mp0).
- Siec: `eth0` **10.10.10.100/24**, gw 10.10.10.1, bridge `vmbr1` (NAT).
- Proxmox NAT port-forward host→LXC: **80, 443, 8080**.
- Zainstalowane w LXC: **Docker 29.6**, **JDK 21**, **Node 20**.

## 4. Aktualnie wdrozony stack (stan na 2026-06-20 ~22:34 UTC)
Docker Compose w **`/opt/properbackup`** (pliki: `docker-compose.yml`, `.env`,
`schema.sql`, `nginx.conf`, `buffer/`, `web-dist/`):

| Kontener | Obraz | Port (publiczny) |
|---|---|---|
| `properbackup-buffer-1` | eclipse-temurin:21-jre | http://51.255.93.127:8080 |
| `properbackup-postgres-1` | postgres:16-alpine | 5432 (tylko wewnatrz LXC) |
| `properbackup-web-1` | nginx:alpine | http://51.255.93.127:80 |

> UWAGA: ten stack zostal zlozony z **recznie przygotowanych artefaktow**, NIE z
> git-checkoutow najnowszych PR-ow. To stary build — pelny E2E na najnowszym
> kodzie dopiero przed nami.

## 5. Dostep
- SSH do hosta Proxmox: `ssh root@51.255.93.127` — haslo w secret
  **`OVH_DEDICATED_SERVER_PROXMOX_ROOT_PASSWORD`** (zapisany globalnie, dostepny
  we wszystkich sesjach Devin).
- Wejscie do kontenera: `pct exec 100 -- bash -lc '<cmd>'` lub `pct enter 100`.
- Dostep administracyjny (SSH, panel Proxmox `:8006`) jest **za VPN/firewallem**, nie z publicznego internetu.

### 5a. Bezpieczenstwo dostepu — zweryfikowane 2026-06-28
Skan z publicznego internetu (spoza VPN): porty **22 (SSH), 8006 (Proxmox), 80, 443,
8080, 5432 (Postgres) sa FILTERED** (brak odpowiedzi). Wniosek: serwer **nie wystawia
publicznie zadnej powierzchni administracyjnej ani aplikacyjnej** — dostep tylko przez
VPN/firewall. Dlatego sama obecnosc IP w docs to niskie ryzyko.
> Uwaga: gdy aplikacja pojdzie na produkcje dla klientow, web/buffer beda musialy byc
> publiczne (lub za reverse-proxy/CDN) — wtedy te porty przestana byc filtered i trzeba
> bedzie zadbac o TLS + hardening. Dzis (pre-launch) wszystko jest zamkniete.

## 6. Co zostalo do zrobienia (gdzie skonczyl setup)
- [x] Proxmox + RAID5 11 TB + LXC + Docker/JDK/Node
- [x] Pierwszy (stary) stack buffer+postgres+web wstal i dziala
- [ ] Wdrozenie **najnowszego kodu** (PR-y z sesji Ultra) na dedyk
- [ ] **Pelny zintegrowany E2E**: agent → buffer → seal → pack → zapis na
      `/mnt/storage` → restore → weryfikacja SHA-256 (z nagraniem)
- [ ] (Opcjonalnie) repo jako git-checkout zamiast recznych artefaktow, dla
      powtarzalnego deployu
