# Plan — [FEAT-010] Dashboard + Polish PWA + Déploiement prod

> Source story : [`docs/backlog/010-dashboard-pwa-prod-setup.md`](../backlog/010-dashboard-pwa-prod-setup.md)
> Branche cible : `feature/dashboard-pwa-prod-setup`
> Patterns de référence :
> - Module feature (domain / data / application / presentation) : [`docs/plans/FEAT-009-documents-storage.md`](FEAT-009-documents-storage.md), [`docs/plans/FEAT-008-email-quittance.md`](FEAT-008-email-quittance.md), [`docs/plans/FEAT-007-quittance-pdf.md`](FEAT-007-quittance-pdf.md)
> - AsyncNotifierProvider + invalidate sur opération : [`lib/features/receipts/application/lease_receipts_provider.dart`](../../lib/features/receipts/application/lease_receipts_provider.dart)
> - Multi-env deploy : [`docs/ENVIRONMENTS.md`](../ENVIRONMENTS.md), [`.github/workflows/deploy.yml`](../../.github/workflows/deploy.yml)
>
> **Décisions actées par l'utilisateur** :
> - **D1 = 4 KPI cards** : loyers du mois, retards, renouvellements 30j, documents en attente
> - **D2 modifié = mini-barchart inclus** (6 mois glissants, dépendance `fl_chart`)
> - **D3 = install prompt PWA au 1er login** + dismiss persisté via `SharedPreferences`
> - **D4 = icône PWA placeholder "ER"** sur teal `#0F766E` (192 + 512 px, générées via ImageMagick / script)
> - **D5 = migration prod via `workflow_dispatch`** avec input `confirm=yes/no` → `supabase db push`
> - **Resend prod = blocker de go-live** : infra livrée, deploy effectif attendra que le domaine soit vérifié. Documenté dans la checklist.

---

## 1. Vue d'ensemble

**Objectif** : Livrer la dernière feature avant le 1er déploiement prod en couvrant 3 concerns distincts :

- **A. Dashboard refonte** — Remplacer la page `ListTile` actuelle (3 raccourcis) par un cockpit : 4 KPI cards, mini-barchart 6 mois, activité récente, raccourcis compacts, onboarding « Premiers pas » quand tout est vide, install prompt PWA en haut.
- **B. Polish PWA** — Compléter le `manifest.json`, générer les icônes placeholder « ER » (192/512), splash screen aux couleurs primaires, activer le service worker offline-first en prod, install prompt JS interop.
- **C. Setup déploiement prod** — Étendre `deploy.yml` pour la prod, créer `migrate-prod.yml` (`workflow_dispatch`), provisionner `dart-defines.prod.json.example`, enrichir la page `/privacy` RGPD, livrer runbook + checklist + rollback.

**Dépendances bloquantes** :
- FEAT-001 (auth) — install prompt déclenché au 1er login authentifié
- FEAT-005 (leases), FEAT-006 (payments), FEAT-007 (receipts), FEAT-009 (documents) — sources des KPI
- Aucune nouvelle table / RPC / Edge Function — la feature est 100% Flutter + infra

**Hors scope** (cohérent story §Out of scope) :
- Charts complets type Stripe/Brex (vision financial dashboard) — l'amorce architecturale est dans `KpiCard.child` slot
- Icône PWA design pro — placeholder « ER » uniquement
- Notifications push PWA
- Export / effacement RGPD self-service
- Monitoring prod (Sentry, logs structurés) — runbook manuel uniquement
- Hardening flag GUC `app.allow_deleted_at_change` (dette FEAT-002, P1)

---

## 2. Modèle de données

**Aucun changement schéma.** Toutes les requêtes KPI sont des `SELECT` agrégés via RLS standard (`landlord_id = auth.uid()`). Aucune nouvelle policy.

### 2.1 Requêtes SQL utilisées par le dashboard

Toutes effectuées via `Db.from(...)` (schéma courant `public` ou `dev`), avec filtre RLS implicite.

| KPI | Table(s) | Requête conceptuelle |
|---|---|---|
| **Loyers du mois (encaissé)** | `payments` | `SUM(rent_amount_cents + charges_amount_cents) WHERE paid_at BETWEEN début_mois AND fin_mois AND deleted_at IS NULL` |
| **Loyers du mois (dû)** | `leases` | `SUM(rent_amount_cents + charges_amount_cents) WHERE status='active' AND deleted_at IS NULL` (snapshot mensuel théorique des baux actifs) |
| **Locataires en retard** | `leases` + `payments` | `count(DISTINCT lease_id) FROM leases l WHERE l.status='active' AND l.deleted_at IS NULL AND NOT EXISTS (SELECT 1 FROM payments p WHERE p.lease_id = l.id AND p.deleted_at IS NULL AND p.paid_at >= now() - interval '35 days')` — hypothèse simplificatrice MVP (35j = ~1 mois + tolérance) |
| **Baux à renouveler 30j** | `leases` | `count(*) WHERE status='active' AND deleted_at IS NULL AND end_date BETWEEN current_date AND current_date + interval '30 days'` |
| **Documents en attente** | `documents` | `count(*) WHERE category='autre' AND deleted_at IS NULL` — proxy MVP (« autre » = pas encore catégorisé), à raffiner P1 quand on aura un workflow d'attente explicite |
| **Activité récente** | UNION ALL `payments`, `receipts`, `documents` | Top 5 lignes par `created_at DESC`, projetées en un type unifié `ActivityItem` (cf. §6.1) |
| **Barchart 6 mois** | `payments` + `leases` | Par mois M-5 → M : `SUM(payments.amount WHERE paid_at IN month)` (encaissé) et `SUM(leases.amount WHERE active during month)` (dû) — calcul agrégé côté Dart à partir d'une fenêtre 6 mois |
| **Onboarding test** | `properties`, `tenants`, `leases` | `count` rapide sur chaque table — si les 3 sont 0 → on affiche l'onboarding au lieu des KPI |

**Note RLS** : aucune nouvelle policy. Les policies existantes (`*_select_own`) garantissent qu'aucun bailleur ne voit les chiffres d'un autre.

**Note performance** : les 4 KPI + barchart + activité + onboarding-test = 7 requêtes parallélisées via `Future.wait`. Acceptable pour MVP (<150ms total typique sur projet Supabase EU). Si besoin P1 : RPC unique `get_dashboard_snapshot()` qui agrège tout côté SQL.

### 2.2 Rétention / cohérence

- Les requêtes lisent `deleted_at IS NULL` partout (RLS le force déjà sur la plupart des tables, mais on est explicite côté Dart pour la lisibilité).
- L'activité récente inclut les receipts `is_voided=true` et `is_stale=true` (avec un libellé approprié) pour pas perdre le fil — décision conservatrice cohérente avec l'immuabilité métier.

