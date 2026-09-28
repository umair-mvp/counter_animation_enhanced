/// Spring physics that reproduce the timing model of Motion's spring transition
/// written with a `visualDuration` and a `bounce`, so the roll of a wheel here
/// lands where the roll of a wheel there lands.
library;

import 'dart:math' as math;

/// Undamped frequency below which a spring is treated as already settled.
const double _minFrequency = 1e-6;

/// Cap on the hyperbolic argument of an overdamped spring, past which `sinh`
/// and `cosh` would overflow.
const double _maxHyperbolic = 300;

/// A damped harmonic oscillator on a unit mass.
class CounterSpring {
  /// Creates a spring from raw physics.
  const CounterSpring({
    this.stiffness = 100,
    this.damping = 10,
    this.mass = 1,
  });

  /// Creates a spring from how long it should *look* and how much it should
  /// overshoot, the same mapping Motion uses: the undamped frequency follows
  /// the visible period, and `bounce` becomes the damping ratio.
  ///
  /// [bounce] of `0` is critically damped and never overshoots; `1` never
  /// settles, so it is held to the same `0.05` floor Motion applies.
  factory CounterSpring.fromVisualDuration({
    required double visualDuration,
    double bounce = 0.18,
  }) {
    final double duration = visualDuration.isFinite && visualDuration > 0
        ? visualDuration
        : 0.3;
    final double ratio = (1 - bounce).clamp(0.05, 1.0).toDouble();
    final double frequency = (2 * math.pi) / (duration * 1.2);
    final double stiffness = frequency * frequency;

    return CounterSpring(
      stiffness: stiffness,
      damping: 2 * ratio * math.sqrt(stiffness * 1),
      mass: 1,
    );
  }

  /// Force holding the value towards its target.
  final double stiffness;

  /// Force opposing motion. Zero damping oscillates forever.
  final double damping;

  /// Inertia of the moving value.
  final double mass;

  /// Overshoot measure: below `1` the spring rings, above it creeps.
  double get dampingRatio => damping / (2 * math.sqrt(stiffness * mass));

  double get _undampedFrequency => math.sqrt(stiffness / mass);
}

/// How close is close enough for a spring to be called finished, in units and
/// units per second.
class CounterTolerance {
  /// Creates a tolerance window.
  const CounterTolerance({this.distance = 0.005, this.velocity = 10});

  /// Settles only once within [distance] of the target.
  final double distance;

  /// Settles only once slower than [velocity].
  final double velocity;

  /// The tight window Motion picks for values moving by less than five units.
  static const CounterTolerance granular = CounterTolerance();

  /// The loose window Motion picks for larger travel, matching its
  /// `restDelta: 2` / `restSpeed: 2` (per millisecond) defaults.
  static const CounterTolerance coarse = CounterTolerance(
    distance: 2,
    velocity: 2000,
  );

  /// Picks the window Motion would use for a move of [travel] units.
  static CounterTolerance forTravel(double travel) =>
      travel.abs() < 5 ? granular : coarse;
}

/// An analytical spring, sampled by seconds since it was aimed.
///
/// Closed form rather than integrated, so a value can be sampled for any
/// instant, and retargeting mid-flight inherits both position and velocity.
class CounterSpringRoll {
  /// Aims a spring at [to] from [from] with [velocity] units per second.
  CounterSpringRoll(
    this.spring,
    this.from,
    this.to, {
    double velocity = 0,
    CounterTolerance? tolerance,
  }) : tolerance = tolerance ?? CounterTolerance.forTravel(to - from) {
    final double ratio = spring.dampingRatio;
    final double frequency = spring._undampedFrequency;
    _ratio = ratio;
    _frequency = frequency;
    _decay = ratio * frequency;
    _delta = to - from;
    _velocity = velocity;

    if (ratio < 1) {
      _damped = frequency * math.sqrt(1 - ratio * ratio);
    } else if (ratio == 1) {
      _damped = 0;
    } else {
      _damped = frequency * math.sqrt(ratio * ratio - 1);
    }

    _positionA = _damped < _minFrequency
        ? 0
        : (_velocity + _decay * _delta) / _damped;
  }

  /// The physics driving the roll.
  final CounterSpring spring;

  /// Where the roll started.
  final double from;

  /// Where the roll is aimed.
  final double to;

  /// When to stop watching the roll.
  final CounterTolerance tolerance;

  late final double _ratio;
  late final double _frequency;
  late final double _decay;
  late final double _delta;
  late final double _velocity;
  late final double _damped;
  late final double _positionA;

