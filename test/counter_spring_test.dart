import 'dart:math' as math;

import 'package:counter_animation_enhanced/src/counter_spring.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CounterSpring.fromVisualDuration', () {
    test('turns a visible duration and a bounce into physics', () {
      final CounterSpring spring =
          CounterSpring.fromVisualDuration(visualDuration: 0.6, bounce: 0.18);
      // The undamped frequency follows the visible period, and bounce becomes
      // the damping ratio: 1 - 0.18.
      expect(spring.mass, 1);
      expect(spring.dampingRatio, closeTo(0.82, 1e-9));
      expect(spring.stiffness, closeTo(math.pow(2 * math.pi / 0.72, 2), 1e-6));
      expect(
        spring.damping,
        closeTo(2 * 0.82 * (2 * math.pi / 0.72), 1e-9),
      );
    });

    test('holds bounce inside the range that keeps the spring finite', () {
      expect(
        CounterSpring.fromVisualDuration(visualDuration: 0.6, bounce: 3)
            .dampingRatio,
        closeTo(0.05, 1e-9),
      );
      expect(
        CounterSpring.fromVisualDuration(visualDuration: 0.6, bounce: -3)
            .dampingRatio,
        closeTo(1, 1e-9),
      );
      // A duration that is not a number, or not positive, falls back.
      expect(
        CounterSpring.fromVisualDuration(visualDuration: double.nan).stiffness,
        closeTo(math.pow(2 * math.pi / 0.36, 2), 1e-6),
      );
    });

    test('never divides by a frequency that collapsed to zero', () {
      final CounterSpring spring =
          CounterSpring.fromVisualDuration(visualDuration: 1000);
      expect(spring.stiffness, greaterThan(0));
      expect(CounterSpringRoll(spring, 0, 1).value(0.5).isFinite, isTrue);
    });
  });

  group('CounterSpringRoll', () {
    final CounterSpring spring =
        CounterSpring.fromVisualDuration(visualDuration: 0.6, bounce: 0.18);

    test('starts where it was aimed from, and lands on the target', () {
      final CounterSpringRoll roll = CounterSpringRoll(spring, 0, 1);
      expect(roll.value(0), 0);
      expect(roll.landed, 1);
      expect(roll.isDone(0), isFalse);
    });

    test('settles within a couple of visible durations', () {
      final CounterSpringRoll roll = CounterSpringRoll(spring, 0, 1);
      expect(roll.isDone(0.3), isFalse);
      expect(roll.isDone(3), isTrue);
    });

    test('overshoots a little, then comes back', () {
      final CounterSpringRoll roll = CounterSpringRoll(spring, 0, 1);
      double highest = 0;
      for (double t = 0; t < 1.5; t += 0.001) {
        highest = math.max(highest, roll.value(t));
      }
      expect(highest, greaterThan(1), reason: 'bounce 0.18 must ring a bit');
      expect(highest, lessThan(1.05));
    });

    test('without bounce it walks up to the target and never past it', () {
      final CounterSpring flat =
          CounterSpring.fromVisualDuration(visualDuration: 0.6, bounce: 0);
      final CounterSpringRoll roll = CounterSpringRoll(flat, 0, 1);
      double previous = 0;
      for (double t = 0; t < 2; t += 0.005) {
        final double value = roll.value(t);
        expect(value, lessThanOrEqualTo(1 + 1e-9));
        expect(value, greaterThanOrEqualTo(previous - 1e-9));
        previous = value;
      }
    });

    test('turns either way symmetrically', () {
      final CounterSpringRoll up = CounterSpringRoll(spring, 0, 1);
      final CounterSpringRoll down = CounterSpringRoll(spring, 1, 0);
      for (double t = 0; t < 1.2; t += 0.05) {
        expect(up.value(t), closeTo(1 - down.value(t), 1e-9));
      }
    });

    test('picks its rest window by how far it has to go', () {
      expect(
        CounterSpringRoll(spring, 0, 4).tolerance.distance,
        CounterTolerance.granular.distance,
      );
      expect(
        CounterSpringRoll(spring, 0, 9).tolerance.distance,
        CounterTolerance.coarse.distance,
      );
      // A coarse window still lands exactly on the target when it closes.
      final CounterSpringRoll far = CounterSpringRoll(spring, 0, 9);
      expect(far.landed, 9);
      expect(far.isDone(3), isTrue);
    });

    test('can be sampled for any instant, in order', () {
      final CounterSpringRoll roll = CounterSpringRoll(spring, 0, 3);
      expect(roll.value(0.1), lessThan(roll.value(0.2)));
    });
  });

  group('CounterCurveRoll', () {
    test('holds the ends of its length', () {
      const CounterCurveRoll roll = CounterCurveRoll(
        from: 1,
        to: 0,
        duration: 0.18,
        curve: easeOutQuintLike,
      );
      expect(roll.value(0), 1);
      expect(roll.value(0.09), greaterThan(0));
      expect(roll.value(0.18), 0);
      expect(roll.value(5), 0);
      expect(roll.isDone(0.17), isFalse);
      expect(roll.isDone(0.19), isTrue);
    });

    test('of no length jumps straight to the target', () {
      const CounterCurveRoll jump = CounterCurveRoll(
        from: 3,
        to: 7,
        duration: 0,
        curve: easeOutQuintLike,
      );
      expect(jump.value(0), 7);
      expect(jump.isDone(0), isTrue);
    });
  });

  group('easeOutQuintLike', () {
    test('is the easing Motion leaves with', () {
      expect(easeOutQuintLike(0), 0);
      expect(easeOutQuintLike(1), 1);
      // cubic-bezier(0.22, 1, 0.36, 1) is most of the way there by halfway.
      expect(easeOutQuintLike(0.5), greaterThan(0.9));
      expect(easeOutQuintLike(0.5), lessThan(1));
    });

    test('only ever goes forwards', () {
      double previous = 0;
      for (double t = 0; t <= 1; t += 0.01) {
        final double value = easeOutQuintLike(t);
        expect(value, greaterThanOrEqualTo(previous));
        expect(value, inInclusiveRange(0, 1));
        previous = value;
      }
    });
  });
}
