# ProperBackup — Dokumentacja

Centralne repozytorium dokumentacji projektu ProperBackup.

## Struktura

```
/changelog      — lista zmian z datami (co zostalo zmienione/dodane)
/architecture   — schematy decyzji architektonicznych, opisy komponentow
/deployment     — przewodnik wdrozeniowy (VPS, nginx, SSL, Stripe)
/scripts        — skrypty migracyjne, narzedzia operacyjne
```

## Repozytoria projektu

| Repo | Opis |
|------|------|
| `properbackup-buffer` | Backend (Kotlin, Spring Boot, PostgreSQL) |
| `properbackup-agent` | Agent backupowy (Kotlin) |
| `properbackup-shared` | Wspolne biblioteki (Kotlin Multiplatform) |
| `properbackup-web` | Panel webowy (React frontend) |
| `properbackup-stack` | Docker stack |
| `properbackup-mc` | Plugin Minecraft |
| `properbackup-docs` | Dokumentacja (to repozytorium) |

## Produkt

Micro-SaaS do backupow zoptymalizowany pod srodowiska niskobudzetowe (VPS/Dedicated/ARM64).

- **Cena:** 19 PLN/mies, 190 PLN/rok (brutto, z VAT 23%)
- **Storage:** OVH Cloud Archive
- **Marza brutto:** >70%
