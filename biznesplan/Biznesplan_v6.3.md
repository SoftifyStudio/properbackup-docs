# Biznesplan ProperBackup — v6.3

> **Wersja:** 6.3 (2026-06-28). **Zastępuje** `Biznesplan_ProperBackup_v6.2_NAJLEPSZY.docx` (maj 2026).
> Co się zmieniło względem v6.2: **storage** (chmura per-GB → dedykowany serwer OVH),
> **cennik** (Hobby/Pro → S/M/L/XL), **model kosztu** (zmienny per-GB → stały serwer),
> **DR** (OVH cold odrzucone → docelowo drugi serwer dedykowany/PBS). Liczby twarde (ceny/limity/koszt/DR) są w
> **kanonie**: [`../00-START-TUTAJ/2-DECYZJE-AKTUALNE.md`](../00-START-TUTAJ/2-DECYZJE-AKTUALNE.md).
> Ten dokument tłumaczy „dlaczego", kanon mówi „ile".

---

## 1. Streszczenie
ProperBackup to micro-SaaS do backupu **zero-knowledge**, sprzedający nie „miejsce na
dane", lecz **pewność, że kopię da się odtworzyć** (auto-test restore + Audit PDF).
Nisze: serwery Minecraft, tani VPS / self-host / ARM64 oraz małe agencje WordPress / IT.
Cały produkt buduje i utrzymuje AI (Devin) — niski, przewidywalny koszt stały.

Model „try-first": 30-dniowy pełny trial → konwersja na pakiet **S/M/L/XL** (29–89 zł/mc).

## 2. Problem i rozwiązanie
Większość „ma backup" — do pierwszej próby odtworzenia. Wtedy okazuje się, że jest
uszkodzony, niepełny albo zaszyfrowany przez ransomware. My **automatycznie testujemy
odtworzenie** każdej kopii i dajemy **dowód (Audit PDF)**. To jest produkt: spokój + dowód spokoju.

## 3. USP (dlaczego my, nie tani addon / iDrive)
- **Zweryfikowany restore + Audit PDF** — addon zrobi kopię, ale nie sprawdzi, czy działa, i nie da dowodu.
- **Zero-knowledge** (Argon2id → AES-256-GCM po stronie klienta) — addon często śle plaintext.
- **Instant restore** z własnego serwera RAID (bez odmrażania).
- **Time-travel** — pełna historia wersji.
- **Świadomy Minecrafta** (plugin Spigot/Paper, backup światów bez korupcji).
- **EU / RODO**, **unlimited devices** (płacisz za miejsce, nie za urządzenia).

