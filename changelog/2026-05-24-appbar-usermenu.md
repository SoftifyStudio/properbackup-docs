# AppBar User Menu — nawigacja do konta i rozliczeń

**Data:** 2026-05-24  
**PRy:** web#29 (devin/1779627002-appbar-account-nav)

## Problem

Użytkownik po zalogowaniu, który nie miał jeszcze żadnych serwerów, był zablokowany na stronie
"Twoje serwery" (OnboardingWizard) i nie mógł przejść do ustawień konta ani rozliczeń.
W AppBarze brakowało linku do `/account/subscription`.

## Rozwiązanie

Zamieniono statyczny blok użytkownika (email + przycisk "Wyloguj") na rozwijane menu (`UserMenu`):

- **Konto i rozliczenia** — nawiguje do `/account/subscription`
- **Wyloguj** — wylogowuje użytkownika

Menu zamyka się po kliknięciu poza nim lub naciśnięciu klawisza Escape.

## Zmiany

| Plik | Zmiana |
|------|--------|
| `src/layout/AppHeader.jsx` | Nowy komponent `UserMenu` z dropdown menu |
| `src/i18n/locales/en.json` | `header.accountBilling`: "Account & Billing" |
| `src/i18n/locales/pl.json` | `header.accountBilling`: "Konto i rozliczenia" |

## Testy E2E na żywym serwerze

Wszystkie 5 testów przeszło pomyślnie na `properbackup-test-server.softify.com.pl`:

1. Dropdown otwiera się z opcjami Account & Billing + Log out
2. Kliknięcie Account & Billing nawiguje do /account/subscription
3. Przycisk wstecz wraca do /servers
4. Dropdown zamyka się po kliknięciu poza nim
5. Tłumaczenie PL: "Konto i rozliczenia" / "Wyloguj"

## Accessibility

- `aria-expanded` przełącza się poprawnie (true/false)
- `aria-haspopup="true"` na przycisku trigger
- Zamknięcie klawiszem Escape
- Zamknięcie kliknięciem poza menu
