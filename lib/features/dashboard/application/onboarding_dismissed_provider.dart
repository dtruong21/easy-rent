import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persiste le fait que le bailleur a « passé » la checklist d'onboarding
/// (préférence LOCALE au navigateur/appareil — pas de synchro serveur).
class OnboardingDismissedStorage {
  static const _key = 'onboarding_dismissed';

  Future<bool> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  Future<void> write(bool dismissed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, dismissed);
  }
}

final onboardingDismissedStorageProvider = Provider<OnboardingDismissedStorage>(
  (ref) => OnboardingDismissedStorage(),
);

/// `true` si le bailleur a masqué la checklist. Démarre `false`, charge la
/// valeur stockée (même compromis que `ChartPeriodNotifier`).
class OnboardingDismissedNotifier extends StateNotifier<bool> {
  OnboardingDismissedNotifier(this._storage) : super(false) {
    _load();
  }

  final OnboardingDismissedStorage _storage;

  Future<void> _load() async {
    final stored = await _storage.read();
    if (stored && mounted) state = true;
  }

  Future<void> dismiss() async {
    state = true;
    await _storage.write(true);
  }
}

final onboardingDismissedProvider =
    StateNotifierProvider<OnboardingDismissedNotifier, bool>(
      (ref) => OnboardingDismissedNotifier(
        ref.read(onboardingDismissedStorageProvider),
      ),
    );