## 4. Segmenty i pozycjonowanie
- **Segment przychodowy (główny): agencje WordPress + freelancerzy IT z compliance** (~30% planu, nie „jedna linijka"). Audit PDF = wartość biznesowa wobec ICH klienta.
- **Segment wejściowy (content/viralowość): admini MC + self-hosterzy.** Świetni do zasięgu i wiarygodności, słabo konwertują (mają darmowe alternatywy).

Nie konkurujemy ceną-za-TB. Wygrywamy zdolnością (MC, zweryfikowany restore, IoThrottle, time-travel, EU).

## 5. Lejek „trigger-based" (kluczowa teza dystrybucji)
Backup kupuje się „jak zaboli". Nasz realny lejek to nie „ktoś szuka backupu", tylko:
- **disaster** („właśnie straciłem dane"), **fear** („czytam, że ktoś stracił"),
- **compliance** („klient pyta agencję o backup"), **news** („ransomware w mojej niszy").

Content celuje w triggery: „Usunąłem świat MC — odzyskałem w 2 min", „Twój backup nie
działa, a nie wiesz", „Jak pokazać klientowi, że dane są bezpieczne".

## 6. Plan sprzedaży B2B (agencje WP) — bo to tu są pieniądze
Agencje nie czytają r/selfhosted. Kupują przez rekomendacje, networking, cold outreach, LinkedIn.
1. **Lista 50–100 polskich agencji WP** (clutch.co, Google, LinkedIn, grupy FB).
2. **Cold email** z demo Audit PDF (cel ~20% open, ~5% reply).
3. **LinkedIn outreach** + case study.
4. **Networking** (WordCamp, meetupy WP) — demo na żywo restore + Audit.
5. **Referral**: agencja poleca agencję → 30 dni gratis dla obu.
6. **Trial 45 dni dla agencji** + 15-min onboarding call.

Orientacyjne metryki: M1 — 50 maili / 10 rozmów / 3 triale; M3 — pierwsze 2–3 płacące; M6 — 10–15 agencji.

## 7. Cennik
**S/M/L/XL, unlimited devices, ~25% taniej rocznie** — pełna tabela i reguła quoty
(Opcja 2, sufit 2× startu) w [kanonie](../00-START-TUTAJ/2-DECYZJE-AKTUALNE.md#a-cennik-klienta-zatwierdzony).
Trial 30 dni (45 dla agencji), z ochroną przed abuse (soft limit 500 GB w trialu,
rate limit flushy, weryfikacja email, alerty).

## 8. Infrastruktura i model kosztu (NAJWIĘKSZA zmiana vs v6.2)
- **Storage primary = dedykowany serwer OVH** (RAID5 ~10–11 TB, `/mnt/storage`), restore instant.
- **DR docelowo = drugi serwer dedykowany (Proxmox Backup Server)** — identyczny box tylko na backupy, koszt stały, inkrementalny+dedup. Na teraz: dowolna tania kopia offsite („byle gdzie zgrane"). OVH cold odrzucone jako za drogie (per-GB).
- **Koszt = STAŁY ~135 zł brutto/mc** za cały serwer (nie per-GB jak w v6.2).
- Szczegóły: [kanon §B/§C/§D](../00-START-TUTAJ/2-DECYZJE-AKTUALNE.md#b-storage--gdzie-leza-dane-zatwierdzony-2026-06-20) + [`../architecture/pricing-and-storage-economics.md`](../architecture/pricing-and-storage-economics.md) §9.

## 9. Koszty roczne (model All-Devin)
- **Rozwój:** intensywny 1-miesięczny sprint Devina, potem tani tryb utrzymania. Łączny koszt AI ~**5 500 zł/rok**.
- **Serwer:** ~135 zł brutto/mc ≈ **~1 620 zł/rok**.
- **VPS pomocniczy / domena / drobne:** wg potrzeb.
- Model AI jest tańszy niż ciągła subskrypcja wielu narzędzi (poprzednio szacowane ~9 600 zł/rok).

## 10. Rentowność (zaktualizowana na model stałego serwera)
- **Pokrycie samego serwera:** ~**5 klientów S** (albo 2 XL).
- **Pokrycie pełnych kosztów rocznych** (serwer + AI ~5 500 zł): przy mixie ≈ kilkanaście–kilkadziesiąt klientów (znacznie niżej niż 55 z v6.2, bo koszt storage przestał rosnąć per-GB).
- **Marża operacyjna:** ~75–90% (świeży klient 85–93%; worst-case na suficie 2× wciąż 70–86%).
- **Sufit per box:** ~68×S / 34×M / 20×L / 10×XL — skalowanie = dokładanie serwerów.
- Pełne wyprowadzenie: [`../architecture/pricing-and-storage-economics.md`](../architecture/pricing-and-storage-economics.md) §9.

> Uwaga: liczby progu rentowności z v6.2 (55 klientów / +9 676 zł) dotyczyły starego
> modelu (Hobby/Pro + storage per-GB) i **już nie obowiązują** — patrz wyżej.

## 11. Analiza ryzyk (kluczowe)
- **Dystrybucja > produkt (80/20).** Największe ryzyko to nie „czy zbudujemy", tylko „czy dotrzemy do agencji WP". Mitygacja: rozdz. 6.
- **Sufit pojemności + immutability.** „Nigdy nie kasujemy" → fizyczne bajty rosną; quota (sufit 2×) domyka box, ale trzeba monitorować zapełnienie i komunikować klientowi „backup zatrzyma się za ~X dni". Ratuje dedup + kompresja (~40%).
- **DR / single-server.** Jeden serwer + RAID5; dopóki nie ma drugiego serwera/PBS, offsite jest prowizoryczne („byle gdzie zgrane"). Docelowo drugi dedyk (Proxmox Backup Server) daje koszt stały i RODO; przed sprzedażą obcym offsite musi mieć umowę powierzenia. Trigger postawienia: ~50% zapełnienia primary lub rosnąca liczba obcych klientów.
- **Konwersja niższa niż optymistycznie.** Realnie 3–7%, nie 17% → po 100 klientów potrzeba ~1 500–2 000 trialów/rok. Stąd nacisk na segment WP (konwertuje lepiej).

## 12. Roadmapa
1. **MVP / dokończenie** (sprint Devin) — zostało: deploy najnowszego kodu na dedyk + pełny E2E + prowizoryczny offsite DR (docelowo drugi serwer/PBS) (patrz [`../00-START-TUTAJ/3-CO-JEST-ZROBIONE.md`](../00-START-TUTAJ/3-CO-JEST-ZROBIONE.md)).
2. **Dowody**: nagrania „disaster → restore → Audit PDF", rozbudowa landingu `softify-website /properbackup`.
3. **Dystrybucja**: content pod triggery (MC/self-host) + cold outreach do agencji WP.
4. **Legal**: DPA + umowa powierzenia (offsite DR) przed sprzedażą obcym.
5. **Skalowanie / DR docelowy**: drugi serwer dedykowany (PBS na backupy) wg triggera.

## 13. Kill-switch / scenariusz wyjścia
Koszt stały jest niski (serwer ~135 zł/mc + AI), więc eksperyment jest tani. Jeśli po
zdefiniowanym oknie dystrybucja nie dowozi trialów/konwersji — wygaszamy z minimalną stratą
(scenariusz katastrofalny przewidziany i akceptowalny).
