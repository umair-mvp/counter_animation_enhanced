# counter_animation_enhanced

A number that counts itself up — and down — on rolling digit wheels.

`AnimatedCounter` puts every digit in a vertical column of ten faces. When the
value changes, only the columns whose face actually changed turn; the rest hold
perfectly still. So `1.00 → 1.01` rolls one wheel, `1.09 → 1.10` rolls two, and
`999 → 1,000` slides a fresh column into place. The motion is a spring, not a
tween, so a value that keeps changing re-aims the wheels that are already
turning instead of queueing up a backlog behind them.

```dart
AnimatedCounter(
  value: 1234.5,
  decimals: 2,
  duration: const Duration(milliseconds: 800),
  prefix: const Text(r'$'),
  style: Theme.of(context).textTheme.displayMedium,
)
```

## Why a wheel and not a crossfade

Fading one digit into the next looks like the text being swapped out. A wheel
turns, which is what the eye expects from a value that is *increasing*: the faces
climb, and the digit you were reading leaves through the top. A short mask fade
above and below each column lets that exit and entry read as movement rather
than as two hard edges snapping past one another.

## Features

- **Spring motion.** Position, arrival and turn all run on the same damped
  oscillator, tuned by `duration` and `bounce`.
- **Counts down as well as up.** Wheels reverse and take the short way back; a
  wheel mid-turn is re-aimed, not restarted.
- **Fixed decimals, zero padding, and a sign column** that only appears once
  there are digits to sign (`-0.004` at two decimals shows `0.00`, not `-0.00`).
- **Western, Indian and no digit grouping**, with any separator characters:
  `1,234,567`, `1.234.567`, `12,34,567`, or `1234567`.
- **Prefix and suffix widgets** so currency signs and units sit on the same line.
- **Reduce motion respected.** The platform setting, or `reduceMotion: true`,
  holds every wheel still and jumps straight to the new number.
- **Accessible by construction.** Screen readers get the value as plain text;
  the spinning wheels are decoration and are not read out.
- **Painted, not rebuilt.** Digits are laid out once and drawn on a canvas, so a
  rolling value costs no per-frame text layout.

## Getting started

Add the package to `pubspec.yaml`:

```yaml
dependencies:
  counter_animation_enhanced: ^1.0.0
```

Then import it:

```dart
import 'package:counter_animation_enhanced/counter_animation_enhanced.dart';
```

The counter inherits its font, size and colour from the surrounding
`DefaultTextStyle`, so it drops into running text the way a `Text` widget would.

## Usage

### Count to a new value

The counter animates whenever `value` changes, so any state that rebuilds with a
new number is enough:

```dart
AnimatedCounter(value: _seconds.toDouble() * 1000, duration: const Duration(seconds: 1))
```

### Money, with decimals

```dart
AnimatedCounter(
  value: 1234567.89,
  decimals: 2,
  separator: ',',
  prefix: const Text(r'$'),
)
// $1,234,567.89
```

### Indian grouping

```dart
AnimatedCounter(value: 12345678, grouping: CounterGrouping.indian)
// 1,23,45,678
```

### A fixed-width readout

`padStart` keeps a minimum number of whole digits on screen, so a timer or a
score does not change width as it grows:

```dart
AnimatedCounter(value: 42, padStart: 5)
// 00042
```

### Driving it from an animation

Rebuild with an interpolated value; the wheels follow it frame by frame:

```dart
AnimatedBuilder(
  animation: controller,
  builder: (context, child) => AnimatedCounter(
    value: tween.evaluate(controller),
    duration: const Duration(milliseconds: 400),
  ),
)
```

## Parameters

| Parameter          | Default    | Meaning                                             |
| ------------------ | ---------- | --------------------------------------------------- |
| `value`            | required   | The number to show.                                  |
| `decimals`         | `0`        | Digits after the decimal mark (`0..15`).             |
| `duration`         | `600ms`    | How long a wheel gets to settle.                     |
| `padStart`         | `1`        | Fewest whole digits shown (`1..24`).                 |
| `separator`        | `,`        | Group separator; `''` for none.                      |
| `decimalSeparator` | `.`        | Marker before the fractional part.                   |
| `grouping`         | `western`  | `western`, `indian` or `none`.                       |
| `prefix`/`suffix`  | `null`     | Widgets on either side of the number.                |
| `style`            | inherited  | Merged over the ambient `DefaultTextStyle`.          |
| `lineHeight`       | `1.5`      | Wheel height as a multiple of the font size.         |
| `bounce`           | `0.18`     | Overshoot of the spring, `0` for none.               |
| `reduceMotion`     | platform   | Forces the still layout on or off.                   |
| `textDirection`    | inherited  | Direction of the strip.                              |

## Formatting without the widget

The formatting the wheels are built from is public too, so a plain-text label
elsewhere on screen can match the counter exactly:

```dart
final shape = measureCounter(1234567.891, 2, 1, 0.6);
formatCounter(shape, ',', '.', CounterGrouping.western); // 1,234,567.89
```

## Notes on edge cases

- `NaN` and `Infinity` are folded onto zero rather than printed.
- Values are rounded to the nearest representable digit count; beyond
  9,007,199,254,740,991 the low digits are noise, so they are held there.
- A value that changes every frame is a stream of re-aims: the wheels keep
  turning towards wherever they are being sent, and always land on the face the
  final value asks for.
- Digits use their font's own figures. For perfectly steady columns, pick a font
  with tabular figures (or a monospaced one); without them the column is sized by
  its widest face so the wheels still cannot shift each other sideways.

## Example

The [`example`](https://github.com/umair-mvp/counter_animation_enhanced/tree/main/example)
folder is a small app that counts a big number up from zero and shows the
grouping, decimals, padding, sign and reduce-motion variants side by side.

## Additional information

- Source and issue tracker:
  [github.com/umairxbt/counter_animation_enhanced](https://github.com/umair-mvp/counter_animation_enhanced)
- Released under the [MIT license](LICENSE).
- The wheel, mask-fade and spring design follows the well-known "animated
  counter" odometer pattern; this is an independent Flutter implementation of it.
