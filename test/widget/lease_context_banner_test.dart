/// Tests widget de [LeaseContextBanner].
///
/// Couvre : rendu nominal (nom bien + locataire + compteurs),
/// squelette pendant chargement, compteurs pluriels.
library;

import 'dart:typed_data';
import 'package:easyrent/core/ui/theme/app_colors.dart';
import 'package:easyrent/core/ui/theme/app_radii.dart';
import 'package:easyrent/features/leases/data/lease_repository.dart';
import 'package:easyrent/features/leases/domain/lease.dart';
import 'package:easyrent/features/leases/domain/lease_list_item.dart';
import 'package:easyrent/features/leases/domain/lease_status.dart';
import 'package:easyrent/features/leases/domain/lease_type.dart';
import 'package:easyrent/features/payments/domain/payment_method.dart';
import 'package:easyrent/features/properties/data/property_repository.dart';
import 'package:easyrent/features/properties/domain/heating_type.dart';
import 'package:easyrent/features/properties/domain/property.dart';
import 'package:easyrent/features/properties/domain/property_list_item.dart';
import 'package:easyrent/features/properties/domain/property_type.dart';
import 'package:easyrent/features/receipts/data/receipts_repository.dart';
import 'package:easyrent/features/receipts/domain/document_type.dart';
import 'package:easyrent/features/receipts/domain/receipt.dart';
import 'package:easyrent/features/receipts/domain/receipt_generation_result.dart';
import 'package:easyrent/features/receipts/presentation/widgets/lease_context_banner.dart';
import 'package:easyrent/features/tenants/data/tenant_repository.dart';
import 'package:easyrent/features/tenants/domain/tenant.dart';
import 'package:easyrent/features/tenants/domain/tenant_list_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Fake repositories
// ---------------------------------------------------------------------------

class _FakeLeaseRepo implements LeaseRepository {
  final Lease? lease;
  _FakeLeaseRepo({this.lease});

  @override
  Future<Lease> getById(String id) async {
    if (lease == null) throw LeaseNotFoundException(id);
    return lease!;
  }

  @override
  Future<List<LeaseListItem>> listForDisplay() async => [];
  @override
  Future<Lease> create({
    required String propertyId,
    required String tenantId,
    required int rentAmountCents,
    required int chargesAmountCents,
    required DateTime startDate,
    DateTime? endDate,
    LeaseType leaseType = LeaseType.unfurnished,
    int? depositAmountCents,
    int paymentDay = 1,
    PaymentMethod paymentMethod = PaymentMethod.virement,
    double? irlIndexValue,
    String? irlQuarterRef,
    int agencyFeesCents = 0,
    bool solidarityClause = false,
    bool entryInventoryDone = false,
  }) async => throw UnimplementedError();
  @override
  Future<Lease> update(Lease lease) async => throw UnimplementedError();
  @override
  Future<Lease> close(String id, {required DateTime effectiveEndDate}) async =>
      throw UnimplementedError();
  @override
  Future<bool> hasOtherActiveLeaseOnProperty(
    String propertyId, {
    String? excludeLeaseId,
  }) async => false;
  @override
  Future<void> archive(String id) async {}
}

class _FakeTenantRepo implements TenantRepository {
  final Tenant? tenant;
  _FakeTenantRepo({this.tenant});

  @override
  Future<Tenant> getById(String id) async {
    if (tenant == null) throw TenantNotFoundException(id);
    return tenant!;
  }

  @override
  Future<List<Tenant>> list() async => [];
  @override
  Future<Tenant> create({
    required String firstName,
    required String lastName,
    required String email,
    String? phone,
    DateTime? birthDate,
    String? birthPlace,
    String? nationality,
    String? profession,
    String? employer,
    int? monthlyIncomeCents,
    String? previousAddress,
    String? guarantorName,
    String? guarantorEmail,
    String? guarantorPhone,
  }) async => throw UnimplementedError();
  @override
  Future<Tenant> update(Tenant tenant) async => throw UnimplementedError();
  @override
  Future<int> countActiveLeases(String tenantId) async => 0;
  @override
  Future<void> archive(String id) async {}
  @override
  Future<List<TenantListItem>> listWithActiveLeases() async => [];
  @override
  Future<List<Map<String, dynamic>>> listLeasesForTenant(
    String tenantId,
  ) async => [];
}

class _FakePropertyRepo implements PropertyRepository {
  final Property? property;
  _FakePropertyRepo({this.property});

  @override
  Future<Property> getById(String id) async {
    if (property == null) throw PropertyNotFoundException(id);
    return property!;
  }

  @override
  Future<List<Property>> list() async => [];
  @override
  Future<List<PropertyListItem>> listWithLeases() async => [];
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
  }) async => throw UnimplementedError();
  @override
  Future<Property> update(Property property) async =>
      throw UnimplementedError();
  @override
  Future<int> countActiveLeases(String propertyId) async => 0;
  @override
  Future<void> archive(String id) async {}
}

class _FakeReceiptsRepo implements ReceiptsRepository {
  final List<Receipt> receipts;
  _FakeReceiptsRepo({this.receipts = const []});

