/// États de session possibles pour un visiteur Baillan.
///
/// Trois états mutuellement exclusifs (jamais deux vrais simultanément) :
///
/// - [unauthenticated] : aucune session Firebase Auth active.
/// - [anonymous] : session Firebase Anonymous Auth active (« essai sans
///   compte »). Accès limité au simulateur ; expire après 14 jours
///   d'inactivité glissants (voir `anonExpiresAt` sur `landlords/{uid}`).
/// - [fullyAuthenticated] : compte email/password (vérifié), Google ou
///   Apple. Accès complet à l'application.
enum SessionState { unauthenticated, anonymous, fullyAuthenticated }
