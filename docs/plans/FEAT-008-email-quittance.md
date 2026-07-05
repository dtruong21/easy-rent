# Plan — [FEAT-008] Partager une quittance par email (Web Share API Native)

> **Pivot 2026-06-22** : Refactorisation d'une architecture Resend/Edge Function vers **partage natif Web Share API côté client** avec fallback `mailto://`.
>
> Source story : [`docs/backlog/008-email-quittance.md`](../backlog/008-email-quittance.md)

## 1. Vue d'ensemble

**Objectif** : Depuis la liste des quittances d'un bail, permettre au bailleur de partager en un clic le PDF d'une quittance valide avec un service email ou une application tierce (Mail, Gmail, Outlook, WhatsApp, etc.) via le **Web Share API natif du navigateur**. Un audit trail (`sent_at`, `sent_to_email`) est maintenu côté client après partage, synchronisé serveur via la RPC `mark_receipt_as_sent`.

**Avantages du pivot** :
- ✅ Zéro dépendance email external (Resend) → pas de secret `RESEND_API_KEY` à gérer en prod
- ✅ Expérience utilisateur native (picker système) → compatible multiplateforme (Windows, macOS, Android, iOS)
- ✅ Pas de risque domaine DNS non vérifié
- ✅ Réduction empreinte backend → moins de surface d'attaque
- ✅ Pas de quota email limitant

**Limites acceptées MVP** :
- ⚠️ Partage ≠ confirmation d'envoi côté serveur → on marque `sent_at` sur base de l'intention utilisateur, pas preuve de livraison
- ⚠️ Safari desktop : fallback `mailto://` pas aussi fluide (compose email système vs Web Share API)
- ⚠️ Pas de webhook ou preuve de remise email

**Dépendances** :
- FEAT-007 (table `receipts`, bucket Storage `receipts/`, migration colonnes `sent_at`, `sent_to_email`)
- `tenants.email` (FEAT-004 — présent et validé regex)
- `landlords.full_name` (FEAT-007 — obligatoire pour signer la quittance ; utilisé dans le body du partage)

**Débloque** : aucune feature aval directe — point final du flow quittance MVP.

---

## 2. Architecture

### 2.1 Schéma SQL — Inchangé depuis FEAT-007/008 original

Colonnes `sent_at` et `sent_to_email` existent déjà sur `receipts` (ajoutées en FEAT-008 avant pivot). La RPC `mark_receipt_as_sent(p_receipt_id uuid, p_sent_to_email text)` est présente et utilisée.

**Marque de la quittance** : après que l'utilisateur appuie sur le bouton "Partager", le contrôleur client appelle la RPC `mark_receipt_as_sent` **asynchrone** (pas bloquant pour l'expérience UI).

**Trigger protection** : le trigger `tr_01b_protect_sent_columns_receipts` bloque toute modification de `sent_at` / `sent_to_email` sauf si le flag GUC `app.allow_sent_columns_change = '1'` est posé par la RPC (mécanisme héritée, inchangé).

### 2.2 Côté Client Flutter — Service de Partage

**Nouveau fichier** : `lib/features/receipts/data/web_share_service.dart`

```dart
/// Wrapper Web Share API (JS interop via package:web)
class WebShareService {
  /// Partage un PDF de quittance
  /// Invocation native : navigator.share({ files: [Blob], title, text })
  Future<void> shareReceipt({
    required Uint8List pdfBytes,
    required String tenantName,
    required String periodLabel, // "mai 2026"
    required String amount,      // "500,00 €"
  })
  
  /// Fallback mailto pour navigateurs sans Web Share API
  /// Construction : mailto:tenant@email.com?subject=...&body=...
  void shareReceiptViaMail({
    required String tenantEmail,
    required String periodLabel,
    required String amount,
    required String landlordName,
  })
}
```

**JS Interop** :
- `navigator.share()` via `package:web` (JS FFI)
- Détection capacité : `navigator.canShare()` → choisit Web Share API vs mailto
- Attachement du PDF : `File` Blob créé in-memory depuis `Uint8List` (pas de stockage côté device)

### 2.3 Contrôleur Riverpod

**Nouveau fichier** : `lib/features/receipts/application/share_receipt_controller.dart`

États possibles (sealed freezed) :