---

## 3. Backend / Edge Functions

**Aucune Edge Function.** Tout est client-side via le SDK Supabase. Toute la logique KPI est en SQL `SELECT` + agrégation Dart.

**Aucune RPC ajoutée.** Pas de SECURITY DEFINER nécessaire.

---

## 4. Flutter — Section A : Dashboard refonte

### 4.1 Arborescence

Pattern strict aligné [`lib/features/receipts/`](../../lib/features/receipts/) et [`lib/features/documents/`](../../lib/features/documents/).

```
lib/features/dashboard/
├── domain/
│   ├── dashboard_kpi.dart                       # sealed union freezed (LoyersMois | Retards | Renouvellements | DocsPending)
│   ├── dashboard_kpi.freezed.dart               # GÉNÉRÉ
│   ├── dashboard_snapshot.dart                  # @freezed agrège les 4 KPI + activity + monthly + onboardingState
│   ├── dashboard_snapshot.freezed.dart          # GÉNÉRÉ
│   ├── activity_item.dart                       # sealed union freezed (PaymentRecorded | ReceiptGenerated | DocumentUploaded)
│   ├── activity_item.freezed.dart               # GÉNÉRÉ
│   ├── monthly_amount.dart                      # @freezed (yearMonth, encaissedCents, dueCents)
│   └── monthly_amount.freezed.dart              # GÉNÉRÉ
├── data/
│   └── dashboard_repository.dart                # interface + SupabaseDashboardRepository + provider Riverpod
├── application/
│   └── dashboard_provider.dart                  # AsyncNotifierProvider<DashboardSnapshot> (fan-in Future.wait)
└── presentation/
    ├── dashboard_page.dart                      # refonte (remplace l'existante)
    └── widgets/
        ├── kpi_card.dart                        # Card responsive avec icon + value + label + couleur sémantique + child slot
        ├── kpi_grid.dart                        # GridView/Wrap responsive (4 cols > 900px, 1 col mobile)
        ├── monthly_barchart.dart                # fl_chart BarChart wrapper (6 mois, encaissé vs dû)
        ├── recent_activity_section.dart         # ListView 5 entrées (PaymentRecorded → /leases/:id/payments/:pid/edit, etc.)
        ├── activity_tile.dart                   # tile générique (icon, title, subtitle, date, onTap)
        ├── shortcuts_row.dart                   # 3 cartes compactes (biens / locataires / baux)
        ├── onboarding_first_steps.dart          # checklist guidée (3 étapes cliquables) si tout est vide
        ├── dashboard_header.dart                # "Bonjour <prénom>" + date du jour
        └── install_prompt_banner.dart           # voir §5 (importé depuis lib/features/pwa/)
```

### 4.2 Modèle `DashboardSnapshot` (freezed)

```dart
@freezed
class DashboardSnapshot with _$DashboardSnapshot {
  const factory DashboardSnapshot({
    required LoyersMoisKpi loyers,
    required RetardsKpi retards,
    required RenouvellementsKpi renouvellements,
    required DocsPendingKpi docs,
    required List<MonthlyAmount> monthly,    // 6 entrées (M-5 → M)
    required List<ActivityItem> activity,    // top 5
    required bool isOnboarding,              // true ssi 0 properties + 0 tenants + 0 leases
  }) = _DashboardSnapshot;
}
```

### 4.3 Repository (interface)

```dart
abstract interface class DashboardRepository {
  Future<LoyersMoisKpi> fetchLoyersMois();
  Future<RetardsKpi> fetchRetards();
  Future<RenouvellementsKpi> fetchRenouvellements();
  Future<DocsPendingKpi> fetchDocsPending();
  Future<List<MonthlyAmount>> fetchLast6MonthsAmounts();
  Future<List<ActivityItem>> fetchRecentActivity({int limit = 5});
  Future<bool> isLandlordOnboarding();  // count(properties) + count(tenants) + count(leases) = 0
}
```

Implémentation `SupabaseDashboardRepository` : chaque méthode = 1 requête `Db.from(...)` ou `Db.rpc(...)` (cf. §2.1). Aucune mutation.

### 4.4 Provider — fan-in parallèle

```dart
final dashboardProvider = AsyncNotifierProvider<DashboardController, DashboardSnapshot>(...);

class DashboardController extends AsyncNotifier<DashboardSnapshot> {
  @override
  Future<DashboardSnapshot> build() async {
    final repo = ref.watch(dashboardRepositoryProvider);
    // 1) Test onboarding en 1er — si true, on évite les 6 autres requêtes
    final isOnboarding = await repo.isLandlordOnboarding();
    if (isOnboarding) {
      return DashboardSnapshot.empty(isOnboarding: true);
    }
    // 2) Fan-in parallèle des 6 KPI/activité
    final results = await Future.wait([
      repo.fetchLoyersMois(),
      repo.fetchRetards(),
      repo.fetchRenouvellements(),
      repo.fetchDocsPending(),
      repo.fetchLast6MonthsAmounts(),
      repo.fetchRecentActivity(),
    ]);
    return DashboardSnapshot(
      loyers: results[0] as LoyersMoisKpi,
      retards: results[1] as RetardsKpi,
      renouvellements: results[2] as RenouvellementsKpi,
      docs: results[3] as DocsPendingKpi,
      monthly: results[4] as List<MonthlyAmount>,
      activity: results[5] as List<ActivityItem>,
      isOnboarding: false,
    );
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(build);
  }
}
```

**Invalidations** : à chaque retour vers `/` depuis une page de mutation (création paiement, génération quittance, upload doc...) → `ref.invalidate(dashboardProvider)`. À implémenter sur `pop` de chaque page concernée (Listener `go_router`) OU plus simplement : `RefreshIndicator` sur la page + invalidation au resume de l'app via `WidgetsBindingObserver` (P1).

