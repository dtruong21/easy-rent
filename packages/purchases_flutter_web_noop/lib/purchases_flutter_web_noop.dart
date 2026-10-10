import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// Remplace l'implémentation web intégrée de `purchases_flutter` (FEAT-044e).
///
/// Celle-ci, enregistrée au démarrage de TOUTE page web, injecte un `<script>`
/// chargeant le SDK web RevenueCat (~1 Mo) — or le web paie par Stripe et
/// n'appelle jamais RevenueCat. Dépendance directe de l'app qui `implements:
/// purchases_flutter` : l'outil Flutter la préfère à l'implémentation intégrée
/// pour le web ; Android et iOS gardent le vrai plugin.
class PurchasesFlutterWebNoop {
  static void registerWith(Registrar registrar) {}
}