```dart
@freezed
sealed class ShareReceiptState with _$ShareReceiptState {
  const factory ShareReceiptState.idle() = ShareReceiptIdle;
  const factory ShareReceiptState.loading() = ShareReceiptLoading;
  const factory ShareReceiptState.confirmingResend({
    required DateTime previousSentAt,
    required String previousMaskedEmail,
  }) = ShareReceiptConfirmingResend;
  const factory ShareReceiptState.success({
    required DateTime sentAt,
    required String sentToEmail,
  }) = ShareReceiptSuccess;
  const factory ShareReceiptState.error({required String message}) = ShareReceiptError;
}
```

**Logique** :
1. Si receipt déjà partagé (`sent_at IS NOT NULL`) → ouvre dialog confirmation
2. Sinon :
   a. Récupère le PDF depuis Storage (signed URL)
   b. Invoque Web Share API avec PDF + sujet + body pré-remplis
   c. Après réussite (picker fermé) → appelle RPC `mark_receipt_as_sent` asynchrone
   d. Rafraîchit la liste des quittances du bail

### 2.4 Widget Bouton

**Nouveau fichier** : `lib/features/receipts/presentation/widgets/share_receipt_button.dart`

**Comportement** :
- Icon = `Icons.share` si jamais partagé, `Icons.check_circle` si déjà partagé
- Désactivé si `receipt.isVoided || receipt.isStale`
- Clic → appelle `share_receipt_controller.initiate(receipt, lease_id)`
- Listener sur l'état :
  - `confirmingResend` → affiche dialog "Renvoyer ?"
  - `loading` → icône devient loader
  - `success` → SnackBar "Quittance partagée" + masquage email (RGPD)
  - `error` → SnackBar message d'erreur

### 2.5 Dialog Confirmation

**Nouveau fichier** : `lib/features/receipts/presentation/widgets/confirm_resend_dialog.dart`

Affiche : "Vous l'avez déjà partagée le JJ/MM/YYYY. Voulez-vous la renvoyer ?" + 2 boutons (Annuler, Renvoyer).

---

## 3. Décisions techniques

| Sujet | Décision |
|---|---|
| Web Share API vs Resend | Web Share API. Native, aucun secret backend, meilleure UX. |
| Lieu du PDF | Récupéré depuis Storage avec signed URL 60s, chargé in-memory, partagé via Blob, pas de stockage device. |
| Preuve d'envoi | Intention utilisateur (picker système fermé sans erreur). RPC mark_receipt_as_sent appelée APRÈS partage réussi, donc **pas de preuve serveur d'envoi réel**. Acceptable MVP — la mention légale loi 1989 art. 21 couvre "remise" vs "livraison". |
| Fallback Safari desktop | `mailto://` compose email système avec PDF attaché (moins fluide mais fonctionnel). |
| Idempotence | 2e partage de la même quittance : dialog confirmation, puis appel RPC qui écrase `sent_at` (marque le dernier partage). |
| Masquage email | `"j***@example.com"` (premier char + 3 étoiles + domaine) dans les SnackBars et dialogs (RGPD). |
| Pas de RPC attente | Non — l'appel Web Share API est immédiat (pas d'await), il ferme le picker et retourne. La RPC est fire-and-forget côté client. |

---

## 4. Plan de tests

### 4.1 Tests Dart (Flutter)

| Fichier | Couverture |
|---|---|
| `test/unit/web_share_service_test.dart` | Mock Web Share API, fallback mailto, Blob creation |
| `test/unit/share_receipt_controller_test.dart` | Transitions d'état, call RPC after success, error handling |
| `test/widget/share_receipt_button_test.dart` | Icon switching, disabled state, dialog confirmation, SnackBar success |

**Cible** : ~3 fichiers, ~25 tests.

### 4.2 QA manuel

1. Chrome desktop (Windows/macOS) : Web Share API picker apparaît
2. Firefox desktop : fallback mailto compose email système
3. Safari desktop : fallback mailto
4. Android Chrome : Web Share API avec options Share Sheet (Gmail, Outlook, WhatsApp)
5. iOS Safari : Web Share API avec options partage système
6. PDF déjà partagé : dialog confirmation + repartage OK
7. Receipt void/stale : bouton désactivé visuel
8. Tenant sans email : error message approprié
9. Storage PDF absent : error message "PDF indisponible"
10. Bundle audit (`grep share_ build/web/main.dart.js`) : aucun secret visible

