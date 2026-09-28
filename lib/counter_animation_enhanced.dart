/// A number that counts itself up — and down — on rolling digit wheels.
///
/// Drop an [AnimatedCounter] anywhere a `Text` would go and change its `value`:
/// each digit lives on a vertical wheel of ten faces, and only the wheels whose
/// face actually changed turn.
///
/// ```dart
/// AnimatedCounter(
///   value: 1234.5,
///   decimals: 2,
///   duration: const Duration(milliseconds: 800),
///   prefix: const Text(r'$'),
/// )
/// ```
///
/// The formatting helpers ([measureCounter], [formatCounter], [toCells]) are
/// public too, so a plain-text label can be formatted exactly the way the
/// counter formats its wheels.
library;

export 'src/animated_counter.dart' show AnimatedCounter;
export 'src/counter_formatting.dart'
    show
        CounterCell,
        CounterDigitCell,
        CounterGrouping,
        CounterMarkCell,
        CounterShape,
        aimWheel,
        formatCounter,
        groupDigits,
        maxDecimals,
        maxDuration,
        maxPad,
        maxSafeInteger,
        measureCounter,
        minDuration,
        toCells,
        wheelPlaces,
        wrap;