**MVP** : pull-to-refresh manuel via `RefreshIndicator` + invalidation au focus de la page (`useFocusEffect` n'existe pas en go_router → on utilise `ref.invalidate` dans le `build` de chaque page mutation au moment du retour, ou refresh manuel par bouton).

### 4.5 Widget `DashboardPage` — composition

```
Scaffold
├── AppBar (titre "EasyRent" + bouton logout existant + bouton /profile)
└── RefreshIndicator(onRefresh: () => ref.invalidate(dashboardProvider))
    └── ListView (padding 16)
        ├── InstallPromptBanner (cf. §5)        // affiché conditionnellement
        ├── DashboardHeader("Bonjour <prénom>", date du jour)
        ├── snapshot.when(
              loading: → 4 KpiCard skeleton + barchart skeleton
              error:   → ErrorView avec bouton "Réessayer"
              data:    →
                  if (isOnboarding) OnboardingFirstSteps
                  else Column [
                    KpiGrid(4 cards),
                    MonthlyBarchart(6 mois),
                    RecentActivitySection(activity),
                    ShortcutsRow(3 raccourcis compacts),
                  ]
            )
```

### 4.6 `KpiCard` — anatomie

```dart
class KpiCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;
  final Color? semanticColor;   // ex: rouge si retards > 0
  final VoidCallback? onTap;
  final Widget? child;          // slot pour mini-chart futur (vision financial dashboard, vide en MVP)
}
```

Layout responsif via `LayoutBuilder` :
- Largeur disponible > 900 → `KpiGrid` = `Wrap` ou `GridView` 4 colonnes
- Largeur disponible 600-900 → 2 colonnes
- Largeur disponible < 600 → 1 colonne (liste verticale)

Couleurs sémantiques :
- Retards > 0 → `colorScheme.error` (texte) + `colorScheme.errorContainer` (icône wrap)
- Renouvellements > 0 (≤ 30j) → `colorScheme.tertiary` (warning friendly)
- Loyers du mois encaissé < dû → `colorScheme.error` ; sinon `colorScheme.primary`
- DocsPending = 0 → couleur neutre `onSurfaceVariant`

### 4.7 `MonthlyBarchart` — fl_chart

- Wrapper minimal autour de `BarChart` du package `fl_chart`
- 6 groupes de 2 barres (encaissé teal `colorScheme.primary` + dû outline `colorScheme.outline`)
- Hauteur fixe 200 px sur desktop, 160 px sur mobile
- Tooltips au tap (`BarTouchData` natif fl_chart)
- Labels axe X : `janv.` / `févr.` / `mars` ... (via `intl` `DateFormat.MMM('fr')`)
- Labels axe Y : `1,2k €` (helper `formatCompactEuros`)
- Légende sous le chart : 2 chips colorés (encaissé / dû)

**Tests** : widget test snapshot sur 6 mois données fixes + cas tous-zéros (empty state inline).

### 4.8 `RecentActivitySection`

- Section avec header "Activité récente" + bouton "Voir tout" (désactivé en MVP — pas de page dédiée)
- 5 tiles maximum
- Mapping `ActivityItem` → tile :
  - `PaymentRecorded(payment)` → icon `payments_outlined`, title "Paiement enregistré · {tenantName}", subtitle "{amount}€ · {paid_at}", onTap → `/leases/{leaseId}/payments/{paymentId}/edit`
  - `ReceiptGenerated(receipt)` → icon `description_outlined`, title "Quittance générée · {period}", subtitle "{amount}€", onTap → `/leases/{leaseId}/receipts`
  - `DocumentUploaded(document)` → icon `attach_file_outlined`, title "{category.label} · {filename}", subtitle "{sizeHuman}", onTap → `/leases/{leaseId}` (section documents)
- Si liste vide : empty state "Aucune activité récente. Commencez par enregistrer un paiement."

### 4.9 `ShortcutsRow` — 3 raccourcis compacts

Reformat des 3 ListTile actuels en cartes compactes (icône + label) sur 1 ligne (Wrap responsive). Identique en routing aux 3 actuelles (`/properties`, `/tenants`, `/leases`).

### 4.10 `OnboardingFirstSteps`

Affiché uniquement si `isOnboarding == true`. Layout :

```
Card (elevated, padding 24)
  ├── Icon rocket_launch_outlined (size 48, color primary)
  ├── Text "Bienvenue ! Premiers pas" (titleLarge)
  ├── Text "Suivez ces 3 étapes pour démarrer." (bodyMedium, onSurfaceVariant)
  ├── _StepTile(1, "Ajouter un bien", "home_outlined", → /properties/new)
  ├── _StepTile(2, "Ajouter un locataire", "person_outline", → /tenants/new)
  └── _StepTile(3, "Créer un bail", "description_outlined", → /leases/new)
```

Chaque step → `ListTile` avec leading numéro circulaire + trailing chevron + onTap navigation.

**Note** : on n'utilise pas une checklist persistée — l'onboarding apparaît dynamiquement tant que les 3 counts sont 0. Dès qu'au moins une entité existe, le dashboard normal s'affiche.

---

## 5. Flutter — Section B : Polish PWA

### 5.1 Arborescence module `lib/features/pwa/`

```
lib/features/pwa/
├── data/
│   ├── install_prompt_storage.dart          # SharedPreferences wrapper (key: pwa_install_prompt_dismissed_at)
│   └── install_prompt_js_bridge.dart        # dart:js_interop bridge (beforeinstallprompt + matchMedia standalone)
├── application/
│   └── install_prompt_controller.dart       # StateNotifier (visible / hidden / triggering / installed / unsupported)
└── presentation/
    └── install_prompt_banner.dart           # Material 3 banner card (Action "Installer" + bouton Close X)
```

### 5.2 Manifest et icônes

**Audit `web/manifest.json`** : le fichier actuel est déjà conforme (cf. §inspection). À auditer pour confirmer :
- `name` = "EasyRent — Gestion locative" ✅
- `short_name` = "EasyRent" ✅
- `theme_color` = `#0F766E` ✅
- `background_color` → **à passer de `#1E293B` (slate) à `#0F766E` (teal)** pour cohérence splash
- `display` = "standalone" ✅
- `start_url` → **passer de `"."` à `"/"`** (recommandation Lighthouse)
- `icons` : 4 entrées existantes (192, 512, maskable 192, maskable 512) → **à régénérer en placeholder "ER"**

**Icônes placeholder "ER"** :
- 4 fichiers à régénérer dans `web/icons/` : `Icon-192.png`, `Icon-512.png`, `Icon-maskable-192.png`, `Icon-maskable-512.png`
- Design : fond `#0F766E`, texte "ER" blanc, font sans-serif gras (Helvetica/Inter), border-radius 24% pour les non-maskable
- Outil : script bash `scripts/generate-pwa-icons.sh` utilisant ImageMagick (`convert`) :
  ```bash
  convert -size 192x192 xc:'#0F766E' -fill white -gravity center \
    -font Helvetica-Bold -pointsize 80 -annotate +0+0 'ER' \
    -alpha set -channel A -fx 'i < 0.05 ? 0 : a' \
    web/icons/Icon-192.png
  ```
  + variantes 512, maskable (sans border-radius, safe zone 80%)
- Le script est checked-in, les PNG aussi (commit unique)
- Fallback si ImageMagick indispo en local : script Python `Pillow` équivalent fourni en alternative

### 5.3 `index.html` — splash + meta

Modifications minimales :
- Ajouter CSS inline dans `<head>` : `body { background: #0F766E; margin: 0; }` pour que le chargement Flutter soit visuellement continu avec le manifest
- Vérifier que `<meta name="theme-color" content="#0F766E">` est présent ✅
- `apple-touch-icon` ✅ déjà présent
- Aucun ajout JS — l'install prompt JS est géré côté Dart (cf. §5.5)

### 5.4 Service Worker

Flutter génère `flutter_service_worker.js` automatiquement avec `--pwa-strategy=offline-first` (default). Le workflow actuel `deploy.yml` :
- Staging : `--pwa-strategy=none` (désactive le SW — évite cache stale en preview)
- Prod : (rien → default `offline-first`)

Vérification : le SW Flutter precache automatiquement `main.dart.js`, `flutter.js`, `canvaskit/*`, `assets/fonts/*`. Aucune custom logic requise pour le MVP. **Documentation** : ajouter un paragraphe dans `docs/RUNBOOK_PROD_DEPLOY.md` expliquant que le SW doit invalider automatiquement le bundle quand le hash de `main.dart.js` change.

**Cache headers Firebase Hosting** : vérifier `firebase.json` pour assurer `Cache-Control: no-cache` sur `index.html` et `flutter_service_worker.js` (sinon le SW ne sera jamais updaté). Si absent → ajouter (modif `firebase.json`).

### 5.5 Install prompt — JS interop

**`install_prompt_js_bridge.dart`** :
```dart
import 'dart:js_interop';
import 'package:web/web.dart' as web;

extension type _BeforeInstallPromptEvent._(JSObject _) implements web.Event {
  external JSPromise<JSObject> prompt();
  external JSPromise<_UserChoice> get userChoice;
}

@JS('window.addEventListener')
external void _addEventListener(String type, JSExportedDartFunction listener);

class InstallPromptJsBridge {
  static _BeforeInstallPromptEvent? _deferred;

  static void captureDeferred() {
    _addEventListener('beforeinstallprompt', ((web.Event e) {
      e.preventDefault();
      _deferred = e as _BeforeInstallPromptEvent;
    }).toJS);
  }

  static bool get hasDeferred => _deferred != null;
  static bool get isStandalone =>
      web.window.matchMedia('(display-mode: standalone)').matches;

  static Future<bool> trigger() async { /* prompt + userChoice */ }
}
```

Appelé au démarrage de l'app (`main.dart` ou bootstrap d'auth) — ainsi l'event `beforeinstallprompt` est capturé même avant que l'utilisateur ne soit logué (Chrome le fire au load de la page).

