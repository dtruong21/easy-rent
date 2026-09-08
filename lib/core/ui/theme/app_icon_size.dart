/// Échelle canonique de tailles d'icônes Baillan.
///
/// Avant ce jeton, les tailles d'icônes étaient saisies en dur au fil des
/// écrans (14, 16, 18, 20… plus des valeurs isolées comme 11, 48, 56), d'où des
/// icônes de gabarits incohérents pour un même rôle. Utiliser ces constantes
/// plutôt qu'un littéral aligne les icônes sur une grille commune.
///
/// Repères d'usage :
/// - [xs] badge inline minuscule (puce « récurrent »)
/// - [sm] icône dense dans une liste
/// - [md] icône inline accolée à du texte (cas le plus courant)
/// - [lg] icône légèrement mise en avant
/// - [xl] icône autonome (défaut Material)
/// - [hero] illustration d'état vide / onboarding
abstract final class AppIconSize {
  static const double xs = 14;
  static const double sm = 16;
  static const double md = 18;
  static const double lg = 20;
  static const double xl = 24;
  static const double hero = 48;
}
