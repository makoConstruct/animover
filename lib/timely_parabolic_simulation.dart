// Ported from animated_containers (DynamicEaseInOutSimulation) — piecewise
// parabolic / linear ease-in-out with a fixed duration and smooth retargeting.
//
// Originally translated from https://github.com/makoConstruct/interruptable_easer

import 'dart:math' as math;

import 'package:flutter/physics.dart';

double _sq(double a) => a * a;

double _linearAccelerationEaseInOutWithInitialVelocity(
  double t,
  double initialVelocity,
) {
  return t *
      (t * ((initialVelocity - 2) * t + (3 - 2 * initialVelocity)) +
          initialVelocity);
}

double _velocityOfLinearAccelerationEaseInOutWithInitialVelocity(
  double t,
  double initialVelocity,
) {
  return t * ((3 * initialVelocity - 6) * t + (6 - 4 * initialVelocity)) +
      initialVelocity;
}

double _constantAccelerationEaseInOutWithInitialVelocity(
  double t,
  double initialVelocity,
) {
  if (t >= 1) {
    return 1;
  }
  final sqrtPart = math.sqrt(
    2 * _sq(initialVelocity) - 4 * initialVelocity + 4,
  );
  final m =
      (2 - initialVelocity + (initialVelocity < 2 ? sqrtPart : -sqrtPart)) / 2;
  final ax = -initialVelocity / (2 * m);
  final ay = initialVelocity * ax / 2;
  final h = (ax + 1) / 2;
  if (t < h) {
    return m * _sq(t - ax) + ay;
  } else {
    return -m * _sq(t - 1) + 1;
  }
}

double _velocityOfConstantAccelerationEaseInOutWithInitialVelocity(
  double t,
  double initialVelocity,
) {
  if (t >= 1) {
    return 0;
  }
  final sqrtPart = math.sqrt(
    2 * _sq(initialVelocity) - 4 * initialVelocity + 4,
  );
  final m =
      (2 - initialVelocity + (initialVelocity < 2 ? sqrtPart : -sqrtPart)) / 2;
  final ax = -initialVelocity / (2 * m);
  final h = (ax + 1) / 2;
  if (t < h) {
    return 2 * m * (t - ax);
  } else {
    return 2 * m * (1 - t);
  }
}

/// Default segment length in seconds for [TimelyParabolicSimulation]'s
/// `(current, target, velocity)` constructor (matches common short layout moves).
const double kTimelyParabolicDefaultDurationSeconds = 0.24;

/// a no-nonsense sim that takes a fixed duration to transpire
/// Fixed-duration ease from [startValue] to [endValue] that can be retargeted
/// with [target] without velocity jumps. [duration] and the [time] argument to
/// [x], [dx], and [isDone] share the same units (for example `1.0` for a
/// normalized 0→1 progress curve, or microseconds as in the original easer).
class TimelyParabolicSimulation extends Simulation {
  /// At [value] with zero velocity; call [target] to animate. For the
  /// [SimulationFactory] shape `(current, target, velocity)` use the unnamed
  /// constructor instead.
  TimelyParabolicSimulation.constant(double value, {required this.duration})
    : startValue = value,
      endValue = value,
      startVelocity = 0.0,
      super();

  /// From [current] toward [target] with initial [velocity], in seconds for
  /// [duration] and for [x] / [dx] / [isDone] time — same shape as
  /// [SpringSimulation] and [SimulationFactory].
  TimelyParabolicSimulation(
    double current,
    double target,
    double velocity, {
    this.duration = kTimelyParabolicDefaultDurationSeconds,
  }) : startValue = current,
       endValue = target,
       startVelocity = velocity,
       super();

  TimelyParabolicSimulation.fromState({
    required double position,
    required double velocity,
    required double target,
    required this.duration,
  }) : startValue = position,
       endValue = target,
       startVelocity = velocity,
       super();

  /// First sample reaches the target immediately (no transition until retarget).
  TimelyParabolicSimulation.unset({required this.duration})
    : startValue = double.nan,
      endValue = double.nan,
      startVelocity = double.nan,
      super();

  double startValue;
  double endValue;
  double startVelocity;
  double duration;

  void target(double v, {required double time}) {
    if (startValue.isNaN) {
      startValue = endValue = v;
      startVelocity = 0;
    } else {
      startValue = x(time);
      startVelocity = dx(time);
      endValue = v;
    }
  }

  @override
  double x(double time) {
    if (startValue.isNaN) return endValue;
    if (startValue == endValue) return startValue;
    final normalizedTime = time / duration;
    final normalizedVelocity =
        startVelocity / (endValue - startValue) * duration;
    final normalizedOutput = normalizedVelocity > 2
        ? _linearAccelerationEaseInOutWithInitialVelocity(
            normalizedTime,
            normalizedVelocity,
          )
        : _constantAccelerationEaseInOutWithInitialVelocity(
            normalizedTime,
            normalizedVelocity,
          );
    return startValue + normalizedOutput * (endValue - startValue);
  }

  @override
  double dx(double time) {
    if (startValue.isNaN) return 0.0;
    if (startValue == endValue) return 0.0;
    final normalizedTime = time / duration;
    final normalizedVelocity =
        startVelocity / (endValue - startValue) * duration;
    final normalizedOutput = normalizedVelocity > 2
        ? _velocityOfLinearAccelerationEaseInOutWithInitialVelocity(
            normalizedTime,
            normalizedVelocity,
          )
        : _velocityOfConstantAccelerationEaseInOutWithInitialVelocity(
            normalizedTime,
            normalizedVelocity,
          );
    return normalizedOutput * (endValue - startValue) / duration;
  }

  @override
  bool isDone(double time) {
    if (startValue.isNaN) return time >= duration;
    if (startValue == endValue) return true;
    return time >= duration;
  }
}