**Spécifique iOS** : Safari iOS ne supporte PAS `beforeinstallprompt`. Détection : si `_deferred == null` ET user agent contient `iPhone`/`iPad` → afficher des instructions textuelles "Pour installer EasyRent : appuyez sur Partager → Ajouter à l'écran d'accueil". Variante du banner.

### 5.6 `InstallPromptController`

```dart
@freezed
sealed class InstallPromptState with _$InstallPromptState {
  const factory InstallPromptState.hidden() = _Hidden;             // standalone, dismissed récemment, ou unsupported
  const factory InstallPromptState.visibleNative() = _VisibleNative;   // Chrome/Edge — prompt natif disponible
  const factory InstallPromptState.visibleIos() = _VisibleIos;     // iOS — instructions manuelles
  const factory InstallPromptState.triggering() = _Triggering;
  const factory InstallPromptState.installed() = _Installed;
}
```

**Logique de visibilité** :
- Au démarrage : si `isStandalone == true` → `hidden`
- Sinon : lit `pwa_install_prompt_dismissed_at` depuis SharedPreferences. Si timestamp < 30 jours → `hidden`. Sinon → évalue support.
- Si support natif (`hasDeferred`) → `visibleNative`
- Si iOS Safari → `visibleIos`
- Sinon → `hidden` (Firefox desktop par ex.)

**Logique au 1er login** (D3) : le state observe `authControllerProvider`. Au 1er passage `authenticated`, si la clé `pwa_install_prompt_first_login_seen` est absente dans SharedPreferences → on force l'affichage du banner (transition vers visible). Ensuite on stocke la clé. Aux logins suivants, le banner suit la logique standard ci-dessus (dismiss-based).

**Actions** :
- `trigger()` → appelle `InstallPromptJsBridge.trigger()`, transition `triggering` → `installed` (sur accept) ou `hidden` (sur dismiss côté browser)
- `dismiss()` → écrit `pwa_install_prompt_dismissed_at = now()` dans SharedPreferences → transition `hidden`. Re-éligible 30 jours plus tard.

### 5.7 `InstallPromptBanner` widget

- Carte Material 3 en haut du dashboard (au-dessus de `DashboardHeader`)
- Couleurs : `surfaceContainerHigh` (cohérent thème), accent teal pour l'icône
- Layout : `Row` [`Icon`, `Column` [title, subtitle], `FilledButton`, `IconButton(close)`]
- Texte FR :
  - Title : "Installez EasyRent"
  - Subtitle native : "Accédez à votre gestion locative en un clic, même hors-ligne."
  - Subtitle iOS : "Appuyez sur Partager puis « Sur l'écran d'accueil »."
  - Bouton native : "Installer" (`onPressed → controller.trigger()`)
  - Bouton iOS : "OK, compris" (`onPressed → controller.dismiss()`)
- Animation : `AnimatedSwitcher` pour apparition/disparition douce

### 5.8 Dépendances Flutter à ajouter

| Package | Version | Justification |
|---|---|---|
| `fl_chart` | `^0.69.0` | Barchart 6 mois. Package standard Flutter, pure-Dart, no JS deps |
| `shared_preferences` | `^2.3.5` | Persiste le dismiss du install prompt + la flag "first login seen" |
| `web` | `^1.1.0` | Remplace `dart:html` pour JS interop (`beforeinstallprompt` + `matchMedia`) — package officiel Dart |

**Mise à jour pubspec.yaml** :
```yaml
dependencies:
  fl_chart: ^0.69.0
  shared_preferences: ^2.3.5
  web: ^1.1.0
```

**CSP Firebase Hosting** : aucune mise à jour. `fl_chart` est pure-Dart, `web` package n'ajoute pas de fetch externes.

---

## 6. Section C : Setup déploiement prod

### 6.1 `dart-defines.prod.json.example` (template commité)

Fichier nouveau, **commité en clair** (template uniquement) :

