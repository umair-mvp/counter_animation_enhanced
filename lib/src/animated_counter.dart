/// The odometer widget: one [AnimatedCounter] shows a number whose digits roll
/// into place on vertical wheels.
library;

import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'counter_formatting.dart';
import 'counter_spring.dart';

part 'animated_counter_strip.dart';

/// What a column holds: a rolling wheel, a static mark, or the minus sign.
enum _Kind { digit, mark, sign }

/// A column as the current value asks for it, before it is matched with the
/// state that has been carrying its key.
class _Unit {
  const _Unit({
    required this.key,
    required this.kind,
    this.text = '',
    this.face,
    this.fades = true,
  });

  /// Identity, counted in places from the right edge of the strip.
  final Object key;

  /// What the column shows.
  final _Kind kind;

  /// Glyphs for a mark or the sign; a digit draws its wheel instead.
  final String text;

  /// Face the wheel should rest on, for a digit column.
  final int? face;

  /// Whether the column fades in and out, as opposed to simply being there.
  final bool fades;
}

/// A rolling counter for a number.
///
/// Every digit lives in a column of ten faces. When [value] changes, each
/// column whose face changed turns its wheel to the new face along a spring,
/// while the columns that did not change hold perfectly still — so `1.00` to
/// `1.01` rolls one face and everything else waits.
///
/// ```dart
/// AnimatedCounter(
///   value: 1234.5,
///   decimals: 2,
///   duration: const Duration(milliseconds: 800),
///   prefix: const Text(r'$'),
///   style: Theme.of(context).textTheme.displaySmall,
/// )
/// ```
///
/// The font, size and colour come from the ambient [DefaultTextStyle] (merged
/// with [style]), so the counter drops into running text the way an inline
/// element would. Columns are keyed by their distance from the right edge, so a
/// carry from `999` to `1,000` slides the existing wheels into their new places
/// instead of replacing them.
///
/// Screen readers get the value as plain text; the wheels are decoration only.
class AnimatedCounter extends StatefulWidget {
  /// Creates a rolling counter for [value].
  const AnimatedCounter({
    super.key,
    required this.value,
    this.decimals = 0,
    this.duration = const Duration(milliseconds: 600),
    this.padStart = 1,
    this.separator = ',',
    this.decimalSeparator = '.',
    this.grouping = CounterGrouping.western,
    this.prefix,
    this.suffix,
    this.style,
    this.lineHeight = 1.5,
    this.bounce = 0.18,
    this.reduceMotion,
    this.textDirection,
  });

  /// The number to show. Animate it by rebuilding with a new value.
  final double value;

  /// Digits after the decimal mark, clamped to `0..15`.
  final int decimals;

  /// How long one wheel gets to settle, clamped to `0.01..60` seconds.
  final Duration duration;

  /// Smallest number of whole digits, so a value can hold its width. Clamped to
  /// `1..24`.
  final int padStart;

  /// Digit-group separator; pass an empty [separator] for none.
  final String separator;

  /// Marker between the whole and the fractional part.
  final String decimalSeparator;

  /// How [separator] is inserted between groups of digits.
  final CounterGrouping grouping;

  /// Static content before the number, such as a currency sign.
  final Widget? prefix;

  /// Static content after the number, such as a unit.
  final Widget? suffix;

  /// Merged over the ambient [DefaultTextStyle].
  final TextStyle? style;

  /// Wheel height as a multiple of the font size: the band of air the mask
  /// fades through above and below a resting face.
  final double lineHeight;

  /// Overshoot of the spring that settles everything, `0` for none and `1` for
  /// never settling.
  final double bounce;

  /// Holds every wheel and column still. Defaults to the platform's
  /// reduce-motion setting.
  final bool? reduceMotion;

  /// Direction of the strip; defaults to the ambient [Directionality].
  final TextDirection? textDirection;

  @override
  State<AnimatedCounter> createState() => _AnimatedCounterState();
}