  @override
  Future<List<Receipt>> listForLease(String leaseId) async => receipts;
  @override
  Future<Receipt> getById(String id) async => throw UnimplementedError();
  @override
  Future<ReceiptGenerationResult> generate({
    List<String>? paymentIds,
    String? leaseId,
    DateTime? periodStart,
    DateTime? periodEnd,
  }) async => throw UnimplementedError();
  @override
  Future<String> signedUrl(String pdfPath) async => 'https://example.com';
  @override
  Future<void> voidReceipt(String id, String reason) async {}
  @override
  Future<Receipt> markReceiptAsShared({
    required String receiptId,
    required String tenantEmail,
  }) async => throw UnimplementedError();

  @override
  Future<Uint8List> renderPdfBytes(String receiptId) async => Uint8List(0);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ThemeData _appTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
  extensions: const [AppColors.light, AppRadii()],
);

Lease _makeLease() => Lease(
  id: 'lease-1',
  landlordId: 'landlord-1',
  propertyId: 'property-1',
  tenantId: 'tenant-1',
  rentAmountCents: 110000,
  chargesAmountCents: 10000,
  startDate: DateTime(2026, 1, 1),
  endDate: DateTime(2029, 1, 1),
  status: LeaseStatus.active,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

Tenant _makeTenant() => Tenant(
  id: 'tenant-1',
  landlordId: 'landlord-1',
  firstName: 'Jean',
  lastName: 'Dupont',
  email: 'jean.dupont@example.com',
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

Property _makeProperty() => Property(
  id: 'property-1',
  landlordId: 'landlord-1',
  name: 'Appartement Paris 2e',
  address: '12 rue de la Paix',
  type: PropertyType.appartement,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

Receipt _makeReceipt({bool hasBeenShared = false}) => Receipt(
  id: 'r-1',
  landlordId: 'landlord-1',
  leaseId: 'lease-1',
  paymentIds: const ['pay-1'],
  periodStart: DateTime(2026, 3, 1),
  periodEnd: DateTime(2026, 3, 31),
  totalCents: 120000,
  rentCents: 110000,
  chargesCents: 10000,
  documentType: DocumentType.quittance,
  pdfPath: 'landlord-1/r-1.pdf',
  isVoided: false,
  isStale: false,
  generatedAt: DateTime(2026, 3, 5),
  createdAt: DateTime(2026, 3, 5),
  sentAt: hasBeenShared ? DateTime(2026, 3, 6) : null,
  sentToEmail: hasBeenShared ? 'jean.dupont@example.com' : null,
);

Widget _buildBanner({
  Lease? lease,
  Tenant? tenant,
  Property? property,
  List<Receipt> receipts = const [],
}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => const Scaffold(
          body: SingleChildScrollView(
            child: LeaseContextBanner(leaseId: 'lease-1'),
          ),
        ),
      ),
      GoRoute(
        path: '/properties/:id',
        builder: (_, state) =>
            Scaffold(body: Text('property ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/tenants/:id',
        builder: (_, state) =>
            Scaffold(body: Text('tenant ${state.pathParameters['id']}')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      leaseRepositoryProvider.overrideWithValue(_FakeLeaseRepo(lease: lease)),
      tenantRepositoryProvider.overrideWithValue(
        _FakeTenantRepo(tenant: tenant),
      ),
      propertyRepositoryProvider.overrideWithValue(
        _FakePropertyRepo(property: property),
      ),
      receiptsRepositoryProvider.overrideWithValue(
        _FakeReceiptsRepo(receipts: receipts),
      ),
    ],
    child: MaterialApp.router(routerConfig: router, theme: _appTheme()),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('LeaseContextBanner', () {
    testWidgets('squelette rendu sans crash si bail pas encore chargé', (
      tester,
    ) async {
      // Pas de bail → squelette.
      await tester.pumpWidget(_buildBanner());
      await tester.pump();

      expect(find.byType(LeaseContextBanner), findsOneWidget);
      // Pas d'erreur.
    });

    testWidgets('rendu nominal — nom bien + locataire + compteurs', (
      tester,
    ) async {
      final receipt = _makeReceipt(hasBeenShared: true);

      await tester.pumpWidget(
        _buildBanner(
          lease: _makeLease(),
          tenant: _makeTenant(),
          property: _makeProperty(),
          receipts: [receipt],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Appartement Paris 2e'), findsOneWidget);
      expect(find.textContaining('Jean Dupont'), findsOneWidget);
      expect(find.textContaining('1 quittance'), findsOneWidget);
      expect(find.textContaining('1 envoyée'), findsOneWidget);
    });

    testWidgets('0 quittances — compteurs pluriels corrects', (tester) async {
      await tester.pumpWidget(
        _buildBanner(lease: _makeLease(), tenant: _makeTenant(), receipts: []),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('0 quittances'), findsOneWidget);
      expect(find.textContaining('0 envoyées'), findsOneWidget);
    });

    testWidgets('adresse du bien affichée avec nom', (tester) async {
      await tester.pumpWidget(
        _buildBanner(
          lease: _makeLease(),
          tenant: _makeTenant(),
          property: _makeProperty(),
          receipts: [],
        ),
      );
      await tester.pumpAndSettle();

      // Nom + adresse visible dans le texte concaténé.
      expect(find.textContaining('12 rue de la Paix'), findsOneWidget);
    });
  });
}
