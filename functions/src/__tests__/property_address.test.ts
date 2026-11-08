/**
 * composePropertyAddress — composition de l'adresse complète d'un bien.
 *
 * Fonction pure, aucun mock : ni Firestore, ni firebase-admin.
 *
 * ⚠️ Ces cas sont MIROIR de `test/unit/property_address_test.dart`. Toute
 * modification ici doit être répercutée là-bas (et réciproquement) : le
 * serveur fige la valeur sur le bail, le client affiche la même chose depuis
 * le bien — une divergence produirait deux adresses différentes pour le même
 * logement.
 */

import {describe, expect, it} from "vitest";

import {composePropertyAddress} from "../utils/property_address";

describe("composePropertyAddress — champs séparés renseignés", () => {
  it("compose rue + code postal + ville (cas nominal du formulaire)", () => {
    expect(
      composePropertyAddress({
        address: "48 avenue du Hazay",
        postalCode: "95000",
        city: "Cergy",
      }),
    ).toBe("48 avenue du Hazay, 95000 Cergy");
  });

  it("compose une ville en plusieurs mots", () => {
    expect(
      composePropertyAddress({
        address: "11 rue des Eglantines",
        postalCode: "95320",
        city: "Saint Leu la Forêt",
      }),
    ).toBe("11 rue des Eglantines, 95320 Saint Leu la Forêt");
  });

  it("nettoie les espaces et la virgule finale de la rue", () => {
    expect(
      composePropertyAddress({
        address: "  48 avenue du Hazay,  ",
        postalCode: " 95000 ",
        city: " Cergy ",
      }),
    ).toBe("48 avenue du Hazay, 95000 Cergy");
  });

  it("accepte un code postal stocké comme nombre", () => {
    expect(
      composePropertyAddress({
        address: "48 avenue du Hazay",
        postalCode: 95000,
        city: "Cergy",
      }),
    ).toBe("48 avenue du Hazay, 95000 Cergy");
  });
});

describe("composePropertyAddress — postalCode/city nuls ou vides", () => {
  it("rend la rue seule quand les deux sont null", () => {
    expect(
      composePropertyAddress({
        address: "48 avenue du Hazay",
        postalCode: null,
        city: null,
      }),
    ).toBe("48 avenue du Hazay");
  });

  it("rend la rue seule quand les deux champs sont absents", () => {
    expect(composePropertyAddress({address: "48 avenue du Hazay"})).toBe(
      "48 avenue du Hazay",
    );
  });

  it("rend la rue seule quand les deux sont des chaînes vides", () => {
    expect(
      composePropertyAddress({
        address: "48 avenue du Hazay",
        postalCode: "",
        city: "   ",
      }),
    ).toBe("48 avenue du Hazay");
  });

  it("ajoute le seul code postal disponible", () => {
    expect(
      composePropertyAddress({
        address: "48 avenue du Hazay",
        postalCode: "95000",
        city: null,
      }),
    ).toBe("48 avenue du Hazay, 95000");
  });

  it("ajoute la seule ville disponible", () => {
    expect(
      composePropertyAddress({
        address: "48 avenue du Hazay",
        postalCode: null,
        city: "Cergy",
      }),
    ).toBe("48 avenue du Hazay, Cergy");
  });

  it("ne rend pas une chaîne vide si la rue manque mais pas le reste", () => {
    expect(
      composePropertyAddress({
        address: "",
        postalCode: "95000",
        city: "Cergy",
      }),
    ).toBe("95000 Cergy");
  });

  it("rend une chaîne vide si tout manque", () => {
    expect(
      composePropertyAddress({address: null, postalCode: null, city: null}),
    ).toBe("");
  });
});

describe("composePropertyAddress — adresse contenant déjà les composants", () => {
  it("n'ajoute rien si la rue porte déjà code postal ET ville", () => {
    expect(
      composePropertyAddress({
        address: "48 avenue du Hazay, 95000 Cergy",
        postalCode: "95000",
        city: "Cergy",
      }),
    ).toBe("48 avenue du Hazay, 95000 Cergy");
  });

  it("colle la ville derrière un code postal déjà présent en fin de rue", () => {
    expect(
      composePropertyAddress({
        address: "48 avenue du Hazay, 95000",
        postalCode: "95000",
        city: "Cergy",
      }),
    ).toBe("48 avenue du Hazay, 95000 Cergy");
  });

  it("insère le code postal devant une ville déjà présente en fin de rue", () => {
    expect(
      composePropertyAddress({
        address: "48 avenue du Hazay, Cergy",
        postalCode: "95000",
        city: "Cergy",
      }),
    ).toBe("48 avenue du Hazay, 95000 Cergy");
  });

  it("ignore la casse et les accents pour détecter la ville", () => {
    expect(
      composePropertyAddress({
        address: "11 rue des Eglantines, SAINT-LEU-LA-FORET",
        postalCode: "95320",
        city: "Saint Leu la Forêt",
      }),
    ).toBe("11 rue des Eglantines, 95320 SAINT-LEU-LA-FORET");
  });

  it("ne duplique pas une ville citée en milieu d'adresse", () => {
    expect(
      composePropertyAddress({
        address: "48 avenue du Hazay, Cergy, France",
        postalCode: null,
        city: "Cergy",
      }),
    ).toBe("48 avenue du Hazay, Cergy, France");
  });

  it("ajoute le code postal en fin si la ville n'est pas en position finale", () => {
    expect(
      composePropertyAddress({
        address: "48 avenue du Hazay, Cergy, France",
        postalCode: "95000",
        city: "Cergy",
      }),
    ).toBe("48 avenue du Hazay, Cergy, France, 95000");
  });
});

describe("composePropertyAddress — pas de faux positifs de détection", () => {
  it("« Cergy » ne matche pas « Cergy-Pontoise » par préfixe", () => {
    expect(
      composePropertyAddress({
        address: "48 avenue du Hazay, Cergy-Pontoise",
        postalCode: "95000",
        city: "Cergy",
      }),
    ).toBe("48 avenue du Hazay, Cergy-Pontoise, 95000 Cergy");
  });

  it("un numéro de rue qui contient le code postal ne le fait pas passer", () => {
    expect(
      composePropertyAddress({
        address: "950001 avenue du Hazay",
        postalCode: "95000",
        city: "Cergy",
      }),
    ).toBe("950001 avenue du Hazay, 95000 Cergy");
  });

  it("un code postal identique à un numéro de rue isolé est bien détecté", () => {
    // Limite assumée : « 95000 » en tête est un vrai numéro de rue, mais la
    // détection est purement lexicale. On documente le comportement plutôt
    // que de prétendre le contraire.
    expect(
      composePropertyAddress({
        address: "95000 avenue du Hazay",
        postalCode: "95000",
        city: "Cergy",
      }),
    ).toBe("95000 avenue du Hazay, Cergy");
  });
});