```json
{
  "SUPABASE_URL": "https://tbgttutodbqffrvsvkoz.supabase.co",
  "SUPABASE_ANON_KEY": "<REMPLIR_DEPUIS_DASHBOARD_SUPABASE>",
  "SUPABASE_SCHEMA": "public"
}
```

Le vrai `dart-defines.prod.json` est git-ignoré (`.gitignore` déjà configuré pour exclure `dart-defines.*.json`). En CI, on n'a PAS besoin du fichier — le workflow injecte les valeurs via `--dart-define=` directement (cf. `deploy.yml` existant).

### 6.2 Modifications `.github/workflows/deploy.yml`

Le workflow existant supporte déjà `main` → prod via `determine-env`. Modifications mineures :

1. **Activer le SW en prod** : déjà OK (default `offline-first`)
2. **Ajouter `SUPABASE_SCHEMA=public` en prod** : déjà géré par `determine-env`
3. **Vérifier que `apply-supabase-migrations` ne tourne PAS automatiquement** : actuellement le job tourne `if: github.ref == 'refs/heads/main'`. **Décision D5 → désactiver le trigger automatique** :
   - **Modifier** la condition pour : `if: false` (commenter le job pour MVP) OU laisser tourner mais documenter clairement que c'est par-dessus.
   - **Recommandation MVP** : commenter le job entièrement dans `deploy.yml` et migrer toute la logique vers `migrate-prod.yml` (cf. §6.3) — séparation de responsabilité claire, pas de migration silencieuse sur push main.

### 6.3 Nouveau workflow `.github/workflows/migrate-prod.yml`

```yaml
name: Apply migrations to PROD (manual)

on:
  workflow_dispatch:
    inputs:
      confirmation:
        description: 'Taper "yes" pour confirmer l'application des migrations sur public (PROD)'
        required: true
        type: string
      dry_run:
        description: 'Afficher les migrations à appliquer sans les exécuter'
        required: false
        type: boolean
        default: false

concurrency:
  group: migrate-prod
  cancel-in-progress: false

jobs:
  apply:
    name: Apply migrations
    runs-on: ubuntu-latest
    environment: production
    if: github.event.inputs.confirmation == 'yes'
    steps:
      - uses: actions/checkout@v4

      - uses: supabase/setup-cli@v1
        with:
          version: latest

      - name: Link project (prod)
        run: supabase link --project-ref ${{ secrets.SUPABASE_PROJECT_REF }}
        env:
          SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}
          SUPABASE_DB_PASSWORD: ${{ secrets.SUPABASE_DB_PASSWORD }}

      - name: List pending migrations
        run: supabase migration list --linked
        env:
          SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}
          SUPABASE_DB_PASSWORD: ${{ secrets.SUPABASE_DB_PASSWORD }}

      - name: Apply migrations (db push)
        if: github.event.inputs.dry_run != 'true'
        run: supabase db push --linked
        env:
          SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}
          SUPABASE_DB_PASSWORD: ${{ secrets.SUPABASE_DB_PASSWORD }}
```

**Sécurité** :
- `environment: production` → utilise les protected secrets + nécessite un reviewer approval si configuré côté GitHub
- `if: github.event.inputs.confirmation == 'yes'` → bloque l'exécution si l'utilisateur n'a pas tapé "yes" exactement
- `dry_run` permet de lister les migrations avant application
- `concurrency` empêche 2 runs simultanés (race sur `supabase migrations` table)

### 6.4 Secrets GitHub à provisionner

Liste exhaustive pour l'environnement `production` (à créer dans Settings → Environments → `production`) :

| Secret | Valeur | Source |
|---|---|---|
| `SUPABASE_URL` | `https://tbgttutodbqffrvsvkoz.supabase.co` | déjà existant si staging utilise le même projet |
| `SUPABASE_ANON_KEY` | clé anon | Dashboard Supabase → Settings → API |
| `FIREBASE_SERVICE_ACCOUNT` | JSON service account | Console Firebase → Project Settings → Service accounts (générer pour `easy-rent-54cd4`) |
| `FIREBASE_PROJECT_ID` | `easy-rent-54cd4` | Console Firebase |
| `SUPABASE_PROJECT_REF` | `tbgttutodbqffrvsvkoz` | Dashboard Supabase |
| `SUPABASE_ACCESS_TOKEN` | `sbp_xxx...` | Dashboard Supabase → Account → Access Tokens (créer un nouveau token nommé "github-actions-prod") |
| `SUPABASE_DB_PASSWORD` | mot de passe DB | Dashboard Supabase → Settings → Database (à recopier ou reset) |
| `RESEND_API_KEY` | `re_xxx...` (prod) | Dashboard Resend, créer une API key dédiée prod |
| `RESEND_FROM_EMAIL` | `EasyRent <noreply@easyrent.fr>` | Dépend du domaine vérifié sur Resend |

**Note Resend** : les secrets Resend sont consommés par les Edge Functions Supabase, pas par GitHub Actions. À provisionner via `supabase secrets set` sur le projet prod, séparément. Le workflow `migrate-prod.yml` n'a PAS besoin de ces secrets.

### 6.5 Refonte page `/privacy`

**Fichier** : `lib/features/privacy/presentation/privacy_page.dart` (existant, contenu placeholder partiel)

**Sections à compléter** :

1. **Identité du responsable de traitement** : à remplir par le bailleur (rappel : EasyRent est un outil B2B, chaque bailleur est responsable de ses données et donc DPO de fait). Mention "Le compte EasyRent est sous la responsabilité du titulaire du compte (bailleur). Pour toute question relative à vos données personnelles, contactez le bailleur titulaire du compte."
2. **Données collectées** (par catégorie) :
   - Compte bailleur : email (auth), `full_name`, `phone`, `address`
   - Locataires : `first_name`, `last_name`, `email`, `phone`
   - Baux : montant loyer/charges, dates, statut, propriété/locataire associés
   - Paiements : montant, date, méthode, notes
   - Quittances : PDF générés (rétention légale 5 ans)
   - Documents : fichiers uploadés (bails signés, états des lieux, etc.) — métadonnées (nom du fichier potentiellement PII)
