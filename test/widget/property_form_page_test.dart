import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/ui/theme/property_color.dart';
import 'package:easyrent/features/properties/application/property_form_controller.dart';
import 'package:easyrent/features/properties/data/property_repository.dart';
import 'package:easyrent/features/properties/domain/heating_type.dart';
import 'package:easyrent/features/properties/domain/property.dart';
import 'package:easyrent/features/properties/domain/property_form_state.dart';
import 'package:easyrent/features/properties/domain/property_list_item.dart';
import 'package:easyrent/features/properties/domain/property_submit_error.dart';
import 'package:easyrent/features/properties/domain/property_type.dart';
import 'package:easyrent/features/properties/presentation/property_form_page.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Fake repository — aucun appel réseau.
// ---------------------------------------------------------------------------

class _FakePropertyRepository implements PropertyRepository {
  Property? createdProperty;
  Property? updatedProperty;
  Exception? createError;

  @override
  Future<List<Property>> list() async => [];

  @override
  Future<Property> getById(String id) async {
    return _makeProperty(id: id);
  }

  @override
  Future<Property> create({
    required String name,
    required String address,
    required PropertyType type,
    double? surfaceM2,
    String? postalCode,
    String? city,
    int? rooms,
    int? bedrooms,
    int? floor,
    bool hasElevator = false,
    bool furnished = false,
    HeatingType? heatingType,
    String? dpeLetter,
    int? dpeValueKwhM2Year,
    String? gesLetter,
    int? constructionYear,
    int? purchasePriceCents,
    DateTime? purchaseDate,
    int? notaryFeesCents,
    bool isNewProperty = false,
    int? propertyTaxAnnualCents,
    int? insurancePnoAnnualCents,
    int? condoFeesNonRecoverableCents,
    int? loanPrincipalCents,
    int? loanRateBps,
    int? loanInsuranceBps,
    int? loanDurationMonths,
    DateTime? loanStartDate,
    int? loanMonthlyPaymentOverrideCents,
  }) async {
    if (createError != null) throw createError!;
    createdProperty = _makeProperty(
      name: name,
      address: address,
      type: type,
      surfaceM2: surfaceM2,
      postalCode: postalCode,
      city: city,
    );
    return createdProperty!;
  }

  @override
  Future<Property> update(Property property) async {
    updatedProperty = property;
    return property;
  }

  @override
  Future<int> countActiveLeases(String propertyId) async => 0;

  @override
  Future<void> archive(String id) async {}

  @override
  Future<List<PropertyListItem>> listWithLeases() async => [];

  Property _makeProperty({
    String id = 'test-id',
    String name = 'Test',
    String address = '1 rue test',
    PropertyType type = PropertyType.appartement,
    double? surfaceM2,
    String? postalCode,
    String? city,
  }) => Property(
    id: id,
    landlordId: 'landlord-id',
    name: name,
    address: address,
    type: type,
    surfaceM2: surfaceM2,
    postalCode: postalCode,
    city: city,
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
  );
}

// ---------------------------------------------------------------------------
// Helper de montage.
// ---------------------------------------------------------------------------

