# 1. Co to jest ProperBackup (po ludzku)

## W jednym zdaniu
**ProperBackup to płatny backup w chmurze, który naprawdę da się odtworzyć** —
szyfrowany po stronie klienta (my nie widzimy danych), z automatycznym testem
odtwarzania i raportem PDF, pomyślany pod serwery Minecraft, tani VPS, ARM-y i małe firmy.

## Problem, który rozwiązujemy
Większość ludzi „ma backup", dopóki nie spróbuje go odtworzyć — i wtedy okazuje się,
że plik jest uszkodzony, niepełny albo zaszyfrowany ransomwarem. My sprzedajemy
**pewność, że kopia działa**, a nie samo „miejsce na dane".

## Dla kogo
1. **Serwery Minecraft** (hosting gier, właściciele serwerów) — plugin, backup map/światów bez psucia plików.
2. **Self-hosterzy / tani VPS / ARM64** — agent lekki dla słabego sprzętu (dławienie CPU/I-O).
3. **Małe agencje WordPress / freelancerzy IT** — tu jest realny pieniądz: **Audit PDF** = dowód dla ich klienta, że backup był i działa.

## Co nas wyróżnia (USP)
- **Zweryfikowany restore + Audit PDF** — automatyczny test odtworzenia, raport z hashami. *To jest nasz główny haczyk marketingowy.*
- **Zero-knowledge** — Argon2id → AES-256-GCM po stronie klienta. Hasło nie opuszcza urządzenia.
- **Instant restore** — dane na własnym serwerze z RAID, odtwarzanie od ręki (bez „odmrażania").
- **Time-travel** — pełna historia wersji, cofnięcie do dowolnego dnia (nie tylko ostatnia kopia).
- **Świadomy Minecrafta** — plugin Spigot/Paper, backup światów bez korupcji.
- **EU / RODO** — dane w Europie.
- **Unlimited devices** — płacisz za miejsce, nie za liczbę urządzeń.

## Jak to działa (3 kroki)
1. **Agent** (jeden JAR) na serwerze klienta skanuje pliki, deduplikuje, kompresuje, szyfruje i wysyła paczki.
2. **Buffer** (nasz backend) przyjmuje paczki, układa na dedykowanym serwerze (`/mnt/storage`), pilnuje limitów i budżetu.
3. **Panel web** — timeline, 1-Click Restore, pobranie Audit PDF, monitoring agentów, płatności (Stripe).

## Model biznesowy w skrócie
- Trial 30 dni → płatne tiery **S / M / L / XL** (29–89 zł/mc).
- Cały produkt budowany i utrzymywany przez AI (Devin) — niski koszt stały.
- Sukces zależy w ~80% od **dystrybucji** (dotarcie do agencji WP/IT), nie od samego produktu.

➡ Konkretne liczby (ceny, limity, koszty, infrastruktura): [`2-DECYZJE-AKTUALNE.md`](2-DECYZJE-AKTUALNE.md).
➡ Pełny biznesplan: [`../biznesplan/Biznesplan_v6.3.md`](../biznesplan/Biznesplan_v6.3.md).
