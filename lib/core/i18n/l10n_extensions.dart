import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';

/// Raccourci `context.l10n` pour `AppLocalizations.of(context)`.
///
/// `nullable-getter: false` (l10n.yaml) rend déjà [AppLocalizations.of]
/// non-nullable (throw explicite si les délégués ne sont pas enregistrés,
/// plutôt qu'un `null` silencieux) — aucun `!` nécessaire ici.
extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
