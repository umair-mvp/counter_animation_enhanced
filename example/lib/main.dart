import 'dart:math' as math;

import 'package:counter_animation_enhanced/counter_animation_enhanced.dart';
import 'package:flutter/material.dart';

void main() => runApp(const CounterDemoApp());

/// The demo app: one big number counting up, and a few shapes of it below.
class CounterDemoApp extends StatelessWidget {
  /// Creates the demo app.
  const CounterDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AnimatedCounter demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6C5CE7),
        useMaterial3: true,
      ),
      home: const CounterDemoPage(),
    );
  }
}

/// The demo page.
class CounterDemoPage extends StatefulWidget {
  /// Creates the demo page.
  const CounterDemoPage({super.key});

  @override
  State<CounterDemoPage> createState() => _CounterDemoPageState();
}

class _CounterDemoPageState extends State<CounterDemoPage>
    with SingleTickerProviderStateMixin {
  static const double _goal = 842197.32;

  late final AnimationController _runner = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );

  /// The value the big counter is asked to show, frame by frame.
  late final Animation<double> _amount = Tween<double>(
    begin: 0,
    end: _goal,
  ).animate(CurvedAnimation(parent: _runner, curve: Curves.easeOutCubic));

  /// Added by hand on top of whatever the driver is counting to, so a single
  /// step can be seen rolling one wheel.
  double _stepped = 0;

  @override
  void initState() {
    super.initState();
    _runner.forward();
  }

  @override
  void dispose() {
    _runner.dispose();
    super.dispose();
  }

  void _replay() {
    setState(() => _stepped = 0);
    _runner
      ..stop()
      ..value = 0
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Counting up', style: theme.textTheme.titleMedium),
                  // Only the counter listens to the driver, so a frame costs no
                  // rebuild of anything else on the page.
                  AnimatedBuilder(
                    animation: _runner,
                    builder: (BuildContext context, Widget? child) {
                      return AnimatedCounter(
                        value: _amount.value + _stepped,
                        decimals: 2,
                        duration: const Duration(milliseconds: 400),
                        style: theme.textTheme.displayLarge!.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    children: <Widget>[
                      FilledButton.icon(
                        onPressed: _replay,
                        icon: const Icon(Icons.replay),
                        label: const Text('Replay'),
                      ),
                      OutlinedButton(
                        onPressed: () => setState(() => _stepped += 1),
                        child: const Text('Step one'),
                      ),
                      OutlinedButton(
                        onPressed: () => setState(
                          () => _runner.value = math.Random().nextDouble(),
                        ),
                        child: const Text('Jump'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  Text('Shapes of it', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  const _ShapeRow(
                    label: 'Currency, no grouping',
                    child: AnimatedCounter(
                      value: 1234567,
                      separator: '',
                      prefix: Text(r'$'),
                    ),
                  ),
                  const _ShapeRow(
                    label: 'Lakhs and crores',
                    child: AnimatedCounter(
                      value: 12345678,
                      grouping: CounterGrouping.indian,
                    ),
                  ),
                  const _ShapeRow(
                    label: 'Percent, one decimal',
                    child: AnimatedCounter(
                      value: 99.9,
                      decimals: 1,
                      suffix: Text('%'),
                    ),
                  ),
                  const _ShapeRow(
                    label: 'Below zero',
                    child: AnimatedCounter(
                      value: -12.75,
                      decimals: 2,
                      suffix: Text('°C'),
                    ),
                  ),
                  const _ShapeRow(
                    label: 'Padded to five digits',
                    child: AnimatedCounter(value: 42, padStart: 5),
                  ),
                  const _ShapeRow(
                    label: 'Nothing moves under reduce motion',
                    child: AnimatedCounter(value: 987654, reduceMotion: true),
                  ),
                  const SizedBox(height: 24),
                  const _ChangeMyValue(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A label beside a counter.
class _ShapeRow extends StatelessWidget {
  const _ShapeRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 200,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// A counter whose value is typed in, to show that any change rolls the wheels.
class _ChangeMyValue extends StatefulWidget {
  const _ChangeMyValue();

  @override
  State<_ChangeMyValue> createState() => _ChangeMyValueState();
}

class _ChangeMyValueState extends State<_ChangeMyValue> {
  double _value = 2026;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Your number', style: theme.textTheme.titleMedium),
        AnimatedCounter(
          value: _value,
          style: theme.textTheme.headlineMedium,
        ),
        Slider(
          min: -50000,
          max: 500000,
          value: _value.clamp(-50000, 500000),
          onChanged: (double value) => setState(() => _value = value),
        ),
      ],
    );
  }
}