3. **Base légale** (RGPD art. 6.1.b) : exécution du contrat de bail
4. **Sous-traitants** :
   - **Supabase** (Supabase Inc., USA — instances de données EU/Francfort) : hébergement DB, Auth, Storage. Sous-traitant principal. DPA disponible sur leur site.
   - **Resend** (Resend, Inc., USA) : envoi des emails transactionnels (quittances). DPA signée.
   - **Firebase Hosting** (Google LLC, USA) : hébergement statique des assets. Pas de stockage de données personnelles côté Firebase (l'app communique directement avec Supabase pour les data).
5. **Durée de conservation** :
   - 5 ans pour `bail_signe`, `etat_des_lieux`, quittances (loi 6 juillet 1989, mécanisme `legal_hold` empêche la suppression)
   - Suppression sur demande pour le reste, via contact du bailleur
6. **Droits** (RGPD art. 15-21) : accès, rectification, effacement, opposition, portabilité, limitation. À exercer auprès du bailleur titulaire du compte.
7. **Sécurité** : RLS Postgres, URLs Storage signées 5 min, communication HTTPS, magic link PKCE.
8. **Cookies** : aucun cookie tiers de tracking. Cookies fonctionnels uniquement (auth session, theme preference). À confirmer pendant le coding qu'aucun analytics n'est branché.
9. **Mise à jour** : version + date de dernière mise à jour

**Wording** : ton clair, FR, accessible. Inspiration : politique de confidentialité OVH / Indy / Pennylane.

**Accessibilité** : page accessible sans login (déjà OK via `app_router.dart` — route `/privacy` whitelistée). Lien depuis :
- Footer login (déjà existant)
- Page `/profile` (à ajouter en bas, lien discret "Politique de confidentialité")

### 6.6 Documentation runbook

**Nouveau fichier** : `docs/RUNBOOK_PROD_DEPLOY.md`

Sections :

1. **Pré-requis** : checklist secrets GitHub (cf. §6.4) + Auth URL Supabase + domaine Resend vérifié
2. **Procédure de 1er déploiement prod** (sequence) :
   - a. Configurer Supabase Auth URL : Dashboard → Authentication → URL Configuration → Site URL = `https://easy-rent-54cd4.web.app`, Redirect Allow-List = `https://easy-rent-54cd4.web.app/**`
   - b. Provisionner les Edge Function secrets prod : `supabase secrets set RESEND_API_KEY=... RESEND_FROM_EMAIL=...`
   - c. Déployer les Edge Functions sur prod : `supabase functions deploy generate-receipt && supabase functions deploy send-receipt`
   - d. Lancer `migrate-prod.yml` (workflow_dispatch, confirmation=yes) → applique toutes les migrations sur `public`
   - e. Merge `develop` → `main` → trigger `deploy.yml` job prod → build + deploy Firebase
   - f. Smoke test (cf. §6.7)
3. **Procédure de re-déploiement régulier** : push sur `main` → `deploy.yml` rebuild + deploy. Migrations à part via `migrate-prod.yml` quand nécessaire.
4. **Rollback Hosting** :
   - Option 1 (rapide) : `firebase hosting:clone easy-rent-54cd4:live easy-rent-54cd4:live --version-id=<previous-version-id>` (récupéré via `firebase hosting:versions:list`)
   - Option 2 : redéploiement d'un commit antérieur via `workflow_dispatch` sur `deploy.yml` (input `target=prod`, branche à choisir)
5. **Rollback migrations** :
   - **Pas de rollback automatique**. Si une migration casse prod : créer une nouvelle migration de correction (`fix_xxx.sql`), tester en dev, puis re-lancer `migrate-prod.yml`.
   - Ne JAMAIS exécuter `DROP TABLE` ou `DELETE FROM` en migration (rétention légale 5 ans).
6. **Monitoring manuel** : pendant les premières 48h, vérifier 2x/jour : Supabase logs (auth + Edge Functions errors), Resend dashboard (email failures), Firebase Hosting logs.

### 6.7 Smoke test post-deploy (checklist)

**Nouveau fichier** : `docs/DEPLOY_CHECKLIST.md` (ou intégré au runbook)

Checklist manuelle (15 étapes, ~30 min à exécuter une fois) :

- [ ] Ouvrir `https://easy-rent-54cd4.web.app` — la page de login s'affiche
- [ ] Cliquer "Politique de confidentialité" en bas → la page `/privacy` complète s'affiche (sans login)
- [ ] Demander un magic link avec un email réel → email reçu en moins de 30s
- [ ] Cliquer le lien → redirect vers dashboard, session active
- [ ] Dashboard affiche l'onboarding "Premiers pas" (3 étapes)
- [ ] Cliquer étape 1 → page `/properties/new` → créer un bien
- [ ] Cliquer étape 2 → page `/tenants/new` → créer un locataire
- [ ] Cliquer étape 3 → page `/leases/new` → créer un bail
- [ ] Retour dashboard → 4 KPI affichés (loyers ~0€ encaissé, retards 0, renouvellements 0 ou 1 selon end_date, docs 0)
- [ ] Naviguer vers le bail créé → enregistrer un paiement
- [ ] Sur la page receipts → générer une quittance PDF → preview OK
- [ ] Cliquer "Envoyer par email" → email reçu chez le locataire (vérifier dossier spam)
- [ ] Uploader un document PDF de test (catégorie "autre")
- [ ] Retour dashboard → activité récente affiche les 3 actions, KPI mis à jour
- [ ] PWA install prompt visible (Chrome desktop) → cliquer "Installer" → app installée
- [ ] Couper le réseau → l'app shell reste accessible (SW offline-first)

### 6.8 Décisions techniques

| Sujet | Décision | Justification |
|---|---|---|
| Migrations prod | `workflow_dispatch` avec confirmation `yes` | D5 — évite migration silencieuse sur push main, contrôle explicite |
| Dart-defines prod | Injecté via secrets GitHub dans `deploy.yml` (pas de fichier check-in) | Sécurité — `dart-defines.prod.json` est git-ignored, template `*.example.json` versionné |
| Resend prod | Provisionné séparément via `supabase secrets set` | Edge Functions consomment les secrets côté Supabase, pas côté GitHub |
| Service Worker prod | `offline-first` (default Flutter) | Cohérent attente PWA, cache stale géré par Flutter (hash filenames) |
| Install prompt | JS interop via `package:web` (pas `dart:html` qui est legacy) | Pattern moderne, supporte sound nullability + WASM-ready |
| Persist dismiss | `SharedPreferences` (clé `pwa_install_prompt_dismissed_at` timestamp) | Léger, cross-browser-storage natif Web (localStorage backed) |
| Re-trigger after dismiss | 30 jours | Évite spam ; cohérent UX bannières install Twitter/LinkedIn |
| Charts | `fl_chart` ^0.69 | Standard Flutter, pure-Dart, supporte BarChart natif. Pas de dépendance JS |
| Onboarding state | Calculé dynamiquement (count(properties)+count(tenants)+count(leases)=0) | Pas de table dédiée — disparaît automatiquement dès qu'une entité existe |
| KPI fan-in | `Future.wait` de 6 requêtes parallèles | Latence cumulée minimisée. P1 : RPC unique `get_dashboard_snapshot()` si > 200ms |
| Retards (KPI) | Heuristique 35j sans paiement | Simplification MVP. P1 : analyse stricte mois calendaire |
| Docs pending (KPI) | Proxy `category='autre'` | Simplification MVP. P1 : workflow d'attente explicite (status) |
| Privacy page | Sections RGPD complètes en FR | Bloquant go-live (AC story) — accessible sans login |
| Rollback migrations | Aucun rollback — créer migration de correction | Conformité légale (DROP TABLE interdit en rétention 5 ans) |

---

## 7. Helpers nouveaux ou réutilisés

| Helper | Statut | Path |
|---|---|---|
| `Db.from`, `Db.rpc` | Réutilisés | `lib/core/db.dart` |
| `FrenchDate.format` | Réutilisé | `lib/core/utils/french_date.dart` |
| `MoneyFormat` (centimes → "1 234,56 €") | Réutilisé | `lib/core/utils/money_format.dart` (déjà existant pour payments) |
| `formatCompactEuros(int cents) → "1,2k €"` | **Nouveau** | `lib/core/utils/money_format.dart` (extension) — utilisé par MonthlyBarchart axe Y |
| `firstNameOrEmail(Landlord)` | **Nouveau** | `lib/core/utils/landlord_x.dart` — pour DashboardHeader "Bonjour <prénom>" |
| `Logger _log = Logger('Dashboard')` | Réutilisé | `logging` package déjà en deps |

---

## 8. ⚠️ Questions à valider avant codage

1. **Cardinalité "retards"** : la requête MVP utilise `paid_at >= now() - interval '35 days'`. Si un locataire paie en avance le 25 du mois précédent pour le mois courant, il sera correctement marqué non-retard. En revanche, si un bail démarre le 15 du mois courant, on le marquera "en retard" alors qu'il n'est pas encore dû. **Mitigation MVP** : exclure les baux dont `start_date > now() - interval '35 days'`. À valider avec le PO — sinon faux positifs au démarrage d'un nouveau bail.
2. **KPI "documents en attente"** : la story propose `category='autre' AND deleted_at IS NULL` comme proxy. C'est un proxy faible (un bailleur peut volontairement choisir "autre" pour un fichier déjà classé). **Alternative** : afficher simplement "Documents totaux" sans notion de pending. Décision recommandée : MVP avec proxy `category='autre'`, doc explicite que le calcul changera en P1.
3. **Frequency re-éligibilité install prompt** : 30 jours après dismiss. **À valider** — 30j cohérent avec patterns Twitter/LinkedIn, mais arbitraire. Alternative : pas de re-éligibilité automatique (dismiss = définitif jusqu'au logout). Recommandation : 30 jours, configurable.
4. **Icônes PWA — design ER vs autre placeholder** : "ER" texte blanc sur teal `#0F766E`. **Confirmer** : OK avec le bailleur cible (lisibilité), ou préférer un pictogramme (maison, clé...) ? Recommandation : "ER" texte est neutre et reconnaissable, à itérer en P1 avec un vrai design.
5. **Resend domaine** : le go-live effectif dépend de la vérification d'un domaine email (DNS records). **Bloquant pour l'envoi de quittances** — l'app fonctionne sans, mais la feature "envoi email" échouera. À planifier en parallèle du dev. Le runbook documente clairement que cette étape doit être faite avant le smoke test étape 12 ("envoi email").
6. **`background_color` manifest** : actuellement `#1E293B` (slate dark). Le plan propose `#0F766E` (teal, cohérent splash). **Confirmer** : cohérence UX > cohérence avec dark mode background. Recommandation : teal.
7. **Pull-to-refresh dashboard** : le plan propose `RefreshIndicator` + invalidation manuelle. **Alternative** : auto-refresh sur retour vers `/` via `GoRouterObserver`. Recommandation MVP : `RefreshIndicator` simple ; P1 si pénible.
8. **Activity récente — limit** : 5 entrées au MVP. Suffisant pour un cockpit. P1 : pagination ou page dédiée `/activity`.

Aucune de ces questions n'est bloquante pour démarrer le dev — elles seront résolues au codage avec des défauts raisonnés. Flag PO pour Q1 (faux positifs retards) et Q5 (domaine Resend) qui peuvent impacter UX/go-live.

---

## 9. Plan de tests

### 9.1 Tests SQL

**Aucun nouveau test SQL** — pas de nouvelle table / RPC / policy. Les requêtes du dashboard utilisent les policies RLS existantes (testées dans `rls_*.sql` des features précédentes).

### 9.2 Tests Flutter

| Fichier | Type | Couverture |
|---|---|---|
| `test/unit/dashboard_kpi_test.dart` | unit | freezed equality, sealed union, helpers de format |
| `test/unit/dashboard_snapshot_test.dart` | unit | `empty(isOnboarding)` factory + equality |
| `test/unit/activity_item_test.dart` | unit | mapping payment/receipt/document → ActivityItem |
| `test/unit/monthly_amount_test.dart` | unit | parsing date YYYY-MM + serialization |
| `test/unit/dashboard_repository_test.dart` | unit | mock Supabase client : 4 KPI méthodes + 6 mois + activité + onboarding (zéros) |
| `test/unit/dashboard_provider_test.dart` | unit | fan-in `Future.wait`, skip si `isOnboarding`, AsyncError mappé |
| `test/unit/install_prompt_storage_test.dart` | unit | SharedPreferences mock — read/write timestamp |
| `test/unit/install_prompt_controller_test.dart` | unit | 1er login → visible, dismiss → hidden 30j, isStandalone → hidden |
| `test/widget/kpi_card_test.dart` | widget | rendu icon + value + label, semanticColor appliqué, child slot rendu |
| `test/widget/kpi_grid_test.dart` | widget | layout 4 colonnes >900px, 1 colonne <600px (LayoutBuilder) |
| `test/widget/monthly_barchart_test.dart` | widget | golden test 6 mois données fixes + cas tous-zéros |
| `test/widget/recent_activity_section_test.dart` | widget | empty state si liste vide, 5 tiles si données, tap navigation |
| `test/widget/onboarding_first_steps_test.dart` | widget | 3 steps cliquables, navigation correcte |
| `test/widget/dashboard_page_test.dart` | widget | loading skeleton, error retry, data normale, data onboarding |
| `test/widget/install_prompt_banner_test.dart` | widget | visible/hidden selon state, tap installer → trigger, tap close → dismiss, variante iOS |
| `test/widget/privacy_page_test.dart` | widget | sections complètes, accessible sans login |

**Couverture** : ~16 fichiers tests, ~80 tests unitaires/widgets.

### 9.3 Test manuel obligatoire post-deploy

Cf. §6.7 checklist 15 étapes.

### 9.4 Test infra (workflow migrate-prod.yml)

- Lancer le workflow en `dry_run=true` une première fois → vérifier que la sortie liste les migrations correctement
- Lancer en `dry_run=false`, `confirmation=yes` → vérifier que `supabase db push` réussit sur `public`
- Lancer avec `confirmation=no` → vérifier que le job est skippé (`if: false`)

---

## 10. Step-by-step execution order

Suggéré pour la branche `feature/dashboard-pwa-prod-setup` — possibilité de split en 3 PR si découpage souhaité (FEAT-010A/B/C).

1. **Section C en premier (bloque go-live)** :
   - Créer `migrate-prod.yml`
   - Créer `dart-defines.prod.json.example`
   - Refonte `privacy_page.dart` (RGPD complet)
   - Documenter `RUNBOOK_PROD_DEPLOY.md` + `DEPLOY_CHECKLIST.md`
   - Provisionner secrets GitHub manuellement (action humaine, à mentionner en review)
2. **Section B en parallèle** :
   - Audit + corriger `manifest.json`
   - Générer icônes placeholder ER (script + commit)
   - Ajuster `index.html` (CSS body bg teal)
   - Implémenter module `lib/features/pwa/` (storage + bridge JS + controller + banner)
   - Tests unit/widget PWA
3. **Section A en parallèle** :
   - `pubspec.yaml` : ajouter `fl_chart`, `shared_preferences`, `web`
   - Implémenter module `lib/features/dashboard/` (domain → data → application → presentation)
   - Tests unit/widget dashboard
   - Intégrer `InstallPromptBanner` dans `DashboardPage`
4. **Polish et review** :
   - `flutter analyze` clean
   - `dart format .`
   - `flutter test`
   - PR review : `code-reviewer` + `security-auditor`
5. **Merge + déploiement** :
   - Merge feature → develop → tests staging
   - Lancer `migrate-prod.yml` (dry-run puis apply)
   - Merge develop → main → trigger `deploy.yml` prod
   - Smoke test `DEPLOY_CHECKLIST.md`

---

## 11. Risques

| Risque | Impact | Mitigation |
|---|---|---|
| 1er deploy prod révèle des secrets/config manquants (Supabase Auth URL, Edge Functions non déployées, Resend domaine non vérifié) | Haut | Runbook §6.6 exhaustif. Étapes a-c à valider AVANT le `deploy.yml` prod. Buffer 0,5j prévu story. |
| Cache stale Service Worker offline-first : utilisateurs reçoivent l'ancien bundle pendant des heures | Moyen | Vérifier `Cache-Control: no-cache` sur `index.html` + `flutter_service_worker.js` dans `firebase.json`. Tester avec un build incrémental après go-live. |
| Install prompt JS interop ne capture pas `beforeinstallprompt` à temps (race avec Flutter bootstrap) | Moyen | `captureDeferred()` appelé tout en haut de `main.dart`, avant `runApp`. Si race persistante : ajouter listener inline dans `index.html` qui stash dans `window.__pwaDeferredPrompt` + récupérer côté Dart après load. |
| `fl_chart` est lourd au bundle (+100KB) | Faible | Acceptable — c'est l'unique dépendance "graphique" du MVP. Tree-shaking Flutter Web minimise l'impact. |
| `SharedPreferences` ne persiste pas en navigation privée Chrome | Faible | Comportement attendu. L'install prompt réapparaîtra à chaque session privée — non-bloquant. |
| Heuristique "retards 35j" produit faux positifs sur baux fraîchement démarrés | Moyen | Exclure `start_date > now() - 35j` dans la requête (cf. §8 Q1). |
| Migration prod auto-déclenchée par accident sur push main | Haut | Désactivation du job `apply-supabase-migrations` dans `deploy.yml` (§6.2 décision 3). Migration uniquement via `migrate-prod.yml` workflow_dispatch. |
| Page `/privacy` incomplète au go-live → non-conformité RGPD | Haut | Page bloquante (AC story). Review juridique recommandée avant merge (à flagger PO). |
| Secrets GitHub `production` env non protected (pas de reviewer required) | Moyen | À configurer dans Settings → Environments → production → required reviewers. Documenté dans runbook. |
| Resend prod domaine non vérifié à temps | Moyen | Send-receipt échoue mais le reste de l'app fonctionne. Doc dans runbook §6.6 que c'est un blocker email-only, pas app-wide. |

---

## 12. Récap

**Sections principales** :
- **A. Dashboard refonte** : module Flutter `lib/features/dashboard/` (~20 fichiers Dart + tests), 4 KPI cards, mini-barchart 6 mois (`fl_chart`), activité récente, raccourcis, onboarding "Premiers pas". Aucune mutation SQL — fan-in `Future.wait` de 6 requêtes RLS.
- **B. Polish PWA** : module `lib/features/pwa/` (4 fichiers), icônes placeholder "ER" (4 PNG via ImageMagick script), audit `manifest.json` (`background_color` + `start_url`), splash CSS, install prompt JS interop via `package:web`, persist dismiss via `SharedPreferences` (30j re-éligibilité).
- **C. Setup prod** : nouveau `migrate-prod.yml` (workflow_dispatch + confirmation), refonte `privacy_page.dart` RGPD complète, `dart-defines.prod.json.example`, désactivation migration auto dans `deploy.yml`, runbook `RUNBOOK_PROD_DEPLOY.md` + `DEPLOY_CHECKLIST.md` (15 étapes smoke test).

**Nouveaux fichiers estimés** :
- Dashboard : 8 domain + 1 repo + 1 provider + 9 widgets ≈ **19 fichiers Dart**
- PWA : 4 fichiers Dart + 4 PNG + 1 script bash ≈ **9 fichiers**
- Prod setup : 1 workflow + 1 template JSON + 2 docs MD + 1 refonte privacy ≈ **5 fichiers**
- Tests : ~16 fichiers tests Dart

**Dépendances Flutter ajoutées** : `fl_chart ^0.69.0`, `shared_preferences ^2.3.5`, `web ^1.1.0`.

**Effort total estimé** : **4,5 jours** (cohérent story §Estimated effort), décomposé : A=2j, B=0,5j, C=1,5j + 0,5j buffer go-live.

**Critique à surfacer PO** :
- Q1 §8 (retards faux positifs au démarrage de bail)
- Q5 §8 (domaine Resend bloque l'envoi email post-deploy)
- Risque "Page /privacy review juridique" (§11)
- Action humaine requise : provisionner les 9 secrets GitHub env `production` (§6.4) avant le 1er deploy
