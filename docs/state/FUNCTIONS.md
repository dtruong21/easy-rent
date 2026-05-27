# Edge Functions — snapshot

> Maintenu par `state-keeper`. **Source** : `supabase/functions/`. **Dernière sync** : 2026-05-27

## Fonctions déployées

_(aucune fonction créée — `supabase/functions/` n'existe pas encore)_

## Fonctions planifiées

| Nom | Trigger | Auth | Secrets | Priorité |
|---|---|---|---|---|
| `send-receipt` | Manual (on receipt create) | JWT required | `RESEND_API_KEY` | P0 |
| `generate-receipt` | Manual (on payment record) | JWT required | — | P0 |

## Structure

À créer avec :
- Deno runtime
- `import_map.json` pour dépendances (à utiliser pour Supabase Functions v2+)
- Error handling + logging via `Db.invokeFunction()`

## Notes

- Appellées via `Db.invokeFunction()` wrapper (voir `lib/core/db.dart`)
- Passage automatique du `schema` (public ou dev) en paramètre
- Scheduled functions (cron) : TBD (ex: rappel paiement loyers)
