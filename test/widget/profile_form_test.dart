/// Tests widget de [ProfileForm].
///
/// Couvre :
/// - Les 3 champs sont présents (fullName, phone, address)
/// - [validateAll] retourne false si fullName vide
/// - [validateAll] retourne false si address vide
/// - [validateAll] retourne true si fullName + address renseignés (phone optionnel)
/// - phone invalide → message d'erreur inline
library;

import 'package:easyrent/features/profile/presentation/widgets/profile_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helper de montage
// ---------------------------------------------------------------------------

class _TestHarness extends StatefulWidget {
  const _TestHarness({this.fullName = '', this.phone = '', this.address = ''});

  final String fullName;
  final String phone;
  final String address;

  @override
  State<_TestHarness> createState() => _TestHarnessState();
}

class _TestHarnessState extends State<_TestHarness> {
  final _formKey = GlobalKey<FormState>();
  final _formWidgetKey = GlobalKey<ProfileFormWidgetState>();
  late final TextEditingController _fullNameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addressCtrl;
  bool? _lastValidateResult;

  @override
  void initState() {
    super.initState();
    _fullNameCtrl = TextEditingController(text: widget.fullName);
    _phoneCtrl = TextEditingController(text: widget.phone);
    _addressCtrl = TextEditingController(text: widget.address);
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              ProfileForm(
                key: _formWidgetKey,
                formKey: _formKey,
                fullNameController: _fullNameCtrl,
                phoneController: _phoneCtrl,
                addressController: _addressCtrl,
              ),
              ElevatedButton(
                key: const Key('btn_validate'),
                onPressed: () {
                  setState(() {
                    _lastValidateResult = _formWidgetKey.currentState
                        ?.validateAll();
                  });
                },
                child: const Text('Valider'),
              ),
              if (_lastValidateResult != null)
                Text(
                  'validate_result:${_lastValidateResult!}',
                  key: const Key('validate_result'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ProfileForm', () {
    // -----------------------------------------------------------------------
    // Structure des champs
    // -----------------------------------------------------------------------
    testWidgets('les 3 champs éditables sont présents', (tester) async {
      await tester.pumpWidget(const _TestHarness());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('field_full_name')), findsOneWidget);
      expect(find.byKey(const Key('field_phone')), findsOneWidget);
      expect(find.byKey(const Key('field_address')), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // validateAll — champs obligatoires vides
    // -----------------------------------------------------------------------
    testWidgets('validateAll → false si fullName vide', (tester) async {
      await tester.pumpWidget(
        const _TestHarness(address: '12 rue de la Paix\n75001 Paris'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_validate')));
      await tester.pumpAndSettle();

      expect(find.text('validate_result:false'), findsOneWidget);
    });

    testWidgets('validateAll → false si address vide', (tester) async {
      await tester.pumpWidget(const _TestHarness(fullName: 'Jean Dupont'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_validate')));
      await tester.pumpAndSettle();

      expect(find.text('validate_result:false'), findsOneWidget);
    });

    testWidgets('validateAll → false si les deux champs requis vides', (
      tester,
    ) async {
      await tester.pumpWidget(const _TestHarness());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_validate')));
      await tester.pumpAndSettle();

      expect(find.text('validate_result:false'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // validateAll — cas valides
    // -----------------------------------------------------------------------
    testWidgets(
      'validateAll → true si fullName + address renseignés (phone optionnel)',
      (tester) async {
        await tester.pumpWidget(
          const _TestHarness(
            fullName: 'Jean Dupont',
            address: '12 rue de la Paix\n75001 Paris',
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_validate')));
        await tester.pumpAndSettle();

        expect(find.text('validate_result:true'), findsOneWidget);
      },
    );

    testWidgets(
      'validateAll → true si fullName + phone + address tous renseignés',
      (tester) async {
        await tester.pumpWidget(
          const _TestHarness(
            fullName: 'Jean Dupont',
            phone: '06 12 34 56 78',
            address: '12 rue de la Paix\n75001 Paris',
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_validate')));
        await tester.pumpAndSettle();

        expect(find.text('validate_result:true'), findsOneWidget);
      },
    );

    // -----------------------------------------------------------------------
    // Validation phone — format invalide
    // -----------------------------------------------------------------------
    testWidgets('phone invalide → message erreur inline', (tester) async {
      await tester.pumpWidget(
        const _TestHarness(
          fullName: 'Jean Dupont',
          phone: 'abc',
          address: '12 rue de la Paix\n75001 Paris',
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_validate')));
      await tester.pumpAndSettle();

      expect(find.textContaining('invalide'), findsOneWidget);
      expect(find.text('validate_result:false'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Erreur inline après validateAll
    // -----------------------------------------------------------------------
    testWidgets(
      'erreur fullName "obligatoire" visible après validateAll raté',
      (tester) async {
        await tester.pumpWidget(
          const _TestHarness(address: '12 rue de la Paix\n75001 Paris'),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_validate')));
        await tester.pumpAndSettle();

        expect(find.textContaining('obligatoire'), findsWidgets);
      },
    );
  });
}
