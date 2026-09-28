part of 'animated_counter.dart';

/// The key the minus column answers to.
const String _signKey = 'sign';

/// Default font size, used only when the inherited style does not say.
const double _fallbackFontSize = 14;

/// How long a column takes to fade out once it has left the strip, in seconds.
const double _leaveSeconds = 0.18;

/// Faces on a wheel, with the trailing `0` so the wrap from `9` back to `0`
/// lands on an identical face. Used to size a column by its widest face.
const List<int> _faces = <int>[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0];

/// Faces on one wheel, as an integer, for slot arithmetic.
const int _facesPerWheel = 10;

/// The air around each face is what the mask fades through, so a resting digit
/// stays solid. These are the fractions of the wheel box, and how much of the
/// ink survives at each of them.
///
/// Eased rather than a straight ramp: a linear fade of the same width reads as
/// a hard edge.
const List<double> _fadeStops = <double>[
  0, 0.055, 0.11, 0.165, 0.22, 0.78, 0.835, 0.89, 0.945, 1,
];
const List<double> _fadeAlphas = <double>[
  0, 0.06, 0.5, 0.94, 1, 1, 0.94, 0.5, 0.06, 0,
];

/// One animated property of a column: where it sits, how visible it is, or
/// which face its wheel is on.
class _Track {
  /// Runs a spring towards its target.
  _Track.spring(CounterSpringRoll roll)
      : spring = roll,
        curve = null;

  /// Runs a fixed-length curve.
  _Track.curve(CounterCurveRoll roll)
      : spring = null,
        curve = roll;

  final CounterSpringRoll? spring;
  final CounterCurveRoll? curve;

  double _elapsed = 0;

  /// Where the track ends up once it is done.
  double get target => spring?.landed ?? curve!.to;

  /// The value at the track's current age.
  double get value =>
      spring != null ? spring!.value(_elapsed) : curve!.value(_elapsed);

  /// Ages the track by [dt] seconds, reporting whether it still has ground to
  /// cover.
  bool step(double dt) {
    _elapsed += dt;
    final bool done =
        spring != null ? spring!.isDone(_elapsed) : curve!.isDone(_elapsed);
    return !done;
  }
}

/// Live state of one column: where it sits, how visible it is and, for digits,
/// where its wheel is.
class _Column {
  _Column(this.key, this.kind);

  /// Place from the right edge of the strip, or [_signKey] for the sign.
  final Object key;

  /// What this column shows.
  final _Kind kind;

  /// Left edge of the column in the strip.
  double x = 0;

  /// How solid the column is, `0` being invisible.
  double opacity = 1;

  /// Measured width of the column.
  double width = 0;

  /// Wheel position in faces, unbounded: rendering wraps it into a turn, so
  /// several turns can queue up behind each other.
  double wheel = 0;

  /// Where the wheel is aimed, kept absolute for the same reason.
  double goal = 0;

  _Track? xTrack;
  _Track? fadeTrack;
  _Track? wheelTrack;

  /// Glyphs of a mark or the sign, kept so a column can finish fading out with
  /// the characters it was showing.
  String text = '';

  /// True while an arriving column is still fading up to solid.
  bool fadingIn = false;

  /// True until a brand-new column has been given its place in the flow: it
  /// appears there, rather than sliding to it.
  bool fresh = true;

  /// Popped out of the flow while it fades away, so its neighbours get the
  /// space immediately.
  bool leaving = false;

  bool get busy => xTrack != null || fadeTrack != null || wheelTrack != null;

  /// Aims the wheel.
  void turn(CounterSpringRoll roll) => wheelTrack = _Track.spring(roll);

  /// Slides the column along the strip.
  void slide(CounterSpringRoll roll) => xTrack = _Track.spring(roll);

  /// Fades an arriving column up to solid.
  void enter(CounterSpringRoll roll) {
    fadingIn = true;
    fadeTrack = _Track.spring(roll);
  }

