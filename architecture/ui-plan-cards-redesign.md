# UI Plan Cards — Redesign

## Zmiana

Redesign kart planów subskrypcyjnych na stronie `/account/subscription`.

### Przed zmianą

- Badge "Best value" na karcie rocznej (highlight)
- Aktywny plan wyróżniony tym samym stylem co "Best value"
- Brak jasnej informacji o oszczędnościach

### Po zmianie

1. **Usunięto "Best value"** — żaden plan nie jest faworyzowany wizualnie
2. **Aktywny plan** ma wyraźnie inny kontrast:
   - Niebieska ramka (`border-2 border-accent`)
   - Tło z akcentem (`bg-accent/[0.08]`)
   - Cień (`shadow-lg shadow-accent/15 ring-1 ring-accent/20`)
   - Badge "AKTYWNY PLAN" (`-top-3 left-4`, białe na niebieskim)
3. **Oszczędności w opisie rocznego planu**:
   - PL: "Płacisz za 10 miesięcy, a korzystasz przez 12 — oszczędzasz 38 PLN rocznie."
   - EN: "Pay for 10 months, use for 12 — save 38 PLN per year."

## Implementacja

### SubscriptionPage.jsx — borderClass

```jsx
const borderClass = isActive
  ? 'border-2 border-accent bg-accent/[0.08] shadow-lg shadow-accent/15 ring-1 ring-accent/20'
  : 'border border-border hover:border-accent/40';
```

### Usunięto

- Prop `highlight` z komponentu PlanCard
- Rendering badge "Best value"
- Warunkowa logika `highlight` w borderClass

### Translations (pl.json / en.json)

```json
"planAnnualDesc": "Płacisz za 10 miesięcy, a korzystasz przez 12 — oszczędzasz 38 PLN rocznie."
```

## Stany kart

| Stan użytkownika | Karta Monthly | Karta Annual |
|------------------|--------------|-------------|
| Trial | Zwykła ramka, "Wybierz i zapłać" | Zwykła ramka, "Wybierz i zapłać" |
| Monthly aktywna | **Niebieska ramka**, "AKTYWNY PLAN", "Anuluj/Odnów" | Zwykła ramka, "Wybierz i zapłać" |
| Annual aktywna | Zwykła ramka, "Wybierz i zapłać" | **Niebieska ramka**, "AKTYWNY PLAN", "Anuluj/Odnów" |
| Brak planu | Zwykła ramka, "Wybierz i zapłać" | Zwykła ramka, "Wybierz i zapłać" |

## Pliki zmienione

- `properbackup-web/src/subscription/SubscriptionPage.jsx`
- `properbackup-web/src/i18n/locales/pl.json`
- `properbackup-web/src/i18n/locales/en.json`
