import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:counter_animation_enhanced/counter_animation_enhanced.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The test font, Ahem, draws every glyph as a full square of the font size, so
/// a column of digits at 10logical pixels is exactly 10 logical pixels wide.
const double _face = 10;
const double _column = 10;
const double _wheel = 15;

/// Rasterises what the strip has just drawn, so a test can look at the wheels
/// without a golden file. Reading pixels needs the real event loop, which is why
/// this runs in [WidgetTester.runAsync] rather than in the fake-async of a
/// widget test.
Future<Uint8List> _pictureOf(WidgetTester tester) async {
  final Uint8List? bytes = await tester.runAsync<Uint8List>(() async {
    final RenderCustomPaint render =
        tester.renderObject<RenderCustomPaint>(find.byType(CustomPaint));
    final Size size = render.size;
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    render.painter!.paint(canvas, size);
    final ui.Picture picture = recorder.endRecording();
    final ui.Image image =
        picture.toImageSync(size.width.round(), size.height.round());
    final ByteData? rgba =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    picture.dispose();
    return rgba!.buffer.asUint8List();
  });
  return bytes!;
}

int _litPixels(Uint8List bytes) {
  int lit = 0;
  for (int i = 3; i < bytes.length; i += 4) {
    if (bytes[i] > 24) lit++;
  }
  return lit;
}

