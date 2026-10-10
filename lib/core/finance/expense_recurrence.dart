/// Périodicité d'une dépense — **récurrence virtuelle** (FEAT-041d).
///
/// Aucune dépendance Flutter ni Firebase : ce module est le calendrier pur
/// consommé par `profitability.dart` (cash flow), le graphique mensuel du
/// dashboard et les totaux de la fiche bien. Le pendant « présentation »
/// (libellés localisés) vit dans
/// `features/expenses/presentation/expense_recurrence_l10n.dart`.
///
/// ## Pourquoi virtuel plutôt que généré
///
/// Une dépense qui revient (charges de copropriété trimestrielles, assurance
/// annuelle, mensualité de crédit) porte une périodicité et **compte
/// automatiquement dans chaque période concernée sans créer un seul document
/// Firestore**. L'alternative — une fonction planifiée qui matérialise une
/// écriture par échéance — a été écartée : elle coûte un cron, des écritures,
/// des quotas, et surtout elle oblige à rattraper tout l'historique dès que
/// le montant est corrigé (le syndic révise les charges → il faudrait
/// réécrire N documents déjà générés). Ici, corriger le montant d'une ligne
/// corrige instantanément toutes ses échéances, passées comme à venir.
///
/// ## Décision 1 — la borne de fin
///
/// La fin est une **date optionnelle portée par la dépense**
/// ([recurrenceEndDate] côté modèle), pas un rattachement au bail.
///
/// Rattacher la récurrence au bail serait faux pour les charges qui
/// justement récurrent : taxe foncière, assurance PNO et charges de
/// copropriété sont dues par le **propriétaire**, locataire ou pas. Les
/// arrêter à la fin du bail effacerait ces charges pendant une vacance
/// locative — exactement le moment où le cash flow du bailleur se dégrade et
/// où il a le plus besoin d'un chiffre juste. De plus `leaseId` est
/// optionnel sur une dépense (le décompte syndic n'en a le plus souvent
/// aucun) : la majorité des récurrences n'aurait aucune borne du tout.
///
/// Une récurrence sans date de fin n'est pas pour autant infinie : toutes
/// les expansions sont bornées par une fenêtre `[from, to]` fournie par
/// l'appelant, et aucun appelant ne demande au-delà du mois courant. Une
/// récurrence ouverte compte donc jusqu'à aujourd'hui, jamais au-delà — on
/// ne projette pas des charges dans le futur.
///
/// Reste le cas de la vente du bien : archiver le bien (soft-delete) sort
/// ses dépenses de toutes les agrégations, récurrentes comprises, sans que
/// la récurrence ait à connaître quoi que ce soit du cycle de vie du bien.
///
/// ## Décision 2 — le passé
///
/// **Une récurrence ne compte jamais avant sa première échéance**, et la
/// première échéance est la date de la dépense elle-même. Saisir aujourd'hui
/// « 150 € par trimestre » ne remplit pas rétroactivement les trimestres
/// écoulés.
///
/// Deux raisons décisives :
///
/// 1. **Le double comptage.** Un bailleur qui a saisi ses décomptes syndic
///    un par un depuis janvier, puis bascule la ligne de septembre en
///    « tous les trimestres », verrait janvier et avril comptés deux fois —
///    une fois par la ligne réelle, une fois par l'échéance virtuelle. Le
///    graphique deviendrait faux sur des mois que l'utilisateur a déjà
///    regardés.
/// 2. **Rien n'est perdu.** La rétroactivité reste accessible sans concept
///    supplémentaire : il suffit de dater la dépense au premier versement
///    réel. Le champ existe déjà, il est déjà nommé « date de la dépense »,
///    et son effet est visible immédiatement. La règle tient en une phrase
///    affichable : « la première échéance est la date de la dépense ».
library;

/// Périodicité d'une dépense. [none] = écriture ponctuelle (comportement
/// historique, valeur par défaut des dépenses créées avant FEAT-041d).
enum ExpenseRecurrence {
  /// Dépense ponctuelle — une seule échéance, à sa date.
  none,

  /// Tous les mois (mensualité de crédit, provision mensuelle).
  monthly,

  /// Tous les trimestres (appel de charges de copropriété).
  quarterly,

  /// Tous les ans (assurance PNO, taxe foncière).
  yearly;

  /// Valeur attendue par la Cloud Function / stockée sur le document
  /// Firestore (champ `recurrence`).
  String get sqlValue => switch (this) {
    ExpenseRecurrence.none => 'none',
    ExpenseRecurrence.monthly => 'monthly',
    ExpenseRecurrence.quarterly => 'quarterly',
    ExpenseRecurrence.yearly => 'yearly',
  };

  /// Pas de la récurrence, en mois. `0` pour [none] (jamais itérée).
  int get monthStep => switch (this) {
    ExpenseRecurrence.none => 0,
    ExpenseRecurrence.monthly => 1,
    ExpenseRecurrence.quarterly => 3,
    ExpenseRecurrence.yearly => 12,
  };