  /// Pops the column out of the flow and fades it away.
  void pop() {
    leaving = true;
    fadingIn = false;
    fadeTrack = _Track.curve(
      CounterCurveRoll(
        from: opacity,
        to: 0,
        duration: _leaveSeconds,
        curve: easeOutQuintLike,
      ),
    );
  }

  /// Moves every running track on by [dt] seconds.
  void rollOn(double dt) {
    final _Track? turn = wheelTrack;
    if (turn != null) {
      final bool running = turn.step(dt);
      wheel = running ? turn.value : turn.target;
      if (!running) wheelTrack = null;
    }

    final _Track? slide = xTrack;
    if (slide != null) {
      final bool running = slide.step(dt);
      x = running ? slide.value : slide.target;
      if (!running) xTrack = null;
    }

    final _Track? fade = fadeTrack;
    if (fade != null) {
      final bool running = fade.step(dt);
      opacity = running ? fade.value : fade.target;
      if (!running) {
        fadeTrack = null;
        fadingIn = false;
      }
    }
  }
}

/// A column paired with the glyphs to draw in it.
class _Placed {
  const _Placed(this.state, this.text);

  final _Column state;
  final String text;
}

/// The painted part of the counter: every column of the strip, on one canvas.
class _CounterStrip extends StatelessWidget {
  const _CounterStrip({
    required this.placed,
    required this.bank,
    required this.repaint,
    required this.style,
    required this.textScaler,
    required this.faceHeight,
    required this.width,
    required this.textDirection,
  });

  final List<_Placed> placed;
  final _GlyphBank bank;
  final Listenable repaint;
  final TextStyle style;
  final TextScaler textScaler;
  final double faceHeight;
  final double width;
  final TextDirection textDirection;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CounterPainter(
        placed: placed,
        bank: bank,
        style: style,
        textScaler: textScaler,
        faceHeight: faceHeight,
        textDirection: textDirection,
        repaint: repaint,
      ),
      size: Size(math.max(width, 0), faceHeight),
    );
  }
}

/// Glyphs laid out once and kept across rebuilds, so a rolling frame draws text
/// it has already measured rather than laying the alphabet out again.
///
/// The mask fade lives here too, baked into the gradient the digits are drawn
/// with: no layer, and no touching whatever the counter sits on.
class _GlyphBank {
  final Map<String, TextPainter> _painters = <String, TextPainter>{};

  TextStyle? _for;
  TextScaler? _scaler;
  double _height = -1;
  TextDirection? _direction;
  TextStyle? _masked;

  /// Points the bank at the style to serve, dropping anything laid out for a
  /// different one.
  void use(
    TextStyle style,
    TextScaler scaler,
    double faceHeight,
    TextDirection direction,
  ) {
    if (_for == style &&
        _scaler == scaler &&
        _height == faceHeight &&
        _direction == direction) {
      return;
    }
    _for = style;
    _scaler = scaler;
    _height = faceHeight;
    _direction = direction;
    _masked = null;
    for (final TextPainter painter in _painters.values) {
      painter.dispose();
    }
    _painters.clear();
  }

  /// The laid-out [text], either washed through the mask fade (digits) or solid
  /// (separators and the sign, which never move).
  TextPainter glyph(String text, {required bool masked}) {
    return _painters.putIfAbsent('${masked ? 1 : 0}$text', () {
      final TextPainter painter = TextPainter(
        text: TextSpan(
          text: text,
          style: masked ? (_masked ??= _buildMaskStyle()) : _for,
        ),
        textDirection: _direction!,
        textScaler: _scaler!,
      )..layout();
      return painter;
    });
  }

  /// How wide [text] is in this style, used to place the columns.
  double widthOf(String text) => glyph(text, masked: false).width;

