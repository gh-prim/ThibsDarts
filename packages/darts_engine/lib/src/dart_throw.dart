/// Une fléchette détectée (ou saisie à la main).
class DartThrow {
  /// 1 à 20, 25 pour le bull, 0 pour hors cible.
  final int sector;

  /// 1 simple, 2 double, 3 triple. Le bull n'existe qu'en 1 (25) et 2 (50).
  final int multiplier;

  const DartThrow(this.sector, [this.multiplier = 1])
      : assert(sector == 0 || sector == 25 || (sector >= 1 && sector <= 20)),
        assert(multiplier >= 1 && multiplier <= 3),
        assert(sector != 25 || multiplier <= 2);

  const DartThrow.miss() : this(0);
  const DartThrow.single(int s) : this(s, 1);
  const DartThrow.double(int s) : this(s, 2);
  const DartThrow.triple(int s) : this(s, 3);
  static const bull = DartThrow(25, 2);
  static const outerBull = DartThrow(25, 1);

  int get score => sector * multiplier;
  bool get isMiss => sector == 0;
  bool get isDouble => multiplier == 2 && sector != 0;

  /// Libellé court : T20, D16, S5, BULL, 25, MISS.
  String get label {
    if (isMiss) return 'MISS';
    if (sector == 25) return multiplier == 2 ? 'BULL' : '25';
    return '${const ['S', 'D', 'T'][multiplier - 1]}$sector';
  }

  /// Libellé pour l'animation : "TRIPLE 20".
  String get callout {
    if (isMiss) return 'HORS CIBLE';
    if (sector == 25) return multiplier == 2 ? 'BULL' : 'SIMPLE BULL';
    return '${const ['SIMPLE', 'DOUBLE', 'TRIPLE'][multiplier - 1]} $sector';
  }

  @override
  bool operator ==(Object other) =>
      other is DartThrow &&
      other.sector == sector &&
      other.multiplier == multiplier;

  @override
  int get hashCode => Object.hash(sector, multiplier);

  @override
  String toString() => label;
}
