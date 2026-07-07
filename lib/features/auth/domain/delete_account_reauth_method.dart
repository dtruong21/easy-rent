/// Méthode de confirmation d'identité exigée avant la suppression de
/// compte (FEAT-045) — dérivée des providers du user Firebase courant.
///
/// Firebase exige une authentification récente pour détruire un compte
/// (garde `recent-login-required` de la callable `deleteAccount`) ; la
/// méthode dépend du type de compte :
/// - [password] : compte email → re-saisie du mot de passe actuel ;
/// - [google] / [apple] : compte social → nouveau flux OAuth (popup web /
///   natif mobile). Apple fournit au passage l'`authorizationCode` requis
///   pour la révocation de token (App Store 5.1.1(v)) ;
/// - [none] : session anonyme — aucun credential à re-présenter (la
///   callable exempte les tokens anonymes de la garde de fraîcheur).
enum DeleteAccountReauthMethod { password, google, apple, none }
