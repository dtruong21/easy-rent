# Routes — account

> Source d'état — account (auth, profil, réglages/thème, support). Maintenu par state-keeper.

## Publiques (hors shell, transition fade)

| Chemin | Page | Guard | Notes / deep-link |
|---|---|---|---|
| `/` | LandingPage | unauth OR anonyme→`/simulator` | carrefour onboarding ; **PR #126** : pied de page = version app + pastille d'environnement (pastille masquée en prod, rien tant que `appInfoProvider` charge) |
| `/login` | LoginPage | !fullyAuth | email/pwd + Google/Apple |
| `/signup` | SignupPage | !fullyAuth | inscription + gate RGPD |
| `/forgot-password` | ForgotPasswordPage | public | reset mot de passe |
| `/reset-password` | ResetPasswordPage | public | lien email, `?token=…` via `state.uri.queryParameters` |
| `/privacy` | PrivacyPage | public | politique confid. v1.4 (loi 6 juillet 1989), FEAT-023 |
| `/terms` | TermsPage | public | CGU v2-2026-07 (FEAT-023) |
| `/legal` | LegalPage | public | mentions légales (LCEN), liée depuis le hub Profil — **manquait dans l'état** |
| `/delete-account` | DeleteAccountRequestPage | public (anonyme inclus) | **FEAT-045** — URL Google Play « Account deletion » ; CTA adapté session (login / go profil / suppr essai anonyme) |
| `/faq` | FaqPage | public (anonyme inclus) | **FEAT-048** — questions fréquentes (ExpansionTiles), aussi via Profil→Aide |

## Profil (shell branche 4, FEAT-025b, fullyAuth, transition standard)

| Chemin | Page | Type | Notes |
|---|---|---|---|
| `/profile` | ProfilePage | read | hub réglages (ordre 2026-07-07 : Compte détails/mot de passe/**suppression** · Apparence · Aide **FAQ**/contact/« Donner mon avis » (FEAT-060, toujours)/« Noter l'app » (FEAT-060, apps store ; iOS seulement si `APP_STORE_ID`)/légal · À propos · Session). **Abonné store** (`proStore` ∈ `mobileStores`, web comme apps, FEAT-044e) : `SubscriptionSection` affiche « Gérer dans {store} » (store d'origine ; URL RevenueCat si connue, sinon page générique du store), sans Résilier, Réactiver ni Changer d'offre. **Apps iOS/Android** (`isStoreApp`) : bannière « Passer à Pro » (→ `/pro`) seulement quand l'achat intégré est actif (`(storeApp ? inAppPurchaseEnabled : subscriptionsEnabled) && !isPaid`) ; abonné web : statut + « Résilier » (callable `manageSubscription` `cancel`, accepté sans Origin), « Réactiver » et « Changer d'offre » masqués |
| `/profile/details` | ProfileDetailsPage | write | email/fullName (FEAT-025, immutables) |
| `/profile/password` | ChangePasswordPage | write | `reauthenticateWithPassword` + `updatePassword` ; gated `hasPasswordProvider` |
| `/profile/support` | SupportPage | write | formulaire contact (FEAT-025, collection `support_requests`) |
| `/profile/feedback` | FeedbackPage | write | « Donner mon avis » (FEAT-060) : note 1-5 obligatoire + commentaire facultatif (≤ 2000) → `support_requests` (`kind: feedback`) |
| `/profile/delete-account` | DeleteAccountPage | write | **FEAT-045** — re-auth par provider + révocation Apple + callable `deleteAccount` ; rétention quittances annoncée. **Avis abonnement** (`DeleteAccountSubscriptionNotice`, toutes plateformes, palier payant) : `proStore` ∈ `mobileStores` (app_store/play_store) → « la suppression ne résilie pas, résiliez dans le store » ; `proStore == 'web'` → « résilié immédiatement, sans remboursement » ; `promo`/`null`/autre → rien |

## Pro/Abonnements (shell branche 3, fullyAuth, FEAT-044e/FEAT-056 intégration client web)

| Chemin | Page | Type | Notes |
|---|---|---|---|
| `/pro` | ProPricingPage | read | **FEAT-056** : cartes 3 paliers (Pro achetable, Max/Ultra démonstration) + FAQ, CTA menant à checkout. Abonné web, vente ouverte : changement de palier (`btn_plan_change_<id>`) et, sur la carte du palier détenu, passage mensuel ↔ annuel selon l'interrupteur (`btn_plan_switch_period_<id>`, `manageSubscription('change_plan')` même palier ; bouton affiché seulement vers l'AUTRE périodicité : `currentBillingPeriodProvider` lit `manageSubscription('current_plan')`, inconnue/chargement/erreur → masqué ; règles dans `pro_pricing_cta.dart`, gate injectable pour les tests). **Apps iOS/Android** (`isStoreApp`) : titre « Baillan Pro » (jamais Max/Ultra), interrupteur actif ou coupé ; interrupteur `IAP_ENABLED` coupé → message neutre seul (`txt_pro_store_app_unavailable`) : ni offres, ni prix, ni bouton, aucune mention du web. Interrupteur actif → `ProStorePaywall` (`widgets/pro_store_paywall.dart`) : Pro seul, mensuel et annuel, prix lus dans le store (jamais Max/Ultra ni prix web) ; « Restaurer les achats » ; mentions 3.1.2 et liens `/terms` `/privacy`. Après achat ou restauration : « Activation en cours… » jusqu'au droit accordé par le serveur (`planEntitlementProvider`, écrit par le webhook RevenueCat) ; au-delà de 60 s (`kStoreActivationTimeout`) : « Réessayer » (relance l'attente, jamais un second achat) + « Restaurer les achats ». À l'ouverture, si le store voit déjà un abonnement actif pour le compte (`storeActiveEntitlementProvider`), l'écran reprend cette attente au lieu d'afficher les offres. Achat ou restauration refusés parce que l'abonnement existe déjà : message dédié (déjà actif sur le compte store → « Restaurer » ; rattaché à un autre compte Baillan). Déjà Pro ou plus (toute origine) → « Vous êtes déjà abonné » + « Gérer mon abonnement » (→ `/profile`), aucun bouton d'achat. Palier inconnu → aucun bouton d'achat ni offre demandée : en chargement (y compris rechargement qui garde la valeur précédente) → indicateur ; en erreur ou réglé à `null` (aucun document `landlords/{uid}`) → « offres indisponibles » + réessayer |
| `/pro/success` | ProSuccessPage | read | **FEAT-044e/056** : redirection Stripe Checkout post-paiement réussi ; extract `session_id` de query param ; confirmation + CTA retour dashboard |
| `/pro/cancel` | ProCancelPage | read | **FEAT-044e/056** : redirection Stripe Checkout post-annulation ; invite à réessayer ou revenir. **Apps iOS/Android** : « Réessayer » masqué (seul le retour reste) |

## Provider

- `themeModeProvider` (FEAT-023) : StateProvider<ThemeMode>, SharedPreferences, défaut `ThemeMode.system` (System / Light / Dark).

**FEATs** : FEAT-001 (auth, 4 routes), FEAT-023 (settings `/terms` `/privacy` + thème), FEAT-025 (support), FEAT-025b (profile hub, 3 routes), FEAT-045 (suppression compte, 2 routes), FEAT-048 (FAQ).
