import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Date de la dernière sollicitation d'avis sur cet appareil (FEAT-060),
/// en ISO-8601. Locale à l'appareil, comme le mode d'affichage des cartes.
class ReviewSolicitationStorage {
  static const _key = 'review_solicited_at';

  Future<DateTime?> readLastSolicitedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> markSolicited(DateTime at) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, at.toIso8601String());
  }
}

final reviewSolicitationStorageProvider = Provider<ReviewSolicitationStorage>(
  (_) => ReviewSolicitationStorage(),
);