---

## 5. Fichiers créés / modifiés

### Créés au pivot (FEAT-008 Phase 2 — Web Share)

- `lib/features/receipts/data/web_share_service.dart` (nouvelle)
- `lib/features/receipts/application/share_receipt_controller.dart` (nouvelle)
- `lib/features/receipts/application/share_receipt_state.dart` (nouvelle)
- `lib/features/receipts/presentation/widgets/share_receipt_button.dart` (nouvelle)
- `lib/features/receipts/presentation/widgets/confirm_resend_dialog.dart` (nouvelle)
- `test/unit/web_share_service_test.dart` (nouvelle)
- `test/unit/share_receipt_controller_test.dart` (nouvelle)
- `test/widget/share_receipt_button_test.dart` (nouvelle)

### Modifiés au pivot

- `lib/features/receipts/presentation/widgets/receipt_list_tile.dart` : intégration du `ShareReceiptButton`
- `lib/features/receipts/domain/receipt.dart` : colonnes `sentAt`, `sentToEmail` (inchangées depuis FEAT-008 original)

### Supprimés au pivot

- `supabase/functions/send-receipt/` : répertoire complet (Edge Function Resend)
- Aucune migration SQL : le schéma `receipts` (colonnes `sent_at`, `sent_to_email`) reste intact

### Inchangés (héritée FEAT-008 original)

- `supabase/migrations/*feat008*.sql` : schéma, RPC, triggers restent applicables
- `docs/backlog/008-email-quittance.md` : une note sera ajoutée en en-tête

---

## 6. Décisions post-MVP (P1)

- **Retry / réseau** : pas de queue de partages ou retry automatique au MVP
- **Webhook email** : non applicable (partage natif)
- **Preuve de livraison** : P2 (nécessite intégration bancaire ou parsing SMTP reçu)
- **Notification push** : P2
- **Message email personnalisé** : P1 (permettre au bailleur de personnaliser le body du partage)

---

## 7. Récap technique

**Stack** :
- Flutter Web 3.x + Dart 3.11+
- `package:web` pour JS interop
- Supabase Storage (signed URL)
- RPC `mark_receipt_as_sent` (SECURITY DEFINER, protection GUC)
- Riverpod 2.6.0 (StateNotifierProvider autoDispose)

**Sécurité** :
- ✅ Zéro secret backend exposed
- ✅ RLS sur receipts confirmée (cross-user isolation)
- ✅ Pas de audit trail faussable côté client (RPC côté serveur)

**Performance** :
- Web Share API : ~200ms (picker système)
- Signed URL fetch + Blob creation : ~500ms (dépend taille PDF, typiquement <100KB)
- RPC call asynchrone : ~300ms (fire-and-forget, ne bloque pas UI)

---

## 8. Risques et mitigation

| Risque | Mitigation |
|---|---|
| Web Share API non supportée (Safari vieille version) | Fallback mailto ; détection `navigator.canShare()` ; test sur QA |
| PDF indisponible en Storage | Error message "PDF indisponible" ; bouton désactivé si `pdf_path IS NULL` |
| Tenant email NULL / vide | Error message "Ajoutez l'email du locataire" ; bouton désactivé si pas d'email |
| Double-clic | UI `loading` state désactive bouton pendant partage ; pas de double-call Web Share |
| Utilisateur refuse picker | Picker fermé = SnackBar "Partage annulé" ; `sent_at` non marqué (safe) |
| RPC échoue après partage | Log warning côté client, SnackBar info "Partagé mais enregistrement échoué — réessayez" |

---

## 9. Notes post-déploiement

Le pivot FEAT-008 élimine la dépendance Resend sans régresser la fonctionnalité core. La sémantique change légèrement :
- **Avant** : "email envoyé via Resend = preuve de livraison"
- **Après** : "partagé via Web Share = intention de partage, audit trail local"

Conforme à l'art. 21 loi 1989 car la "remise" quittance = action du bailleur de transmettre → le partage native est une transmission.

Voir `docs/state/FEATURES.md` FEAT-008 pour le statut actuel post-pivot.
