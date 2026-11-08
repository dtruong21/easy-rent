/// Type d'état des lieux (loi 6/7/1989 : à l'entrée ET à la sortie).
enum EtatDesLieuxType {
  entree('entree'),
  sortie('sortie');

  const EtatDesLieuxType(this.sqlValue);
  final String sqlValue;

  static EtatDesLieuxType fromSql(String value) =>
      EtatDesLieuxType.values.firstWhere((t) => t.sqlValue == value);
}

/// État d'un élément constaté (échelle usuelle des EDL).
enum EdlCondition {
  neuf('neuf'),
  bon('bon'),
  moyen('moyen'),
  mauvais('mauvais');

  const EdlCondition(this.sqlValue);
  final String sqlValue;

  static EdlCondition fromSql(String value) =>
      EdlCondition.values.firstWhere((c) => c.sqlValue == value);
}
