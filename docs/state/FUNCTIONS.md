# Edge Functions — snapshot

> Maintenu par `state-keeper`. **Source** : `supabase/functions/`. **Dernière sync** : 2026-05-28

## Fonctions Edge déployées

_(aucune fonction créée — `supabase/functions/` n'existe pas)_

## Fonctions planifiées

| Nom | Trigger | Auth | Secrets | Priorité | Feat |
|---|---|---|---|---|---|
| `send-receipt` | Manual (on receipt create) | JWT required | `RESEND_API_KEY` | P0 | FEAT-007 |
| `generate-receipt` | Manual (on payment record) | JWT required | — | P0 | FEAT-006 |

## Structure

À créer avec :
- Deno runtime (TypeScript)
- `import_map.json` ou `deno.json` pour dépendances (Supabase Functions v2+)
- Error handling + logging via `Db.invokeFunction()` wrapper

### Appel côté client

Via `lib/core/db.dart` :

```dart
final result = await supabase.functions.invoke(
  'send-receipt',
  body: {'receipt_id': '...', 'schema': 'public'},
);
```

Passage automatique du `schema` (public ou dev) en paramètre.

## Postgres helpers (côté backend)

_(aucune fonction créée — seront ajoutées avec les features)_

Prévues pour FEAT-006+ :
- `public.generate_receipt_pdf()` : Render PDF template Quittance (colonnes baux, locataires, paiements)
- `public.send_receipt_email()` : Wrapper Resend API

## Cron & Scheduled functions

_(à planifier)_

Exemples pour FEAT-008+ :
- Rappel paiement loyers (10e du mois)
- Nettoyage documents archived (conservation légale 5 ans)
- Synthèse mensuelle propriétaire

## Notes

- Appellées via `Db.invokeFunction()` wrapper (voir `lib/core/db.dart`)
- Passage automatique du `schema` en paramètre pour isolation dev/prod
- Logging centralisé via Supabase Logs (accessible via web UI)
- Erreurs gérées avec status codes HTTP standard (200, 400, 401, 500, etc.)