  /// The widest face: a column is sized by it, so the wheels next to each other
  /// cannot shove one another sideways in a font with no tabular figures.
  double get widestDigit {
    double widest = 0;
    for (final int face in _faces) {
      widest = math.max(widest, widthOf('$face'));
    }
    return widest;
  }

  /// The text style with the fade baked in as the paint glyphs are drawn with.
  ///
  /// The gradient runs along the wheel box, so it depends on the canvas height
  /// only and one shader serves every column.
  TextStyle _buildMaskStyle() {
    final Color base = _for!.color ?? const Color(0xDD000000);
    final LinearGradient gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomLeft,
      colors: List<Color>.generate(
        _fadeAlphas.length,
        (int index) => base.withValues(alpha: base.a * _fadeAlphas[index]),
      ),
      stops: _fadeStops,
    );
    return _for!.copyWith(
      color: null,
      foreground: Paint()
        ..shader = gradient.createShader(
          Rect.fromLTWH(0, 0, 1, math.max(_height, 0.0001)),
        ),
    );
  }

  void dispose() {
    for (final TextPainter painter in _painters.values) {
      painter.dispose();
    }
    _painters.clear();
  }
}

/// Draws the wheels.
///
/// The columns are painted rather than built as widgets: a rolling digit swaps
/// faces every frame, and text layout has no business happening that often.
/// A frame only moves and tints what the [bank] has already laid out.
class _CounterPainter extends CustomPainter {
  _CounterPainter({
    required this.placed,
    required this.bank,
    required this.style,
    required this.textScaler,
    required this.faceHeight,
    required this.textDirection,
    super.repaint,
  });

  final List<_Placed> placed;
  final _GlyphBank bank;
  final TextStyle style;
  final TextScaler textScaler;
  final double faceHeight;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    bank.use(style, textScaler, faceHeight, textDirection);
    if (faceHeight <= 0) return;

    for (final _Placed placed in placed) {
      final _Column column = placed.state;
      if (column.opacity <= 0 || column.width <= 0) continue;

      final bool faded = column.opacity < 1;
      if (faded) {
        canvas.saveLayer(
          Rect.fromLTWH(column.x, 0, column.width, faceHeight),
          Paint()..color = Color.fromRGBO(0, 0, 0, _clamp01(column.opacity)),
        );
      }

      if (column.kind == _Kind.digit) {
        _paintWheel(canvas, column);
      } else if (placed.text.isNotEmpty) {
        _paintGlyph(canvas, column.x, column.width, placed.text, false, 0);
      }

      if (faded) canvas.restore();
    }
  }

  /// Draws the two faces that straddle the box, plus one on each side in case a
  /// fast frame moves the wheel by more than a face.
  void _paintWheel(Canvas canvas, _Column column) {
    final double at = wrap(column.wheel, wheelPlaces);
    final int base = at.floor();
    for (int slot = base - 1; slot <= base + 2; slot++) {
      final double top = (slot - at) * faceHeight;
      if (top >= faceHeight || top <= -faceHeight) continue;
      _paintGlyph(
        canvas,
        column.x,
        column.width,
        '${_digitOf(slot)}',
        true,
        top,
      );
    }
  }

  /// The digit on the wheel face at [slot], counting up from any direction: the
  /// wheel is a ring of ten, so a slot below zero is the same face as a slot
  /// above nine.
  static int _digitOf(int slot) {
    final int digit = slot % _facesPerWheel;
    return digit < 0 ? digit + _facesPerWheel : digit;
  }

  void _paintGlyph(
    Canvas canvas,
    double x,
    double width,
    String glyph,
    bool masked,
    double top,
  ) {
    final TextPainter painter = bank.glyph(glyph, masked: masked);
    painter.paint(
      canvas,
      Offset(
        x + (width - painter.width) / 2,
        top + (faceHeight - painter.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(_CounterPainter oldDelegate) => true;
}

double _clamp01(double value) => value < 0 ? 0 : (value > 1 ? 1 : value);
