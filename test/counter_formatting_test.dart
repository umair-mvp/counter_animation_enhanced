import 'package:counter_animation_enhanced/counter_animation_enhanced.dart';
import 'package:flutter_test/flutter_test.dart';

/// The React original, for reference:
///
/// ```js
/// measure(value, decimals, padStart, duration)
/// format({scaled, places, width}, separator, decimalSeparator, grouping)
/// toCells(chars, width)
/// ```
void main() {
  group('measureCounter', () {
    test('scales by the decimals and counts the digits', () {
      final CounterShape shape = measureCounter(12.375, 2, 1, 0.6);
      expect(shape.amount, 12.375);
      expect(shape.places, 2);
      // Rounds half away from zero, like Math.round on the absolute value.
      expect(shape.scaled, 1238);
      expect(shape.width, 4);
      expect(shape.pace, 0.6);
    });

    test('folds NaN and infinity onto zero', () {
      for (final double value in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        final CounterShape shape = measureCounter(value, 0, 1, 0.6);
        expect(shape.amount, 0, reason: '$value');
        expect(shape.scaled, 0, reason: '$value');
        expect(shape.isNegative, isFalse, reason: '$value');
      }
    });

    test('keeps the sign only when there are digits to sign', () {
      expect(measureCounter(-0.004, 2, 1, 0.6).isNegative, isFalse);
      expect(measureCounter(-0.005, 2, 1, 0.6).isNegative, isTrue);
      expect(measureCounter(-12, 0, 1, 0.6).isNegative, isTrue);
    });

    test('clamps decimals, pad and duration', () {
      final CounterShape shape = measureCounter(0, 99, 99, 1000);
      expect(shape.places, maxDecimals);
      expect(shape.width, maxDecimals + maxPad);
      expect(shape.pace, maxDuration);

      expect(measureCounter(1, 0, 1, -5).pace, minDuration);
      expect(measureCounter(1, -3, 0, 0.6).places, 0);
      expect(measureCounter(1, 0, -3, 0.6).width, 1);
    });

    test('holds the whole-number width a pad asks for', () {
      expect(measureCounter(42, 0, 5, 0.6).width, 5);
      expect(measureCounter(42, 2, 1, 0.6).width, 4);
    });

    test('caps at the largest safe integer', () {
      final CounterShape shape = measureCounter(1e30, 0, 1, 0.6);
      expect(shape.scaled, maxSafeInteger);
      expect(shape.width, '$maxSafeInteger'.length);
    });
  });

  group('groupDigits', () {
    test('groups by threes from the right', () {
      expect(groupDigits('1234', ',', CounterGrouping.western), '1,234');
      expect(groupDigits('1234567', ',', CounterGrouping.western), '1,234,567');
      expect(groupDigits('123', ',', CounterGrouping.western), '123');
      expect(groupDigits('12', ',', CounterGrouping.western), '12');
      expect(groupDigits('0', ',', CounterGrouping.western), '0');
    });

    test('groups by threes then twos for india', () {
      expect(groupDigits('1234', ',', CounterGrouping.indian), '1,234');
      expect(groupDigits('12345', ',', CounterGrouping.indian), '12,345');
      expect(groupDigits('123456', ',', CounterGrouping.indian), '1,23,456');
      expect(
        groupDigits('12345678', ',', CounterGrouping.indian),
        '1,23,45,678',
      );
      expect(groupDigits('123', ',', CounterGrouping.indian), '123');
    });

    test('does nothing without a separator or grouping', () {
      expect(groupDigits('1234567', ',', CounterGrouping.none), '1234567');
      expect(groupDigits('1234567', '', CounterGrouping.western), '1234567');
    });
  });

  group('formatCounter', () {
    String said(
      double value, {
      int decimals = 0,
      int padStart = 1,
      String separator = ',',
      String decimalSeparator = '.',
      CounterGrouping grouping = CounterGrouping.western,
    }) {
      return formatCounter(
        measureCounter(value, decimals, padStart, 0.6),
        separator,
        decimalSeparator,
        grouping,
      );
    }

    test('says a plain number', () {
      expect(said(0), '0');
      expect(said(1234), '1,234');
      expect(said(1234.5, decimals: 1), '1,234.5');
      expect(said(1234.5, decimals: 2), '1,234.50');
    });

    test('pads with leading zeros', () {
      expect(said(7, padStart: 3), '007');
      expect(said(7, decimals: 2, padStart: 2), '07.00');
    });

    test('keeps a zero whole part', () {
      expect(said(0.25, decimals: 2), '0.25');
      expect(said(0.259, decimals: 2), '0.26');
    });

    test('swaps the separators over', () {
      expect(
        said(1234.5,
            decimals: 1, separator: '.', decimalSeparator: ','),
        '1.234,5',
      );
      expect(said(1234, separator: ' '), '1 234');
      expect(said(1234, separator: ''), '1234');
      expect(said(12345678, grouping: CounterGrouping.indian), '1,23,45,678');
      expect(said(12345678, grouping: CounterGrouping.none), '12345678');
    });

    test('leaves the sign to the caller', () {
      expect(said(-1234.5, decimals: 1), '1,234.5');
    });
  });

  group('toCells', () {
    test('keys digits by their place from the right', () {
      final List<CounterCell> cells = toCells('1,234.5', 5);
      expect(
        cells.whereType<CounterDigitCell>().map((CounterCell c) => c.key),
        <Object>[5, 4, 3, 2, 1],
      );
      expect(
        cells.whereType<CounterDigitCell>().map((CounterCell c) {
          return (c as CounterDigitCell).digit;
        }),
        <int>[1, 2, 3, 4, 5],
      );
    });

    test('keys marks by the place they sit after, and their run', () {
      final List<CounterCell> cells = toCells('1,234.5', 5);
      final List<CounterMarkCell> marks =
          cells.whereType<CounterMarkCell>().toList();
      expect(marks.map((CounterMarkCell c) => c.key), <Object>[
        'mark-4-0',
        'mark-1-0',
      ]);
      expect(marks.map((CounterMarkCell c) => c.char), <String>[',', '.']);
    });

    test('keeps a multi-character separator unique', () {
      final List<CounterCell> cells = toCells('1..2', 2);
      expect(
        cells.map((CounterCell c) => c.key),
        <Object>[2, 'mark-1-0', 'mark-1-1', 1],
      );
    });

    test('formats and splits the same way all the time', () {
      final CounterShape shape = measureCounter(9876543.21, 2, 1, 0.6);
      final String chars =
          formatCounter(shape, ',', '.', CounterGrouping.western);
      expect(chars, '9,876,543.21');
      expect(toCells(chars, shape.width).length, chars.length);
    });
  });

  group('aimWheel', () {
    test('always turns up, the way the faces climb', () {
      // Forward travel is mod(face - at, 10), so "up" can be the long way.
      expect(aimWheel(at: 0, face: 1, backwards: false), 1);
      expect(aimWheel(at: 3, face: 2, backwards: false), 12);
      expect(aimWheel(at: 9, face: 0, backwards: false), 10);
    });

    test('always turns down when counting down', () {
      expect(aimWheel(at: 1, face: 0, backwards: true), 0);
      expect(aimWheel(at: 2, face: 3, backwards: true), -7);
      expect(aimWheel(at: 0, face: 9, backwards: true), -1);
    });

    test('aims from where the wheel is, never further than a turn', () {
      for (double at = -20; at <= 20; at += 0.5) {
        for (double face = 0; face < wheelPlaces; face++) {
          for (final bool backwards in <bool>[false, true]) {
            final double goal =
                aimWheel(at: at, face: face, backwards: backwards);
            final double travel = goal - at;
            expect(travel.abs(), lessThan(wheelPlaces));
            if (travel != 0) {
              expect(travel.isNegative, backwards, reason: '$at -> $face');
            }
            expect(
              wrap(goal, wheelPlaces),
              face,
              reason: '$at -> $face $backwards',
            );
          }
        }
      }
    });

    test('lands on the same face the wheel is already heading to', () {
      // Mid-turn at 4.2, still aimed at 5: nothing new to ask for.
      expect(wrap(aimWheel(at: 4.2, face: 5, backwards: false), wheelPlaces), 5);
    });
  });

  group('wrap', () {
    test('folds either direction onto the same face', () {
      expect(wrap(12, wheelPlaces), 2);
      expect(wrap(-1, wheelPlaces), 9);
      expect(wrap(9.5, wheelPlaces), 9.5);
      expect(wrap(10, wheelPlaces), 0);
    });
  });
}
