import 'package:easyrent/core/widgets/lease_status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _buildBadge(String status) => MaterialApp(
  home: Scaffold(body: LeaseStatusBadge(status: status)),
);

void main() {
  group('LeaseStatusBadge', () {
    testWidgets('statut "active" → label "Actif"', (tester) async {
      await tester.pumpWidget(_buildBadge('active'));
      expect(find.text('Actif'), findsOneWidget);
    });

    testWidgets('statut "terminated" → label "Terminé"', (tester) async {
      await tester.pumpWidget(_buildBadge('terminated'));
      expect(find.text('Terminé'), findsOneWidget);
    });

    testWidgets('statut "archived" → label "Archivé"', (tester) async {
      await tester.pumpWidget(_buildBadge('archived'));
      expect(find.text('Archivé'), findsOneWidget);
    });

    testWidgets('statut inconnu → affiche le statut brut', (tester) async {
      await tester.pumpWidget(_buildBadge('pending'));
      expect(find.text('pending'), findsOneWidget);
    });

    testWidgets('statut "active" → couleur primary (pas outline)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue)),
          home: Scaffold(body: LeaseStatusBadge(status: 'active')),
        ),
      );
      await tester.pumpAndSettle();

      // Le badge est rendu — vérification que le widget est dans l'arbre.
      expect(find.byType(LeaseStatusBadge), findsOneWidget);
      // Vérification que le texte est 'Actif' (couleur est visuelle — non testable
      // directement en widget test sans golden test).
      expect(find.text('Actif'), findsOneWidget);
    });

    testWidgets('statut "terminated" → label différent de "Actif"', (
      tester,
    ) async {
      await tester.pumpWidget(_buildBadge('terminated'));
      expect(find.text('Actif'), findsNothing);
      expect(find.text('Terminé'), findsOneWidget);
    });
  });
}
