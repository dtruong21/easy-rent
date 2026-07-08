import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/auth_session_provider.dart';
import '../../data/landlord_tier_repository.dart';
import '../../domain/session_state.dart';
import 'anon_expiry_warning_dialog.dart';

/// Provider global qui mémorise si la modal d'expiration J-1 a déjà été
/// affichée pendant cette session. Persistant au niveau ProviderContainer
/// (donc au niveau app), pas au niveau widget — le state widget local
/// resetait à chaque navigation, faisant re-fire la modal à chaque page
/// (harcèlement anti-goal, cf. review HIGH). Reset naturel au reboot app
/// ou au signOut/link (le provider est ré-init au changement de session).
final _anonExpiryDialogShownProvider = StateProvider<bool>((ref) => false);

/// Bandeau persistant affiché en haut des pages accessibles aux anonymes
/// (landing, `/simulator`, `/privacy`).
///
/// Escalade de tonalité selon `anonExpiresAt` :
/// - > J-3 : ton neutre « Mode démo · 1 scénario »
/// - ≤ J-3 : ton alarmé (oxblood) « expire dans N jours »
/// - ≤ J-1 (24h) : une modal bloquante s'affiche UNE FOIS PAR SESSION
///   (via [_anonExpiryDialogShownProvider])
class AnonDemoBanner extends ConsumerWidget {
  const AnonDemoBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionState = ref.watch(sessionStateProvider);
    if (sessionState != SessionState.anonymous) return const SizedBox.shrink();

    final asyncTier = ref.watch(landlordTierProvider);
    final anonExpiresAt = asyncTier.valueOrNull?.anonExpiresAt;
    final daysLeft = anonExpiresAt == null
        ? null
        : anonExpiresAt.difference(DateTime.now()).inHours / 24;

    final isUrgent = daysLeft != null && daysLeft <= 3;
    final isBlocking = daysLeft != null && daysLeft <= 1;

    if (isBlocking && !ref.read(_anonExpiryDialogShownProvider)) {
      // Défère TOUT à un postFrameCallback — muter un provider pendant la
      // build phase déclenche une erreur Riverpod "modifying provider
      // during build". Le postFrame garantit qu'on est hors phase build.
      // Double-check dans le callback (autre rebuild concurrent possible).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        if (ref.read(_anonExpiryDialogShownProvider)) return;
        ref.read(_anonExpiryDialogShownProvider.notifier).state = true;
        showAnonExpiryWarningDialog(context);
      });
    }

    // Dark mode : les couleurs hardcodées disparaissent sur fond ink. On
    // pioche des variants adaptés au thème ambiant pour rester lisible.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color backgroundColor;
    final Color textColor;
    if (isUrgent) {
      backgroundColor = isDark
          ? AppTheme.oxblood.withValues(alpha: 0.22)
          : AppTheme.oxblood.withValues(alpha: 0.12);
      textColor = isDark
          ? AppTheme.oxblood.withValues(alpha: 0.95)
          : AppTheme.oxblood;
    } else {
      backgroundColor = isDark
          ? AppTheme.oliveSoft.withValues(alpha: 0.18)
          : AppTheme.oliveSoft.withValues(alpha: 0.22);
      textColor = isDark ? AppTheme.oliveSoft : AppTheme.olive;
    }

    final message = _messageFor(context, daysLeft);

    return Material(
      key: const Key('anon_demo_banner'),
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        // LayoutBuilder + Wrap pour éviter l'overflow horizontal sur mobile
        // portrait (~360px) où le CTA + le message dépassent en Row rigide.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 480;
            final messageText = Text(
              message,
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            );
            final cta = TextButton(
              key: const Key('anon_demo_banner_cta'),
              onPressed: () => context.go('/signup'),
              child: Text(
                context.l10n.authAnonBannerUnlockCta,
                style: TextStyle(color: textColor),
              ),
            );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [messageText, cta],
              );
            }
            return Row(
              children: [
                Expanded(child: messageText),
                cta,
              ],
            );
          },
        ),
      ),
    );
  }

  String _messageFor(BuildContext context, double? daysLeft) {
    final l10n = context.l10n;
    if (daysLeft == null) return l10n.authAnonBannerDemoMode;
    // Pas d'affichage "0 jours" (bug review) — au 0.x on est dans la
    // fenêtre "moins de 24h", et on affiche le message court.
    if (daysLeft <= 1) {
      return l10n.authAnonBannerExpiresUnder24h;
    }
    final rounded = daysLeft.ceil().clamp(2, 14);
    if (rounded <= 3) {
      return l10n.authAnonBannerExpiresInDays(rounded);
    }
    return l10n.authAnonBannerDemoMode;
  }
}
