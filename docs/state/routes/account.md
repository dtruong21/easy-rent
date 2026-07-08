# Routes — account

> Source d'état — account (auth, profil, réglages/thème, support). Maintenu par state-keeper.

## Publiques (hors shell, transition fade)

| Chemin | Page | Guard | Notes / deep-link |
|---|---|---|---|
| `/` | LandingPage | unauth OR anonyme→`/simulator` | carrefour onboarding |
| `/login` | LoginPage | !fullyAuth | email/pwd + Google/Apple |
| `/signup` | SignupPage | !fullyAuth | inscription + gate RGPD |
| `/forgot-password` | ForgotPasswordPage | public | reset mot de passe |
| `/reset-password` | ResetPasswordPage | public | lien email, `?token=…` via `state.uri.queryParameters` |
| `/privacy` | PrivacyPage | public | politique confid. v1.2 (loi 6 juillet 1989), FEAT-023 |
| `/terms` | TermsPage | public | CGU v2-2026-07 (FEAT-023) |
| `/delete-account` | DeleteAccountRequestPage | public (anonyme inclus) | **FEAT-045** — URL Google Play « Account deletion » ; CTA adapté session (login / go profil / suppr essai anonyme) |
| `/faq` | FaqPage | public (anonyme inclus) | **FEAT-048** — questions fréquentes (ExpansionTiles), aussi via Profil→Aide |

## Profil (shell branche 4, FEAT-025b, fullyAuth, transition standard)

| Chemin | Page | Type | Notes |
|---|---|---|---|
| `/profile` | ProfilePage | read | hub réglages (ordre 2026-07-07 : Compte détails/mot de passe/**suppression** · Apparence · Aide **FAQ**/contact/légal · À propos · Session) |
| `/profile/details` | ProfileDetailsPage | write | email/fullName (FEAT-025, immutables) |
| `/profile/password` | ChangePasswordPage | write | `reauthenticateWithPassword` + `updatePassword` ; gated `hasPasswordProvider` |
| `/profile/support` | SupportPage | write | formulaire contact (FEAT-025, collection `support_requests`) |
| `/profile/delete-account` | DeleteAccountPage | write | **FEAT-045** — re-auth par provider + révocation Apple + callable `deleteAccount` ; rétention quittances annoncée |

## Provider

- `themeModeProvider` (FEAT-023) : StateProvider<ThemeMode>, SharedPreferences, défaut `ThemeMode.system` (System / Light / Dark).

**FEATs** : FEAT-001 (auth, 4 routes), FEAT-023 (settings `/terms` `/privacy` + thème), FEAT-025 (support), FEAT-025b (profile hub, 3 routes), FEAT-045 (suppression compte, 2 routes), FEAT-048 (FAQ).
