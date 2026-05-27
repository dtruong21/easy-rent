import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/env.dart';

/// Wrapper qui force toutes les requêtes Supabase à utiliser le schéma actif
/// (`public` en prod, `dev` en dev/staging).
///
/// Utilisation : `Db.from('landlords').select()` au lieu de
/// `Supabase.instance.client.from('landlords').select()`.
///
/// Voir docs/ENVIRONMENTS.md.
class Db {
  const Db._();

  static SupabaseClient get _client => Supabase.instance.client;

  /// Référence à une table du schéma actif.
  static SupabaseQueryBuilder from(String table) =>
      _client.schema(Env.supabaseSchema).from(table);

  /// Appelle une fonction RPC du schéma actif.
  static PostgrestFilterBuilder<dynamic> rpc(
    String fn, {
    Map<String, dynamic>? params,
  }) =>
      _client.schema(Env.supabaseSchema).rpc(fn, params: params);

  /// Storage avec préfixe d'env appliqué automatiquement.
  /// Exemple : `Db.storagePath('leases/foo.pdf')` → `prod/{uid}/leases/foo.pdf`.
  static String storagePath(String relativePath) {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Utilisateur non authentifié — storagePath nécessite une session');
    }
    return '${Env.storageEnvPrefix}/$userId/$relativePath';
  }

  /// Invoque une Edge Function en passant le schéma actif en argument.
  /// La fonction Deno doit accepter `schema` dans son body et l'utiliser.
  static Future<FunctionResponse> invokeFunction(
    String name, {
    Map<String, dynamic>? body,
  }) =>
      _client.functions.invoke(
        name,
        body: {
          ...?body,
          'schema': Env.supabaseSchema,
        },
      );
}