  /// Position after [elapsed] seconds.
  double value(double elapsed) {
    final double ratio = _ratio;
    if (ratio < 1) {
      return to -
          math.exp(-_decay * elapsed) *
              (_positionA * math.sin(_damped * elapsed) +
                  _delta * math.cos(_damped * elapsed));
    }
    if (ratio == 1) {
      final double frequency = _frequency;
      return to -
          math.exp(-frequency * elapsed) *
              (_delta + (_velocity + frequency * _delta) * elapsed);
    }
    final double argument = math.min(_damped * elapsed, _maxHyperbolic);
    return to -
        math.exp(-_decay * elapsed) *
            ((_velocity + _decay * _delta) * _sinh(argument) +
                _damped * _delta * _cosh(argument)) /
            _damped;
  }

  /// Speed after [elapsed] seconds, in units per second.
  double speed(double elapsed) {
    final double ratio = _ratio;
    if (ratio < 1) {
      final double envelope = math.exp(-_decay * elapsed);
      return envelope *
          ((_decay * _positionA + _delta * _damped) *
                  math.sin(_damped * elapsed) +
              (_decay * _delta - _positionA * _damped) *
                  math.cos(_damped * elapsed));
    }
    if (ratio == 1) {
      final double frequency = _frequency;
      final double coefficient = _velocity + frequency * _delta;
      return math.exp(-frequency * elapsed) *
          (frequency * coefficient * elapsed - _velocity);
    }
    final double envelope = math.exp(-_decay * elapsed);
    final double argument = math.min(_damped * elapsed, _maxHyperbolic);
    final double hyperbolicSine = _decay * _positionA - _delta * _damped;
    final double hyperbolicCosine = _decay * _delta - _positionA * _damped;
    return envelope *
        (hyperbolicSine * _sinh(argument) +
            hyperbolicCosine * _cosh(argument));
  }

  /// True once the roll is inside [tolerance] of its target.
  bool isDone(double elapsed) =>
      (to - value(elapsed)).abs() <= tolerance.distance &&
      speed(elapsed).abs() <= tolerance.velocity;

  /// The value to lock in once [isDone] reports true: springs land exactly.
  double get landed => to;
}

/// A fixed-length tween along a curve, for the transitions Motion writes as a
/// duration rather than as physics.
class CounterCurveRoll {
  /// Tweens from [from] to [to] over [durationSeconds] along [curve].
  const CounterCurveRoll({
    required this.from,
    required this.to,
    required this.duration,
    required this.curve,
  });

  /// Where the roll started.
  final double from;

  /// Where the roll is aimed.
  final double to;

  /// Length in seconds; zero jumps straight to [to].
  final double duration;

  /// Easing, in the `0..1` to `0..1` range.
  final double Function(double t) curve;

  /// Position after [elapsed] seconds.
  double value(double elapsed) {
    if (duration <= 0) return to;
    if (elapsed >= duration) return to;
    return from + (to - from) * curve(elapsed / duration);
  }

  /// Always true once the length has been spent.
  bool isDone(double elapsed) => elapsed >= duration;
}

double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;

double _cosh(double x) => (math.exp(x) + math.exp(-x)) / 2;

/// `cubic-bezier(0.22, 1, 0.36, 1)`, the easing Motion leaves the wheel with.
///
/// Solved by Newton-Raphson on the x polynomial, which converges in a couple of
/// steps for this monotone curve.
double easeOutQuintLike(double t) {
  if (t <= 0) return 0;
  if (t >= 1) return 1;

  double guess = t;
  for (int step = 0; step < 8; step++) {
    final double x = _bezierAt(guess, 0.22, 0.36) - t;
    if (x.abs() < 1e-6) break;
    final double slope = _bezierSlopeAt(guess, 0.22, 0.36);
    if (slope.abs() < 1e-6) break;
    guess -= x / slope;
    if (guess < 0) {
      guess = 0;
    } else if (guess > 1) {
      guess = 1;
    }
  }
  return _bezierAt(guess, 1, 1);
}

double _bezierAt(double t, double first, double last) {
  final double inverse = 1 - t;
  return 3 * inverse * inverse * t * first +
      3 * inverse * t * t * last +
      t * t * t;
}

double _bezierSlopeAt(double t, double first, double last) {
  final double inverse = 1 - t;
  return 3 * inverse * inverse * first +
      6 * inverse * t * (last - first) +
      3 * t * t * (1 - last);
}
