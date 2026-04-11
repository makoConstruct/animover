// Based on RanimatedContainer from animated_containers: layout updates instantly
// while background decoration size is driven by a physics [Simulation] per axis.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Builds a [SpringSimulation] for one axis of size (width or height).
typedef SizeAxisSimulationFactory = Simulation Function(
  double current,
  double target,
  double velocity,
);

Simulation _defaultSizeAxisSimulation(
  double current,
  double target,
  double velocity,
) {
  return SpringSimulation(
    SpringDescription.withDampingRatio(mass: 1, stiffness: 400, ratio: 1),
    current,
    target,
    velocity,
  );
}

/// Like [Container], but the painted background (color, decoration, margin,
/// transform) follows the **previous** laid-out size with a spring while layout
/// uses the new size immediately.
class AnisizedContainer extends StatefulWidget {
  AnisizedContainer({
    super.key,
    this.alignment,
    this.padding,
    this.color,
    this.decoration,
    this.foregroundDecoration,
    double? width,
    double? height,
    BoxConstraints? constraints,
    this.margin,
    this.transform,
    this.transformAlignment,
    this.child,
    this.clipBehavior = Clip.none,
    this.sizeSimulationFactory = _defaultSizeAxisSimulation,
  })  : assert(margin == null || margin.isNonNegative),
        assert(padding == null || padding.isNonNegative),
        assert(decoration == null || decoration.debugAssertIsValid()),
        assert(constraints == null || constraints.debugAssertIsValid()),
        assert(decoration != null || clipBehavior == Clip.none),
        assert(
          color == null || decoration == null,
          'Cannot provide both a color and a decoration\n'
          'To provide both, use "decoration: BoxDecoration(color: color)".',
        ),
        constraints = (width != null || height != null)
            ? constraints?.tighten(width: width, height: height) ??
                BoxConstraints.tightFor(width: width, height: height)
            : constraints;

  final Widget? child;
  final AlignmentGeometry? alignment;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final Decoration? decoration;
  final Decoration? foregroundDecoration;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? margin;
  final Matrix4? transform;
  final AlignmentGeometry? transformAlignment;
  final Clip clipBehavior;
  final SizeAxisSimulationFactory sizeSimulationFactory;

  @override
  State<AnisizedContainer> createState() => _AnisizedContainerState();
}