  /// Nombre d'échéances sur douze mois. `0` pour [none] : une dépense
  /// ponctuelle n'a pas de rythme annuel, elle a une date.
  int get occurrencesPerYear => switch (this) {
    ExpenseRecurrence.none => 0,
    ExpenseRecurrence.monthly => 12,
    ExpenseRecurrence.quarterly => 4,
    ExpenseRecurrence.yearly => 1,
  };

  /// Vrai si la dépense revient (tout sauf [none]).
  bool get isRecurring => this != ExpenseRecurrence.none;

  /// Construit une [ExpenseRecurrence] depuis la valeur serveur.
  ///
  /// `null` (dépense créée avant FEAT-041d — aucune migration n'a été faite,
  /// délibérément) et toute valeur inconnue retombent sur [none] : une
  /// dépense sans périodicité connue reste ponctuelle, jamais dupliquée par
  /// accident.
  static ExpenseRecurrence fromSql(String? value) => switch (value) {
    'monthly' => ExpenseRecurrence.monthly,
    'quarterly' => ExpenseRecurrence.quarterly,
    'yearly' => ExpenseRecurrence.yearly,
    _ => ExpenseRecurrence.none,
  };
}

/// Échéances d'une dépense tombant dans `[from, to]` (bornes incluses).
///
/// - [firstOccurrence] est la **première** échéance (la date de la dépense) :
///   aucune échéance n'est produite avant elle, même si [from] est
///   antérieur (cf. « Décision 2 » en tête de fichier).
/// - [endDate] (optionnel) borne la récurrence : aucune échéance après
///   elle. Ignoré si [recurrence] vaut [ExpenseRecurrence.none].
/// - [to] borne l'expansion côté appelant : c'est lui, et lui seul, qui
///   décide jusqu'où on projette (fenêtre glissante de 12 mois, dernier mois
///   affiché du graphique...). Une récurrence sans [endDate] s'arrête donc
///   toujours à [to].
///
/// Le jour du mois est **conservé et rogné** au dernier jour du mois cible :
/// une dépense du 31 janvier produit le 28 (ou 29) février, puis le 31 mars.
/// Sans ce rognage, `DateTime(2026, 2, 31)` normaliserait en 3 mars et la
/// dépense sauterait février pour compter deux fois en mars.
///
/// Le fuseau de [firstOccurrence] est préservé (les dates relues de
/// Firestore sont en UTC).
List<DateTime> expenseOccurrences({
  required DateTime firstOccurrence,
  required ExpenseRecurrence recurrence,
  DateTime? endDate,
  required DateTime from,
  required DateTime to,
}) {
  if (to.isBefore(from)) return const [];

  if (!recurrence.isRecurring) {
    final outOfWindow =
        firstOccurrence.isBefore(from) || firstOccurrence.isAfter(to);
    return outOfWindow ? const [] : [firstOccurrence];
  }

  final last = (endDate != null && endDate.isBefore(to)) ? endDate : to;
  final step = recurrence.monthStep;
  final occurrences = <DateTime>[];
  // Terminaison garantie : `_addMonths` est strictement croissant pour
  // `step >= 1`, et `last` est fini.
  for (var index = 0; ; index++) {
    final occurrence = _addMonths(firstOccurrence, step * index);
    if (occurrence.isAfter(last)) break;
    if (!occurrence.isBefore(from)) occurrences.add(occurrence);
  }
  return occurrences;
}

/// Vrai si la récurrence est **en cours** à l'instant [at] : sa première
/// échéance est passée et sa date de fin, si elle existe, ne l'est pas
/// encore.
///
/// Une dépense ponctuelle n'est jamais « en cours » — elle a eu lieu.
bool isRecurrenceActiveAt({
  required DateTime firstOccurrence,
  required ExpenseRecurrence recurrence,
  DateTime? endDate,
  required DateTime at,
}) {
  if (!recurrence.isRecurring) return false;
  if (firstOccurrence.isAfter(at)) return false;
  return endDate == null || !endDate.isBefore(at);
}

/// Ajoute [months] mois à [anchor] en rognant le jour au dernier jour du
/// mois cible (voir [expenseOccurrences]).
DateTime _addMonths(DateTime anchor, int months) {
  if (months == 0) return anchor;
  final shifted = anchor.month - 1 + months;
  final year = anchor.year + shifted ~/ 12;
  final month = shifted % 12 + 1;
  final day = anchor.day <= _daysInMonth(year, month)
      ? anchor.day
      : _daysInMonth(year, month);
  return anchor.isUtc
      ? DateTime.utc(
          year,
          month,
          day,
          anchor.hour,
          anchor.minute,
          anchor.second,
          anchor.millisecond,
          anchor.microsecond,
        )
      : DateTime(
          year,
          month,
          day,
          anchor.hour,
          anchor.minute,
          anchor.second,
          anchor.millisecond,
          anchor.microsecond,
        );
}

/// Nombre de jours du mois [month] de l'année [year] (jour 0 du mois suivant
/// = dernier jour du mois courant).
int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;
