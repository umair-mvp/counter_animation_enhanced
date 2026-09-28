# Changelog

## 1.0.1

- README: added a demo clip of the wheels rolling, so the motion is visible
  before the package is added to a project.

## 1.0.0

Initial release.

- `AnimatedCounter`: a number whose digits roll into place on vertical
  slot-machine wheels, driven by a spring re-aimed whenever the value changes.
- Counts up and down; a wheel that is already turning is re-aimed from where it
  is, and reversals take the short way back.
- Fixed decimals, zero padding (`padStart`), a sign column, and prefix / suffix
  widgets.
- Western, Indian and no digit grouping, with configurable separator characters.
- Per-column mask fade so a resting digit stays solid while faces pass through
  the air above and below it.
- Reduce-motion support via the platform setting or `reduceMotion`, plus a
  plain-text semantics label for screen readers.
- Public formatting helpers (`measureCounter`, `formatCounter`, `toCells`) so a
  text label can match the counter exactly.