class _AnimatedCounterState extends State<AnimatedCounter>
    with SingleTickerProviderStateMixin {
  /// Live columns by key, including the ones only still fading out.
  final Map<Object, _Column> _columns = <Object, _Column>{};

  /// Columns to draw, in order, rebuilt by [_layOut]. A column's numbers are
  /// read live while it is painted, so an animated frame costs no rebuild.
  List<_Placed> _placed = const <_Placed>[];

  /// Glyphs laid out once and kept, for both measuring the columns and drawing
  /// them.
  final _GlyphBank _bank = _GlyphBank();

  /// Bumped once per animated frame to repaint the strip.
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);

  late final Ticker _ticker = createTicker(_onTick);
  Duration _lastStamp = Duration.zero;

  double _faceHeight = 0;
  double _stripWidth = 0;
  double _pace = 0.6;
  String _voiceOver = '';

  bool _firstPass = true;
  bool _still = false;
  double? _previousAmount;
  int _direction = 1;

  @override
  void dispose() {
    _ticker.dispose();
    _bank.dispose();
    _repaint.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- animation

  void _onTick(Duration stamp) {
    final double dt = (stamp - _lastStamp).inMicroseconds / 1e6;
    _lastStamp = stamp;

    if (dt > 0) {
      final List<Object> gone = <Object>[];
      for (final _Column column in _columns.values) {
        column.rollOn(dt);
        if (column.leaving && column.opacity <= 0) gone.add(column.key);
      }
      for (final Object key in gone) {
        _columns.remove(key);
      }
      _repaint.value++;
    }

    if (!_anyBusy()) {
      _ticker.stop();
      _lastStamp = Duration.zero;
    }
  }

  bool _anyBusy() {
    for (final _Column column in _columns.values) {
      if (column.busy) return true;
    }
    return false;
  }

  void _ensureTicking() {
    if (_ticker.isActive) return;
    _lastStamp = Duration.zero;
    _ticker.start();
  }

  // ------------------------------------------------------------------- layout

  /// Seconds a wheel gets to settle, zero when motion is held.
  double get _rollTime => _still ? 0 : _pace;

  CounterSpringRoll _aim(double from, double to) {
    return CounterSpringRoll(
      CounterSpring.fromVisualDuration(
        visualDuration: math.max(_rollTime, 0.0001),
        bounce: widget.bounce,
      ),
      from,
      to,
      // A zero-pace roll lands the moment it is ticked, which is how a held
      // animation and a reduced-motion layout both end up in one code path.
      tolerance: _rollTime == 0
          ? const CounterTolerance(distance: 0, velocity: 0)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextDirection direction =
        widget.textDirection ?? Directionality.of(context);
    final TextStyle style = DefaultTextStyle.of(context).style
        .merge(widget.style)
        // The counter owns its own vertical rhythm, so a line height inherited
        // from a surrounding paragraph must not stack on top of the wheel box.
        .copyWith(height: null);
    final TextScaler scaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;

    _layOut(
      style,
      scaler,
      direction,
      widget.reduceMotion ??
          MediaQuery.maybeDisableAnimationsOf(context) ??
          false,
    );

    return Semantics(
      label: _voiceOver,
      container: true,
      child: DefaultTextStyle(
        style: style,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          textDirection: direction,
          children: <Widget>[
            if (widget.prefix != null) widget.prefix!,
            _CounterStrip(
              placed: _placed,
              bank: _bank,
              repaint: _repaint,
              style: style,
              textScaler: scaler,
              faceHeight: _faceHeight,
              width: _stripWidth,
              textDirection: direction,
            ),
            if (widget.suffix != null) widget.suffix!,
          ],
        ),
      ),
    );
  }

  /// Measures the columns the current value asks for, aims anything that moved,
  /// and lays the strip out from the left the way an inline element is laid.
  void _layOut(
    TextStyle style,
    TextScaler scaler,
    TextDirection direction,
    bool still,
  ) {
    _still = still;
    final List<_Unit> units = _units();
    _faceHeight = scaler.scale(style.fontSize ?? _fallbackFontSize) *
        widget.lineHeight;
    _bank.use(style, scaler, _faceHeight, direction);

    final Map<Object, _Column> known = Map<Object, _Column>.of(_columns);
    final Set<Object> live = <Object>{};
    final List<_Placed> placed = <_Placed>[];

    for (final _Unit unit in units) {
      live.add(unit.key);
      final _Column column = known[unit.key] ?? _create(unit);
      _columns[unit.key] = column;

      // A column that came back cancels the fade that was taking it away.
      if (column.leaving) {
        column.leaving = false;
        column.fadeTrack = null;
        column.fadingIn = column.opacity < 1;
      }
      column.width = unit.face != null
          ? _bank.widestDigit
          : _bank.widthOf(unit.text);
      column.text = unit.text;

      if (unit.face != null) _roll(column, unit.face!.toDouble());
      if (column.fadingIn && !still && column.fadeTrack == null) {
        column.enter(_aim(column.opacity, 1));
      }

      placed.add(_Placed(column, unit.text));
    }

    for (final _Column column in known.values) {
      if (live.contains(column.key) || column.leaving) continue;
      if (still) {
        _columns.remove(column.key);
      } else {
        column.pop();
      }
    }

    double left = 0;
    for (final _Placed placedColumn in placed) {
      final _Column column = placedColumn.state;
      if (column.fresh) {
        // An arriving column takes its place in the flow and stays there; the
        // neighbours are the ones that move.
        column.fresh = false;
        column.x = left;
      } else if (column.x == left) {
        column.xTrack = null;
      } else if (still) {
        column.x = left;
        column.xTrack = null;
      } else {
        column.slide(_aim(column.x, left));
      }
      left += column.width;
    }
    _stripWidth = left;

    // Columns that have left the flow keep being drawn where they stood, fading
    // out while the others slide into their place.
    for (final _Column column in _columns.values) {
      if (column.leaving) placed.add(_Placed(column, column.text));
    }

    if (_anyBusy()) _ensureTicking();
    _firstPass = false;
    _placed = placed;
  }

  /// Starts a brand-new column: at mount it sits on its face, later it starts on
  /// zero and rolls in.
  _Column _create(_Unit unit) {
    final _Column column = _Column(unit.key, unit.kind);
    if (unit.face != null) {
      column.wheel = column.goal = _firstPass ? unit.face!.toDouble() : 0;
    }
    // A fixed column (the sign) never fades: it is simply there or not.
    column.opacity = _firstPass || _still || !unit.fades ? 1 : 0;
    column.fadingIn = column.opacity < 1;
    return column;
  }

  /// Turns a wheel to [face] the short way round in the direction of travel.
  void _roll(_Column column, double face) {
    // Re-aim only when the face changed; a wheel already heading there keeps its
    // turn uncounted.
    if (wrap(column.goal, wheelPlaces) == face) return;
    final double at = column.wheel;
    column.goal = aimWheel(
      at: at,
      face: face,
      backwards: _direction < 0,
    );

    if (_still) {
      column.wheel = column.goal;
      column.wheelTrack = null;
      return;
    }
    column.turn(_aim(at, column.goal));
  }

  /// The columns the current value asks for, plus the voice-over text.
  List<_Unit> _units() {
    final CounterShape shape = measureCounter(
      widget.value,
      widget.decimals,
      widget.padStart,
      widget.duration.inMicroseconds / 1e6,
    );
    _pace = shape.pace;

    final String chars = formatCounter(
      shape,
      widget.separator,
      widget.decimalSeparator,
      widget.grouping,
    );
    _voiceOver = shape.isNegative ? '-$chars' : chars;

    final double? previous = _previousAmount;
    if (previous != null && previous != shape.amount) {
      _direction = shape.amount >= previous ? 1 : -1;
    }
    _previousAmount = shape.amount;

    final List<_Unit> units = <_Unit>[
      if (shape.isNegative)
        const _Unit(key: _signKey, kind: _Kind.sign, text: '-', fades: false),
    ];
    for (final CounterCell cell in toCells(chars, shape.width)) {
      if (cell is CounterDigitCell) {
        units.add(_Unit(key: cell.key, kind: _Kind.digit, face: cell.digit));
      } else {
        final CounterMarkCell mark = cell as CounterMarkCell;
        units.add(_Unit(key: mark.key, kind: _Kind.mark, text: mark.char));
      }
    }
    return units;
  }
}
