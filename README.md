# ProperBackup — Dokumentacja

Centralne repozytorium dokumentacji projektu ProperBackup.

> 👉 **Nowy tu? Albo gubisz się w dokumentach? Zacznij od [`00-START-TUTAJ/`](00-START-TUTAJ/).**
> To wytłumaczenie projektu „po ludzku" + **kanon aktualnych decyzji**
> ([`00-START-TUTAJ/2-DECYZJE-AKTUALNE.md`](00-START-TUTAJ/2-DECYZJE-AKTUALNE.md)) —
> jedyne źródło prawdy o cenach, storage, quocie i DR. Reszta plików tylko do niego linkuje.

## Struktura

```
/00-START-TUTAJ  — ⭐ start: co to jest, aktualne decyzje, stan prac, jak uruchomić, dla AI
/biznesplan      — biznesplan w markdownie (aktualna wersja: v6.3)
/architecture    — szczegóły techniczne (master-specy TDD, decyzje, komponenty)
/changelog       — lista zmian z datami
/deployment      — przewodnik wdrożeniowy (dedyk OVH, nginx, SSL, Stripe)
/scripts         — skrypty migracyjne, narzędzia operacyjne
/legal           — RODO, DPA, polityki
```

## Repozytoria projektu

| Repo | Opis |
|------|------|
| `properbackup-buffer` | Backend (Kotlin, Spring Boot, PostgreSQL) |
| `properbackup-agent` | Agent backupowy (Kotlin) |
| `properbackup-shared` | Wspólne biblioteki (Kotlin Multiplatform) |
| `properbackup-web` | Panel webowy (React frontend) |
| `properbackup-stack` | Docker stack |
| `properbackup-mc` | Plugin Minecraft |
| `properbackup-docs` | Dokumentacja (to repozytorium) |
| `softify-website` | Strona firmowa + **landing ProperBackup** (`/properbackup`, marketing + formularz zgłoszeń) |

## Produkt (skrót — szczegóły w `00-START-TUTAJ/`)

Micro-SaaS do backupów, zero-knowledge, zoptymalizowany pod środowiska
niskobudżetowe (VPS / Dedicated / ARM64) i serwery Minecraft.

- **Cennik:** S 29 zł/mc (259 zł/rok) · M 39 (349) · L 59 (529) · XL 89 (790) — unlimited devices, ~25% taniej rocznie. Pełny model: [`00-START-TUTAJ/2-DECYZJE-AKTUALNE.md`](00-START-TUTAJ/2-DECYZJE-AKTUALNE.md).
- **Storage (primary):** dedykowany serwer OVH (Kimsufi KS-STOR, RAID5 ~10–11 TB, `/mnt/storage`), **restore instant** (bez odmrażania).
- **DR / offsite:** kopia #2 na OVH cold/backup (write-once, EU, RODO).
- **Koszt nasz:** stały ~135 zł brutto/mc za cały serwer (nie per-GB). Próg rentowności ~5 klientów S. Marża operacyjna ~75–90%.
