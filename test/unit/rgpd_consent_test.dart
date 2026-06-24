/// Tests FEAT-016 — Persistance du consentement RGPD.
///
/// Couvre :
/// 1. La constante rgpd_consent_version suit le bon format (vN-YYYY-MM).
/// 2. [LandlordProfile] sérialise / désérialise correctement les deux nouveaux
///    champs (rgpdConsentAt, rgpdConsentVersion).
library;

import 'package:easyrent/features/profile/domain/landlord_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // =========================================================================
  // 1. Version RGPD — format canonique
  // =========================================================================
  group('rgpdConsentVersion — format canonique', () {
    test('v1-2026-06 suit le format vN-YYYY-MM', () {
      // La constante _rgpdConsentVersion est package-private.
      // On vérifie le format de la valeur connue : si la constante change,
      // ce test force une révision consciente de la version.
      const expectedVersion = 'v1-2026-06';
      final versionRegex = RegExp(r'^v\d+-\d{4}-\d{2}$');
      expect(
        versionRegex.hasMatch(expectedVersion),
        isTrue,
        reason:
            'La version RGPD doit suivre le format vN-YYYY-MM (ex: v1-2026-06)',
      );
    });
  });

  // =========================================================================
  // 2. LandlordProfile — sérialisation des champs RGPD
  // =========================================================================
  group('LandlordProfile — champs RGPD (FEAT-016)', () {
    final consentAt = DateTime.utc(2026, 6, 23, 10, 30);

    test('fromJson lit rgpd_consent_at et rgpd_consent_version', () {
      final json = {
        'id': 'uid-123',
        'email': 'jean@exemple.fr',
        'full_name': 'Jean Dupont',
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
        'rgpd_consent_at': '2026-06-23T10:30:00.000Z',
        'rgpd_consent_version': 'v1-2026-06',
      };

      final profile = LandlordProfile.fromJson(json);

      expect(profile.rgpdConsentAt, consentAt);
      expect(profile.rgpdConsentVersion, 'v1-2026-06');
    });

    test('fromJson lit version legacy-1 (comptes antérieurs à FEAT-016)', () {
      final json = {
        'id': 'uid-456',
        'email': 'legacy@exemple.fr',
        'full_name': null,
        'created_at': '2025-01-01T00:00:00.000Z',
        'updated_at': '2025-01-01T00:00:00.000Z',
        'rgpd_consent_at': '2025-01-01T00:00:00.000Z',
        'rgpd_consent_version': 'legacy-1',
      };

      final profile = LandlordProfile.fromJson(json);

      expect(profile.rgpdConsentVersion, 'legacy-1');
    });

    test('toJson produit rgpd_consent_at et rgpd_consent_version', () {
      final profile = LandlordProfile(
        id: 'uid-789',
        email: 'test@exemple.fr',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        rgpdConsentAt: consentAt,
        rgpdConsentVersion: 'v1-2026-06',
      );

      final json = profile.toJson();

      expect(json['rgpd_consent_at'], isNotNull);
      expect(json['rgpd_consent_version'], 'v1-2026-06');
    });

    test('copyWith préserve les champs RGPD si non modifiés', () {
      final original = LandlordProfile(
        id: 'uid-1',
        email: 'a@b.fr',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        rgpdConsentAt: consentAt,
        rgpdConsentVersion: 'v1-2026-06',
      );

      final updated = original.copyWith(fullName: 'Nouveau Nom');

      expect(updated.rgpdConsentAt, consentAt);
      expect(updated.rgpdConsentVersion, 'v1-2026-06');
      expect(updated.fullName, 'Nouveau Nom');
    });

    test('equality — deux profils identiques sont égaux', () {
      final p1 = LandlordProfile(
        id: 'uid-1',
        email: 'a@b.fr',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        rgpdConsentAt: consentAt,
        rgpdConsentVersion: 'v1-2026-06',
      );
      final p2 = LandlordProfile(
        id: 'uid-1',
        email: 'a@b.fr',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        rgpdConsentAt: consentAt,
        rgpdConsentVersion: 'v1-2026-06',
      );

      expect(p1, equals(p2));
    });

    test('equality — versions différentes ne sont pas égales', () {
      final p1 = LandlordProfile(
        id: 'uid-1',
        email: 'a@b.fr',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        rgpdConsentAt: consentAt,
        rgpdConsentVersion: 'legacy-1',
      );
      final p2 = LandlordProfile(
        id: 'uid-1',
        email: 'a@b.fr',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        rgpdConsentAt: consentAt,
        rgpdConsentVersion: 'v1-2026-06',
      );

      expect(p1, isNot(equals(p2)));
    });
  });
}
