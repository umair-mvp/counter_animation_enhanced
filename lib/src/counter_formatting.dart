/// Pure, geometry-free translation of a number into the strip of cells the
/// counter renders: whole/pad clamping, fixed-decimal formatting, digit-group
/// separators and the place-keyed cell list.
///
/// Every cell is keyed by its distance from the right edge, so a column that
/// gains a place moves instead of remounting, and a column that is already on
/// screen keeps its wheel position while the text around it changes.
library;

/// Maximum number of decimal places, mirroring `Number.toFixed`.
const int maxDecimals = 15;

/// Maximum total width in digits, so a runaway `padStart` cannot build an
/// absurd number of columns.
const int maxPad = 24;

/// Shortest roll, in seconds.
const double minDuration = 0.01;

/// Longest roll, in seconds.
const double maxDuration = 60;

/// Largest integer JavaScript (and therefore this formatter) can count
/// exactly: past it the low digits are noise.
const int maxSafeInteger = 9007199254740991;

/// How [AnimatedCounter] inserts [separator] between groups of digits.
enum CounterGrouping {
  /// `1,234,567` — groups of three from the right.
  western,

  /// `12,34,567` — three at the end, pairs the rest of the way up.
  indian,

  /// `1234567` — no grouping at all.
  none,
}

double _clampDouble(double value, double low, double high) =>
    value.isFinite ? (value < low ? low : (value > high ? high : value)) : low;

int _clampInt(double value, int low, int high) {
  if (!value.isFinite) return low;
  final int truncated = value.truncate();
  return truncated < low ? low : (truncated > high ? high : truncated);
}

/// The shape of a rendered value: how wide the strip is and where the decimal
/// mark sits. Immutable, so a widget can compare two of them cheaply.
class CounterShape {
  /// Creates a shape. Normally obtained from [measureCounter].
  const CounterShape({
    required this.amount,
    required this.scaled,
    required this.places,
    required this.pace,
    required this.width,
  });

  /// The value being shown, with `NaN`/`Infinity` folded onto zero.
  final double amount;

  /// [amount] times 10<sup>places</sup>, absolute and rounded: the digits the
  /// wheels actually hold.
  final int scaled;

  /// Number of decimal places.
  final int places;

  /// Roll length in seconds, already clamped to ([minDuration], [maxDuration]).
  final double pace;

  /// Total number of digit columns, `places + padStart` at the very least.
  final int width;

  /// True when the wheels should sit on the minus face of the sign column.
  bool get isNegative => amount < 0 && scaled > 0;

  @override
  bool operator ==(Object other) =>
      other is CounterShape &&
      other.amount == amount &&
      other.scaled == scaled &&
      other.places == places &&
      other.pace == pace &&
      other.width == width;

  @override
  int get hashCode => Object.hash(amount, scaled, places, pace, width);

  @override
  String toString() =>
      'CounterShape(amount: $amount, scaled: $scaled, places: $places, '
      'pace: $pace, width: $width)';
}

/// Reduces [value] plus the caller's formatting wishes into a [CounterShape].
///
/// A `NaN` or `Infinity` [value] would make every later comparison against the
/// previous value true, so it is folded onto zero. Digits beyond
/// [maxSafeInteger] are noise, and past 1e21 the string form turns exponential,
/// so the scaled amount is capped.
CounterShape measureCounter(
  double value,
  int decimals,
  int padStart,
  double duration,
) {
  final double amount = value.isFinite ? value : 0;
  final int places = _clampInt(decimals.toDouble(), 0, maxDecimals);
  final int pad = _clampInt(padStart.toDouble(), 1, maxPad);
  // Round half away from zero, exactly like Math.round on an absolute value.
  final double scaledUp = (amount * _powTen(places)).abs().roundToDouble();
  // Past maxSafeInteger the low digits are noise, so the cap keeps them out of
  // the wheels entirely.
  final int scaled = scaledUp > maxSafeInteger
      ? maxSafeInteger
      : scaledUp.toInt();
  final int digits = scaled.toString().length;

  return CounterShape(
    amount: amount,
    scaled: scaled,
    places: places,
    pace: _clampDouble(duration, minDuration, maxDuration),
    width: _max(digits, places + pad),
  );
}