Widget _buildForm({
  Property? initial,
  _FakePropertyRepository? repo,
  PropertyFormState? initialState,
}) {
  final fakeRepo = repo ?? _FakePropertyRepository();
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => PropertyFormPage(initial: initial),
      ),
      GoRoute(
        path: '/properties',
        builder: (context, state) => const Scaffold(body: Text('properties')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      propertyRepositoryProvider.overrideWithValue(fakeRepo),
      if (initialState != null)
        propertyFormControllerProvider.overrideWith(
          (ref) => PropertyFormController(ref)..state = initialState,
        ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      locale: const Locale('fr'),
      supportedLocales: supportedLocales,
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PropertyFormPage — smoke tests', () {
    // -----------------------------------------------------------------------
    // Mode création — champs présents (section 1 visible directement)
    // -----------------------------------------------------------------------
    testWidgets('mode création — les champs de la section 1 sont présents', (
      tester,
    ) async {
      await tester.pumpWidget(_buildForm());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('field_name')), findsOneWidget);
      expect(find.byKey(const Key('field_address')), findsOneWidget);
      expect(find.byKey(const Key('field_type')), findsOneWidget);
      expect(find.byKey(const Key('field_surface')), findsOneWidget);
      expect(find.byKey(const Key('field_postal_code')), findsOneWidget);
      expect(find.byKey(const Key('field_city')), findsOneWidget);
    });

    testWidgets('mode création — titre "Nouveau bien"', (tester) async {
      await tester.pumpWidget(_buildForm());
      await tester.pumpAndSettle();

      expect(find.text('Nouveau bien'), findsOneWidget);
    });

    testWidgets('mode création — bouton "Créer le bien" présent', (
      tester,
    ) async {
      await tester.pumpWidget(_buildForm());
      await tester.pumpAndSettle();

      expect(find.text('Créer le bien'), findsOneWidget);
    });

    testWidgets(
      'sections ExpansionTile Caractéristiques et DPE/GES présentes',
      (tester) async {
        await tester.pumpWidget(_buildForm());
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('section_caracteristiques')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('section_dpe')), findsOneWidget);
      },
    );

    // -----------------------------------------------------------------------
    // Validation — erreurs inline sur soumission incomplète
    // -----------------------------------------------------------------------
    testWidgets(
      'validation — erreur "nom obligatoire" si nom vide à la soumission',
      (tester) async {
        await tester.pumpWidget(_buildForm());
        await tester.pumpAndSettle();

        // Scroller jusqu'au bouton avant de tapper (formulaire plus long).
        await tester.ensureVisible(find.byKey(const Key('btn_submit_form')));
        await tester.tap(find.byKey(const Key('btn_submit_form')));
        await tester.pumpAndSettle();

        expect(find.text('Le nom du bien est obligatoire'), findsOneWidget);
      },
    );

    testWidgets('validation — erreur "adresse obligatoire" si adresse vide', (
      tester,
    ) async {
      await tester.pumpWidget(_buildForm());
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('field_name')), 'Mon appart');
      // Scroller jusqu'au bouton avant de tapper (formulaire plus long).
      await tester.ensureVisible(find.byKey(const Key('btn_submit_form')));
      await tester.tap(find.byKey(const Key('btn_submit_form')));
      await tester.pumpAndSettle();

      expect(find.textContaining('adresse'), findsWidgets);
    });

    // -----------------------------------------------------------------------
    // Mode édition — champs pré-remplis
    // -----------------------------------------------------------------------
    testWidgets('mode édition — champs pré-remplis (section 1)', (
      tester,
    ) async {
      final property = Property(
        id: 'id-1',
        landlordId: 'landlord-1',
        name: 'Appart Lyon',
        address: '5 rue Mercière, 69001 Lyon',
        type: PropertyType.appartement,
        surfaceM2: 42.5,
        postalCode: '69001',
        city: 'Lyon',
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );

      await tester.pumpWidget(_buildForm(initial: property));
      await tester.pumpAndSettle();

      expect(find.text('Appart Lyon'), findsOneWidget);
      expect(find.text('5 rue Mercière, 69001 Lyon'), findsOneWidget);
    });

    testWidgets('mode édition — titre "Modifier le bien"', (tester) async {
      final property = Property(
        id: 'id-1',
        landlordId: 'landlord-1',
        name: 'Maison Bordeaux',
        address: '10 allée des Roses, 33000 Bordeaux',
        type: PropertyType.maison,
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );

      await tester.pumpWidget(_buildForm(initial: property));
      await tester.pumpAndSettle();

      expect(find.text('Modifier le bien'), findsOneWidget);
    });

    testWidgets(
      'backward compat — bien sans nouveaux champs charge sans erreur',
      (tester) async {
        // Bien "legacy" sans aucun des nouveaux champs.
        final legacy = Property(
          id: 'legacy-id',
          landlordId: 'landlord-1',
          name: 'Bien sans DPE',
          address: '1 ancienne rue',
          type: PropertyType.maison,
          createdAt: DateTime(2023),
          updatedAt: DateTime(2023),
        );

        await tester.pumpWidget(_buildForm(initial: legacy));
        await tester.pumpAndSettle();

        // La page doit être rendue sans exception.
        expect(find.text('Modifier le bien'), findsOneWidget);
        expect(find.byKey(const Key('btn_submit_form')), findsOneWidget);
      },
    );

    // -----------------------------------------------------------------------
    // État submitting — bouton désactivé
    // -----------------------------------------------------------------------
    testWidgets('état submitting — bouton désactivé avec indicateur', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildForm(initialState: const PropertyFormState.submitting()),
      );
      await tester.pump();

      final btn = tester.widget<FilledButton>(
        find.byKey(const Key('btn_submit_form')),
      );
      expect(btn.onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // État erreur — message affiché inline
    // -----------------------------------------------------------------------
    // -----------------------------------------------------------------------
    // Couleur d'identité (FEAT-057) — édition uniquement
    // -----------------------------------------------------------------------
    testWidgets('mode création — pas de sélecteur de couleur (attribution '
        'automatique, rien à choisir avant que le bien existe)', (
      tester,
    ) async {
      await tester.pumpWidget(_buildForm());
      await tester.pumpAndSettle();

      expect(find.text('Couleur d\'identité'), findsNothing);
      expect(find.byKey(const Key('color_swatch_cobalt')), findsNothing);
    });

    testWidgets(
      'mode édition — sélecteur de couleur présent, une pastille par teinte',
      (tester) async {
        final property = Property(
          id: 'id-1',
          landlordId: 'landlord-1',
          name: 'Appart Lyon',
          address: '5 rue Mercière',
          type: PropertyType.appartement,
          colorKey: 'cobalt',
          createdAt: DateTime(2024),
          updatedAt: DateTime(2024),
        );

        await tester.pumpWidget(_buildForm(initial: property));
        await tester.pumpAndSettle();

        expect(find.text('Couleur d\'identité'), findsOneWidget);
        for (final key in PropertyColorKey.values) {
          await tester.ensureVisible(
            find.byKey(Key('color_swatch_${key.name}')),
          );
          expect(find.byKey(Key('color_swatch_${key.name}')), findsOneWidget);
        }
      },
    );

    testWidgets(
      'mode édition — changer la couleur puis soumettre envoie la nouvelle '
      'clé au repository',
      (tester) async {
        final repo = _FakePropertyRepository();
        final property = Property(
          id: 'id-1',
          landlordId: 'landlord-1',
          name: 'Appart Lyon',
          address: '5 rue Mercière',
          type: PropertyType.appartement,
          colorKey: 'cobalt',
          createdAt: DateTime(2024),
          updatedAt: DateTime(2024),
        );

        await tester.pumpWidget(_buildForm(initial: property, repo: repo));
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const Key('color_swatch_moutarde')),
        );
        await tester.tap(find.byKey(const Key('color_swatch_moutarde')));
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.byKey(const Key('btn_submit_form')));
        await tester.tap(find.byKey(const Key('btn_submit_form')));
        await tester.pumpAndSettle();

        expect(repo.updatedProperty?.colorKey, 'moutarde');
      },
    );

    testWidgets(
      'mode édition — bien "legacy" sans colorKey stockée → soumettre sans '
      'toucher la couleur envoie le repli déterministe (jamais null)',
      (tester) async {
        final repo = _FakePropertyRepository();
        final legacy = Property(
          id: 'legacy-id',
          landlordId: 'landlord-1',
          name: 'Bien sans couleur stockée',
          address: '1 ancienne rue',
          type: PropertyType.maison,
          createdAt: DateTime(2023),
          updatedAt: DateTime(2023),
        );

        await tester.pumpWidget(_buildForm(initial: legacy, repo: repo));
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.byKey(const Key('btn_submit_form')));
        await tester.tap(find.byKey(const Key('btn_submit_form')));
        await tester.pumpAndSettle();

        expect(repo.updatedProperty?.colorKey, isNotNull);
        expect(
          PropertyColorKey.parse(repo.updatedProperty!.colorKey),
          isNotNull,
        );
      },
    );

    testWidgets('état erreur — message affiché inline', (tester) async {
      // FEAT-043 : PropertyFormState.error.message porte désormais le `name`
      // technique d'un PropertySubmitError (pas un texte FR en dur) — la
      // présentation le retraduit via PropertySubmitErrorL10n.
      await tester.pumpWidget(
        _buildForm(
          initialState: PropertyFormState.error(
            message: PropertySubmitError.saveFailed.name,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('sauvegarde'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // F-2 (correctif navigation) — succès : édition → pop() (retour fiche
  // détail), création → go('/properties') (comportement historique).
  // ---------------------------------------------------------------------------
  group('PropertyFormPage — navigation de succès (F-2)', () {
    late _DriveableFormController ctrl;

    ProviderContainer makeContainer() {
      final container = ProviderContainer(
        overrides: [
          propertyRepositoryProvider.overrideWithValue(
            _FakePropertyRepository(),
          ),
          propertyFormControllerProvider.overrideWith((ref) {
            ctrl = _DriveableFormController(ref);
            return ctrl;
          }),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    // Router à 2 niveaux (liste → fiche détail → push formulaire) : seul un
    // harnais avec une fiche détail DISTINCTE de la liste peut prouver que
    // l'édition revient à la fiche (pop()) et pas à la liste (go()) — c'est
    // précisément le bug F-2.
    Widget buildWithDetailStack({
      required ProviderContainer container,
      required Property property,
    }) {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/properties',
            builder: (context, _) => const Scaffold(body: Text('liste biens')),
          ),
          GoRoute(
            path: '/property-detail',
            builder: (context, _) => Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    const Text('fiche détail bien'),
                    TextButton(
                      onPressed: () => context.push('/property-detail/edit'),
                      child: const Text('modifier'),
                    ),
                  ],
                ),
              ),
            ),
            routes: [
              GoRoute(
                path: 'edit',
                builder: (context, _) => PropertyFormPage(initial: property),
              ),
            ],
          ),
        ],
        initialLocation: '/property-detail',
      );
      return UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          locale: const Locale('fr'),
          supportedLocales: supportedLocales,
        ),
      );
    }

    testWidgets(
      'édition → succès → pop() (retour à la fiche détail, pas la liste)',
      (tester) async {
        final container = makeContainer();
        final property = Property(
          id: 'id-1',
          landlordId: 'landlord-1',
          name: 'Appart Lyon',
          address: '5 rue Mercière',
          type: PropertyType.appartement,
          createdAt: DateTime(2024),
          updatedAt: DateTime(2024),
        );
        await tester.pumpWidget(
          buildWithDetailStack(container: container, property: property),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('modifier'));
        await tester.pumpAndSettle();
        expect(find.byType(PropertyFormPage), findsOneWidget);

        ctrl.emitSuccess(property);
        await tester.pumpAndSettle();

        // pop() : retour à la FICHE DÉTAIL, pas à la liste — preuve que la
        // pile intermédiaire (détail → edit) n'a pas été écrasée par un
        // go('/properties').
        expect(find.byType(PropertyFormPage), findsNothing);
        expect(find.text('fiche détail bien'), findsOneWidget);
        expect(find.text('liste biens'), findsNothing);
      },
    );

    testWidgets(
      'création → succès → go(/properties) (comportement liste conservé)',
      (tester) async {
        final container = makeContainer();
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/properties',
              builder: (context, _) =>
                  const Scaffold(body: Text('liste biens')),
              routes: [
                GoRoute(
                  path: 'new',
                  builder: (context, _) => const PropertyFormPage(),
                ),
              ],
            ),
          ],
          initialLocation: '/properties/new',
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              locale: const Locale('fr'),
              supportedLocales: supportedLocales,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final created = Property(
          id: 'new-id',
          landlordId: 'landlord-1',
          name: 'Nouveau bien',
          address: '1 rue test',
          type: PropertyType.appartement,
          createdAt: DateTime(2024),
          updatedAt: DateTime(2024),
        );
        ctrl.emitSuccess(created);
        await tester.pumpAndSettle();

        expect(find.byType(PropertyFormPage), findsNothing);
        expect(find.text('liste biens'), findsOneWidget);
      },
    );
  });
}

/// Contrôleur pilotable depuis le test : expose l'émission d'un état succès
/// (le setter `state` de [StateNotifier] est protected, accessible en
/// sous-classe).
class _DriveableFormController extends PropertyFormController {
  _DriveableFormController(super.ref);

  void emitSuccess(Property property) {
    state = PropertyFormState.success(property: property);
  }
}