class _AnisizedContainerState extends State<AnisizedContainer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  Simulation? _simW;
  Simulation? _simH;
  Duration? _animationStart;
  Duration _lastElapsed = Duration.zero;

  double _targetW = double.nan;
  double _targetH = double.nan;
  double _displayW = double.nan;
  double _displayH = double.nan;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _retargetSimulations(double tw, double th) {
    final start = _animationStart;
    final t = start != null
        ? (_lastElapsed - start).inMicroseconds / 1e6
        : 0.0;

    final cw = _simW != null ? _simW!.x(t) : _targetW;
    final ch = _simH != null ? _simH!.x(t) : _targetH;
    final vw = _simW != null ? _simW!.dx(t) : 0.0;
    final vh = _simH != null ? _simH!.dx(t) : 0.0;

    _simW = widget.sizeSimulationFactory(cw, tw, vw);
    _simH = widget.sizeSimulationFactory(ch, th, vh);
    _targetW = tw;
    _targetH = th;
    _animationStart = null;
    if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    _lastElapsed = elapsed;
    if (_simW == null && _simH == null) {
      _ticker.stop();
      return;
    }

    _animationStart ??= elapsed;
    final t = (elapsed - _animationStart!).inMicroseconds / 1e6;

    if (_simW != null) {
      _displayW = _simW!.x(t);
      if (_simW!.isDone(t)) {
        _displayW = _targetW;
        _simW = null;
      }
    } else {
      _displayW = _targetW;
    }

    if (_simH != null) {
      _displayH = _simH!.x(t);
      if (_simH!.isDone(t)) {
        _displayH = _targetH;
        _simH = null;
      }
    } else {
      _displayH = _targetH;
    }

    if (_simW == null && _simH == null) {
      _animationStart = null;
      _ticker.stop();
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return _SizeChangeReporter(
      onSizeChange: (size) {
        final tw = size.width;
        final th = size.height;
        if (_targetW.isNaN) {
          setState(() {
            _targetW = tw;
            _targetH = th;
            _displayW = tw;
            _displayH = th;
          });
          return;
        }
        if (tw == _targetW && th == _targetH) return;
        setState(() {
          _retargetSimulations(tw, th);
        });
      },
      child: Builder(
        builder: (context) {
          if (_displayW.isNaN || _displayH.isNaN) {
            return Container(
              alignment: widget.alignment,
              padding: widget.padding,
              color: widget.color,
              decoration: widget.decoration,
              foregroundDecoration: widget.foregroundDecoration,
              constraints: widget.constraints,
              margin: widget.margin,
              transform: widget.transform,
              transformAlignment: widget.transformAlignment,
              clipBehavior: widget.clipBehavior,
              child: widget.child,
            );
          }

          final w = _displayW;
          final h = _displayH;

          return Stack(
            fit: StackFit.passthrough,
            alignment: Alignment.center,
            children: [
              Positioned(
                left: 0,
                top: 0,
                child: SizedBox(
                  width: 0,
                  height: 0,
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    maxWidth: w,
                    maxHeight: h,
                    child: Container(
                      color: widget.color,
                      padding: widget.padding,
                      decoration: widget.decoration,
                      foregroundDecoration: widget.foregroundDecoration,
                      margin: widget.margin,
                      transform: widget.transform,
                      transformAlignment: widget.transformAlignment,
                    ),
                  ),
                ),
              ),
              Container(
                constraints: widget.constraints,
                alignment: widget.alignment,
                padding: widget.padding,
                clipBehavior: widget.clipBehavior,
                transform: widget.transform,
                transformAlignment: widget.transformAlignment,
                margin: widget.margin,
                child: widget.child,
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<AlignmentGeometry>(
      'alignment',
      widget.alignment,
      showName: false,
      defaultValue: null,
    ));
    properties.add(DiagnosticsProperty<EdgeInsetsGeometry>(
      'padding',
      widget.padding,
      defaultValue: null,
    ));
    properties.add(DiagnosticsProperty<Clip>(
      'clipBehavior',
      widget.clipBehavior,
      defaultValue: Clip.none,
    ));
    if (widget.color != null) {
      properties.add(DiagnosticsProperty<Color>('bg', widget.color));
    } else {
      properties.add(DiagnosticsProperty<Decoration>(
        'bg',
        widget.decoration,
        defaultValue: null,
      ));
    }
    properties.add(DiagnosticsProperty<Decoration>(
      'fg',
      widget.foregroundDecoration,
      defaultValue: null,
    ));
    properties.add(DiagnosticsProperty<BoxConstraints>(
      'constraints',
      widget.constraints,
      defaultValue: null,
    ));
    properties.add(DiagnosticsProperty<EdgeInsetsGeometry>(
      'margin',
      widget.margin,
      defaultValue: null,
    ));
    properties
        .add(ObjectFlagProperty<Matrix4>.has('transform', widget.transform));
  }
}

/// Reports the laid-out size of [child] after layout.
class _SizeChangeReporter extends StatefulWidget {
  const _SizeChangeReporter({
    required this.onSizeChange,
    required this.child,
  });

  final ValueChanged<Size> onSizeChange;
  final Widget child;

  @override
  State<_SizeChangeReporter> createState() => _SizeChangeReporterState();
}

class _SizeChangeReporterState extends State<_SizeChangeReporter> {
  @override
  Widget build(BuildContext context) {
    return _RenderSizeChangeReporter(
      onSizeChange: widget.onSizeChange,
      child: widget.child,
    );
  }
}

class _RenderSizeChangeReporter extends SingleChildRenderObjectWidget {
  const _RenderSizeChangeReporter({
    required this.onSizeChange,
    required super.child,
  });

  final ValueChanged<Size> onSizeChange;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderSizeChangeReporterBox(onSizeChange);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSizeChangeReporterBox renderObject,
  ) {
    renderObject.onSizeChange = onSizeChange;
  }
}

class _RenderSizeChangeReporterBox extends RenderProxyBox {
  _RenderSizeChangeReporterBox(this.onSizeChange);

  ValueChanged<Size> onSizeChange;
  Size? _oldSize;

  @override
  void performLayout() {
    super.performLayout();
    if (size != _oldSize) {
      _oldSize = size;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onSizeChange(size);
      });
    }
  }
}
