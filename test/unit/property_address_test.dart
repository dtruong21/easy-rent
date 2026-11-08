/// composePropertyAddress — composition de l'adresse complète d'un bien.
///
/// ⚠️ Ces cas sont MIROIR de
/// `functions/src/__tests__/property_address.test.ts`. Toute modification ici
/// doit être répercutée là-bas (et réciproquement) : le serveur fige la valeur
/// sur le bail, le client affiche la même chose depuis le bien — une
/// divergence produirait deux adresses différentes pour le même logement.
///
/// Seule exception au miroir : le pendant TypeScript porte un cas de plus
/// (code postal stocké comme NOMBRE dans Firestore), sans équivalent ici — la
/// signature Dart est typée `String?`, le cas ne peut pas se présenter.
library;

import 'package:easyrent/core/utils/property_address.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('composePropertyAddress — champs séparés renseignés', () {
    test('compose rue + code postal + ville (cas nominal du formulaire)', () {
      expect(
        composePropertyAddress(
          address: '48 avenue du Hazay',
          postalCode: '95000',
          city: 'Cergy',
        ),
        '48 avenue du Hazay, 95000 Cergy',
      );
    });

    test('compose une ville en plusieurs mots', () {
      expect(
        composePropertyAddress(
          address: '11 rue des Eglantines',
          postalCode: '95320',
          city: 'Saint Leu la Forêt',
        ),
        '11 rue des Eglantines, 95320 Saint Leu la Forêt',
      );
    });

    test('nettoie les espaces et la virgule finale de la rue', () {
      expect(
        composePropertyAddress(
          address: '  48 avenue du Hazay,  ',
          postalCode: ' 95000 ',
          city: ' Cergy ',
        ),
        '48 avenue du Hazay, 95000 Cergy',
      );
    });
  });

  group('composePropertyAddress — postalCode/city nuls ou vides', () {
    test('rend la rue seule quand les deux sont null', () {
      expect(
        composePropertyAddress(
          address: '48 avenue du Hazay',
          postalCode: null,
          city: null,
        ),
        '48 avenue du Hazay',
      );
    });

    test('rend la rue seule quand les deux champs sont absents', () {
      expect(
        composePropertyAddress(address: '48 avenue du Hazay'),
        '48 avenue du Hazay',
      );
    });

    test('rend la rue seule quand les deux sont des chaînes vides', () {
      expect(
        composePropertyAddress(
          address: '48 avenue du Hazay',
          postalCode: '',
          city: '   ',
        ),
        '48 avenue du Hazay',
      );
    });

    test('ajoute le seul code postal disponible', () {
      expect(
        composePropertyAddress(
          address: '48 avenue du Hazay',
          postalCode: '95000',
          city: null,
        ),
        '48 avenue du Hazay, 95000',
      );
    });

    test('ajoute la seule ville disponible', () {
      expect(
        composePropertyAddress(
          address: '48 avenue du Hazay',
          postalCode: null,
          city: 'Cergy',
        ),
        '48 avenue du Hazay, Cergy',
      );
    });

    test('ne rend pas une chaîne vide si la rue manque mais pas le reste', () {
      expect(
        composePropertyAddress(address: '', postalCode: '95000', city: 'Cergy'),
        '95000 Cergy',
      );
    });

    test('rend une chaîne vide si tout manque', () {
      expect(
        composePropertyAddress(address: null, postalCode: null, city: null),
        '',
      );
    });
  });

  group('composePropertyAddress — adresse contenant déjà les composants', () {
    test('n\'ajoute rien si la rue porte déjà code postal ET ville', () {
      expect(
        composePropertyAddress(
          address: '48 avenue du Hazay, 95000 Cergy',
          postalCode: '95000',
          city: 'Cergy',
        ),
        '48 avenue du Hazay, 95000 Cergy',
      );
    });

    test(
      'colle la ville derrière un code postal déjà présent en fin de rue',
      () {
        expect(
          composePropertyAddress(
            address: '48 avenue du Hazay, 95000',
            postalCode: '95000',
            city: 'Cergy',
          ),
          '48 avenue du Hazay, 95000 Cergy',
        );
      },
    );

    test(
      'insère le code postal devant une ville déjà présente en fin de rue',
      () {
        expect(
          composePropertyAddress(
            address: '48 avenue du Hazay, Cergy',
            postalCode: '95000',
            city: 'Cergy',
          ),
          '48 avenue du Hazay, 95000 Cergy',
        );
      },
    );

    test('ignore la casse et les accents pour détecter la ville', () {
      expect(
        composePropertyAddress(
          address: '11 rue des Eglantines, SAINT-LEU-LA-FORET',
          postalCode: '95320',
          city: 'Saint Leu la Forêt',
        ),
        '11 rue des Eglantines, 95320 SAINT-LEU-LA-FORET',
      );
    });

    test('ne duplique pas une ville citée en milieu d\'adresse', () {
      expect(
        composePropertyAddress(
          address: '48 avenue du Hazay, Cergy, France',
          postalCode: null,
          city: 'Cergy',
        ),
        '48 avenue du Hazay, Cergy, France',
      );
    });

    test(
      'ajoute le code postal en fin si la ville n\'est pas en position finale',
      () {
        expect(
          composePropertyAddress(
            address: '48 avenue du Hazay, Cergy, France',
            postalCode: '95000',
            city: 'Cergy',
          ),
          '48 avenue du Hazay, Cergy, France, 95000',
        );
      },
    );
  });

  group('composePropertyAddress — pas de faux positifs de détection', () {
    test('« Cergy » ne matche pas « Cergy-Pontoise » par préfixe', () {
      expect(
        composePropertyAddress(
          address: '48 avenue du Hazay, Cergy-Pontoise',
          postalCode: '95000',
          city: 'Cergy',
        ),
        '48 avenue du Hazay, Cergy-Pontoise, 95000 Cergy',
      );
    });

    test(
      'un numéro de rue qui contient le code postal ne le fait pas passer',
      () {
        expect(
          composePropertyAddress(
            address: '950001 avenue du Hazay',
            postalCode: '95000',
            city: 'Cergy',
          ),
          '950001 avenue du Hazay, 95000 Cergy',
        );
      },
    );

    test(
      'un code postal identique à un numéro de rue isolé est bien détecté',
      () {
        // Limite assumée : « 95000 » en tête est un vrai numéro de rue, mais la
        // détection est purement lexicale. On documente le comportement plutôt
        // que de prétendre le contraire.
        expect(
          composePropertyAddress(
            address: '95000 avenue du Hazay',
            postalCode: '95000',
            city: 'Cergy',
          ),
          '95000 avenue du Hazay, Cergy',
        );
      },
    );
  });
}
