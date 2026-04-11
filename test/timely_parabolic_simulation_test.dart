import 'package:animove/timely_parabolic_simulation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SimulationFactory-style constructor reaches target at duration', () {
    final s = TimelyParabolicSimulation(0.0, 100.0, 0.0, duration: 1.0);
    expect(s.x(0), 0.0);
    expect(s.x(1.0), closeTo(100.0, 1e-9));
    expect(s.isDone(1.0), isTrue);
  });

  test('reaches end at duration', () {
    final s = TimelyParabolicSimulation.constant(0.0, duration: 1.0);
    s.target(100.0, time: 0);
    expect(s.x(0), 0.0);
    expect(s.x(1.0), closeTo(100.0, 1e-9));
    expect(s.isDone(1.0), isTrue);
  });

  test('retarget preserves continuity of position', () {
    final s = TimelyParabolicSimulation.constant(0.0, duration: 1.0);
    s.target(100.0, time: 0);
    final mid = s.x(0.5);
    s.target(200.0, time: 0.5);
    // New segment's clock starts at 0; position must match the interrupted curve.
    expect(s.x(0), closeTo(mid, 1e-9));
  });
}