/// The plain digit string of [shape], with [separator] between groups and
/// [decimalSeparator] before the fractional part.
String formatCounter(
  CounterShape shape,
  String separator,
  String decimalSeparator,
  CounterGrouping grouping,
) {
  // width is at least places + 1, so there is always a whole part.
  final String raw = shape.scaled.toString().padLeft(shape.width, '0');
  final int split = raw.length - shape.places;
  final String whole = groupDigits(raw.substring(0, split), separator, grouping);
  if (shape.places == 0) return whole;
  return '$whole$decimalSeparator${raw.substring(split)}';
}

/// Inserts [separator] every three digits from the right ([CounterGrouping
/// .western]), every two above the last three ([CounterGrouping.indian]), or
/// nowhere ([CounterGrouping.none] / an empty [separator]).
String groupDigits(String whole, String separator, CounterGrouping grouping) {
  if (separator.isEmpty || grouping == CounterGrouping.none) return whole;

  final int length = whole.length;
  // Indian grouping keeps the last three together and pairs everything above
  // them, so the stride only applies to the head.
  final int stride = grouping == CounterGrouping.indian ? 2 : 3;
  final int head = grouping == CounterGrouping.indian
      ? (length > 3 ? length - 3 : 0)
      : length;

  final StringBuffer out = StringBuffer();
  for (int index = 0; index < length; index++) {
    if (index > 0 && index <= head && (head - index) % stride == 0) {
      out.write(separator);
    }
    out.write(whole[index]);
  }
  return out.toString();
}

/// One column of the rendered strip.
sealed class CounterCell {
  /// Creates a cell. Produced by [toCells].
  const CounterCell({required this.key});

  /// Stable identity, counted in places from the right edge of the strip, so
  /// growing the number moves columns rather than remounting them.
  final Object key;
}

/// A column holding a rolling digit wheel.
final class CounterDigitCell extends CounterCell {
  /// Creates a digit column.
  const CounterDigitCell({required super.key, required this.digit});

  /// The face the wheel rests on, `0` through `9`.
  final int digit;

  @override
  bool operator ==(Object other) =>
      other is CounterDigitCell &&
      other.key == key &&
      other.digit == digit;

  @override
  int get hashCode => Object.hash(key, digit);

  @override
  String toString() => 'CounterDigitCell(key: $key, digit: $digit)';
}

/// A column holding a static character: a group separator, the decimal mark or
/// the minus sign.
final class CounterMarkCell extends CounterCell {
  /// Creates a mark column.
  const CounterMarkCell({required super.key, required this.char});

  /// The character to show.
  final String char;

  @override
  bool operator ==(Object other) =>
      other is CounterMarkCell && other.key == key && other.char == char;

  @override
  int get hashCode => Object.hash(key, char);

  @override
  String toString() => 'CounterMarkCell(key: $key, char: $char)';
}

/// Splits the formatted string into columns.
///
/// Only digits advance the place count, and consecutive marks step aside with a
/// run index, so even a multi-character separator gets unique keys.
List<CounterCell> toCells(String chars, int width) {
  final List<CounterCell> cells = <CounterCell>[];
  int seen = 0;
  int run = 0;

  for (final String char in chars.split('')) {
    final int code = char.codeUnitAt(0);
    if (code >= 0x30 && code <= 0x39) {
      run = 0;
      cells.add(CounterDigitCell(key: width - seen, digit: code - 0x30));
      seen++;
    } else {
      cells.add(
        CounterMarkCell(key: 'mark-${width - seen}-${run++}', char: char),
      );
    }
  }
  return cells;
}

double _powTen(int places) {
  double result = 1;
  for (int index = 0; index < places; index++) {
    result *= 10;
  }
  return result;
}

int _max(int a, int b) => a > b ? a : b;

/// `((n % m) + m) % m`, so negative positions wrap onto the same face as their
/// positive counterpart.
double wrap(double value, double modulus) {
  final double wrapped = value % modulus;
  return wrapped < 0 ? wrapped + modulus : wrapped;
}

/// Where to aim a ten-face wheel sitting at [at], so that it ends up showing
/// [face] by the shortest route in the current direction of travel.
///
/// The aim is kept an absolute distance rather than a face, and is always within
/// one turn away, so a value that keeps changing queues up turns instead of
/// falling behind. With [backwards] the wheel turns down through the lower
/// faces; otherwise it turns up.
double aimWheel({
  required double at,
  required double face,
  required bool backwards,
}) {
  return backwards
      ? at - wrap(at - face, wheelPlaces)
      : at + wrap(face - at, wheelPlaces);
}

/// Faces on one wheel.
const double wheelPlaces = 10;
