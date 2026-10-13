import 'package:flutter/widgets.dart';

/// Ferme le clavier quand on touche une zone sans action de l'écran.
///
/// Sur iOS, les claviers numériques (téléphone, montants, index de
/// compteurs) n'ont pas de touche « OK », et toucher à côté du champ ne
/// fermait rien — seul un défilement le faisait (recette iOS, #197).
///
/// Posé une fois autour de toute l'app (`MaterialApp.builder`). Le détecteur
/// est « translucide » et ne gagne l'arène des gestes que si rien en dessous
/// ne réagit au tap : un bouton, un autre champ ou une case gardent leur
/// comportement ; seul un tap dans le vide retire le focus.
class DismissKeyboardOnTap extends StatelessWidget {
  const DismissKeyboardOnTap({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: child,
    );
  }
}