/// Hosts the counter the way an app would: text style, direction and media
/// query, with room enough for a number padded out to 39 columns.
Widget _host(Widget child, {MediaQueryData media = const MediaQueryData()}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: media,
      child: DefaultTextStyle(
        style: const TextStyle(fontSize: _face, color: Color(0xFF000000)),
        child: Center(
          child: OverflowBox(
            maxWidth: 100000,
            maxHeight: 100000,
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('what it says', () {
    testWidgets('reads the number out as plain text', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(
        AnimatedCounter(value: 1234.5, decimals: 2),
      ));
      expect(tester.getSemantics(find.byType(AnimatedCounter)).label,
          '1,234.50');
      handle.dispose();
    });

    testWidgets('includes the sign, and drops it once there are no digits',
        (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(const AnimatedCounter(
        value: -1234.5,
        decimals: 1,
      )));
      expect(tester.getSemantics(find.byType(AnimatedCounter)).label,
          '-1,234.5');

      await tester.pumpWidget(_host(const AnimatedCounter(
        value: -0.004,
        decimals: 2,
      )));
      expect(
          tester.getSemantics(find.byType(AnimatedCounter)).label, '0.00');
      handle.dispose();
    });

    testWidgets('follows the grouping it is given', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(const AnimatedCounter(
        value: 12345678,
        grouping: CounterGrouping.indian,
      )));
      expect(tester.getSemantics(find.byType(AnimatedCounter)).label,
          '1,23,45,678');
      handle.dispose();
    });
  });

  group('what it takes up', () {
    testWidgets('one column per digit, one per mark', (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        const AnimatedCounter(value: 999),
      ));
      expect(tester.getSize(find.byType(AnimatedCounter)), const Size(3 * _column, _wheel));

      await tester.pumpWidget(_host(
        const AnimatedCounter(value: 1000),
      ));
      expect(tester.getSize(find.byType(AnimatedCounter)), const Size(5 * _column, _wheel));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(AnimatedCounter)), const Size(5 * _column, _wheel));
    });

    testWidgets('the wheels are as tall as the line asks', (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        const AnimatedCounter(value: 12, lineHeight: 2),
      ));
      expect(tester.getSize(find.byType(AnimatedCounter)).height, _face * 2);
    });

    testWidgets('prefix and suffix line up beside it', (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        AnimatedCounter(value: 12, prefix: const Text(r'$'), suffix: const Text('%')),
      ));
      expect(tester.getSize(find.byType(AnimatedCounter)), const Size(4 * _column, _wheel));
    });

    testWidgets('the sign costs a column', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const AnimatedCounter(value: 1234)));
      final double unsigned = tester.getSize(find.byType(AnimatedCounter)).width;
      await tester.pumpWidget(_host(const AnimatedCounter(value: -1234)));
      expect(
        tester.getSize(find.byType(AnimatedCounter)).width,
        unsigned + _column,
      );
    });
  });

  group('how it moves', () {
    testWidgets('animates for about as long as it was given', (WidgetTester tester) async {
      const Duration pace = Duration(milliseconds: 600);
      await tester.pumpWidget(_host(AnimatedCounter(value: 0, duration: pace)));
      expect(tester.binding.transientCallbackCount, 0);

      await tester.pumpWidget(_host(AnimatedCounter(value: 1234, duration: pace)));
      await tester.pump();
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      int frames = 0;
      while (tester.binding.transientCallbackCount > 0 && frames < 200) {
        await tester.pump(const Duration(milliseconds: 16));
        frames++;
      }
      expect(tester.binding.transientCallbackCount, 0);
      // Spring timing settles a little after its visible duration, and must not
      // run away either.
      expect(frames, greaterThan(20));
      expect(frames, lessThan(120));
    });

    testWidgets('holds every wheel still when the value does not move',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const AnimatedCounter(value: 1234)));
      await tester.pumpWidget(_host(const AnimatedCounter(value: 1234)));
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('draws part-way through a roll, and lands where it belongs',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const AnimatedCounter(value: 999)));
      final Uint8List before = await _pictureOf(tester);

      await tester.pumpWidget(_host(const AnimatedCounter(value: 1000)));
      await tester.pump(const Duration(milliseconds: 120));
      final Uint8List during = await _pictureOf(tester);

      await tester.pumpAndSettle();
      final Uint8List after = await _pictureOf(tester);

      await tester.pumpWidget(_host(const AnimatedCounter(value: 1000)));
      final Uint8List mounted = await _pictureOf(tester);

      // Mid-roll the strip is its own picture, and settling brings it back to
      // exactly what a counter that never moved would have drawn.
      expect(_same(before, after), isFalse);
      expect(_same(during, after), isFalse);
      expect(_same(after, mounted), isTrue);
    });

    testWidgets('leaves a resting face solid and the air around it clear',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const AnimatedCounter(value: 8)));
      final Uint8List bytes = await _pictureOf(tester);
      final int stride = _column.round() * 4;

      int litInRow(int row) {
        int lit = 0;
        for (int x = 0; x < _column; x++) {
          if (bytes[row * stride + x * 4 + 3] > 200) lit++;
        }
        return lit;
      }

      // The face is a 10px square centred in a 15px wheel box: all of it sits
      // inside the band the mask keeps, so none of it is faded.
      for (int row = 3; row <= 12; row++) {
        expect(litInRow(row), _column.round(), reason: 'row $row');
      }
      for (final int row in <int>[0, 1, 2, 13, 14]) {
        expect(litInRow(row), 0, reason: 'row $row');
      }
    });

    testWidgets('a number that shrinks a place fades the column away',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const AnimatedCounter(value: 1000)));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(AnimatedCounter)), const Size(5 * _column, _wheel));

      // The separator and the extra digit leave the flow; they fade where they
      // stood, and the strip must not be left holding a track that never ends.
      await tester.pumpWidget(_host(const AnimatedCounter(value: 999)));
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.getSize(find.byType(AnimatedCounter)), const Size(3 * _column, _wheel));
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);

      await tester.pumpWidget(_host(const AnimatedCounter(value: 1000)));
      await tester.pumpAndSettle();
      final Uint8List back = await _pictureOf(tester);
      await tester.pumpWidget(_host(const AnimatedCounter(value: 1000)));
      final Uint8List mounted = await _pictureOf(tester);
      expect(_same(back, mounted), isTrue);
    });

    testWidgets('reduce motion from the platform holds it still',
        (WidgetTester tester) async {
      final MediaQueryData media = const MediaQueryData(disableAnimations: true);
      await tester.pumpWidget(_host(const AnimatedCounter(value: 999), media: media));
      await tester.pumpWidget(_host(const AnimatedCounter(value: 1000), media: media));
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.getSize(find.byType(AnimatedCounter)), const Size(5 * _column, _wheel));
    });

    testWidgets('reduce motion asked for directly holds it still',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const AnimatedCounter(
        value: 999,
        reduceMotion: true,
      )));
      await tester.pumpWidget(_host(const AnimatedCounter(
        value: 123456,
        reduceMotion: true,
      )));
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      final Uint8List settled = await _pictureOf(tester);
      expect(_litPixels(settled), greaterThan(0));
    });
  });

  group('what it survives', () {
    testWidgets('absurd values, decimals and pads', (WidgetTester tester) async {
      for (final double value in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
        1e30,
        -1e30,
        -0.0,
        1e-300,
        0,
      ]) {
        for (final int decimals in <int>[0, 2, 99]) {
          for (final int pad in <int>[1, 30]) {
            await tester.pumpWidget(_host(AnimatedCounter(
              value: value,
              decimals: decimals,
              padStart: pad,
            )));
            await tester.pump(const Duration(milliseconds: 40));
            expect(tester.takeException(), isNull,
                reason: '$value / $decimals / $pad');
          }
        }
      }
      await tester.pumpAndSettle();
    });

    testWidgets('a value that keeps changing', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const AnimatedCounter(value: 0)));
      for (int value = 1; value <= 200; value++) {
        await tester.pumpWidget(_host(AnimatedCounter(value: value.toDouble())));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      final SemanticsHandle handle = tester.ensureSemantics();
      expect(tester.getSemantics(find.byType(AnimatedCounter)).label, '200');
      handle.dispose();
    });

    testWidgets('being thrown away mid-roll', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const AnimatedCounter(value: 1)));
      await tester.pumpWidget(_host(const AnimatedCounter(value: 98765)));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pumpWidget(_host(const SizedBox.shrink()));
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('right-to-left text', (WidgetTester tester) async {
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.rtl,
        child: MediaQuery(
          data: const MediaQueryData(),
          child: DefaultTextStyle(
            style: const TextStyle(fontSize: _face),
            child: Center(
              child: AnimatedCounter(value: 1234, prefix: const Text(r'$')),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      // Four digits, one separator and the prefix.
      expect(tester.getSize(find.byType(AnimatedCounter)).width, 6 * _column);
      expect(tester.takeException(), isNull);
    });
  });
}

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if ((a[i] - b[i]).abs() > 2) return false;
  }
  return true;
}
