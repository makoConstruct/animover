import 'dart:math';

import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

const double _kEpsilon = 0.0001;

// --- Frame ---

class RenderAnimoveFrame extends RenderProxyBox {
  RenderAnimoveFrame({RenderBox? child}) : super(child);

  final Set<RenderAnimove> _animatingDescendants = {};

  void _registerAnimating(RenderAnimove animove) {
    _animatingDescendants.add(animove);
  }

  void _unregisterAnimating(RenderAnimove animove) {
    _animatingDescendants.remove(animove);
  }

  /// Returns [child]'s position in this frame's content coordinate space.
  Offset getRelativeOffset(RenderBox child) {
    return child.localToGlobal(Offset.zero, ancestor: this);
  }

  /// Converts a global position to this frame's content coordinate space.
  /// Must use the same coordinate space as [getRelativeOffset].
  Offset globalToRelative(Offset globalPos) {
    return MatrixUtils.transformPoint(
      getTransformTo(null)..invert(),
      globalPos,
    );
  }

  @override
  void dispose() {
    _animatingDescendants.clear();
    super.dispose();
  }

  /// Paints children with z-ordering support for animating descendants.
  /// Extracted so [RenderAnimove] can reuse this after applying its own
  /// animation translation.
  void paintFrame(PaintingContext context, Offset offset) {
    if (child == null) return;

    context.paintChild(child!, offset);
    if (_animatingDescendants.isEmpty) return;

    // Push a fresh container layer so we can reparent animating layers on top.
    final containerLayer = OffsetLayer(offset: offset);
    context.pushLayer(containerLayer, (ctx, _) {
      for (final animove in _animatingDescendants) {
        final layer = animove._layerHandle.layer;
        if (layer != null) {
          layer.remove();
          layer.offset = getRelativeOffset(animove);
          containerLayer.append(layer);
        }
      }
    }, Offset.zero);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    paintFrame(context, offset);
  }
}

class RenderAnimoveSliverFrame extends RenderAnimoveFrame {
  RenderAnimoveSliverFrame({super.child});

  Axis _scrollAxis = Axis.vertical;
  Axis get scrollAxis => _scrollAxis;
  set scrollAxis(Axis value) {
    if (_scrollAxis == value) return;
    _scrollAxis = value;
    markNeedsPaint();
  }

  double _scrollOffset = 0.0;
  double get scrollOffset => _scrollOffset;
  set scrollOffset(double value) {
    if (_scrollOffset == value) return;
    _scrollOffset = value;
    markNeedsPaint();
  }

  Offset _addScrollCompensation(Offset base) {
    return switch (_scrollAxis) {
      Axis.vertical => base + Offset(0, _scrollOffset),
      Axis.horizontal => base + Offset(_scrollOffset, 0),
    };
  }

  @override
  Offset getRelativeOffset(RenderBox child) {
    return _addScrollCompensation(super.getRelativeOffset(child));
  }

  @override
  Offset globalToRelative(Offset globalPos) {
    return _addScrollCompensation(super.globalToRelative(globalPos));
  }
}

class AnimoveFrame extends SingleChildRenderObjectWidget {
  const AnimoveFrame({super.key, super.child});

  @override
  RenderAnimoveFrame createRenderObject(BuildContext context) {
    return RenderAnimoveFrame();
  }
}

class AnimoveSliverFrame extends StatefulWidget {
  const AnimoveSliverFrame({
    super.key,
    required this.controller,
    required this.child,
  });

  final ScrollController controller;
  final Widget child;

  @override
  State<AnimoveSliverFrame> createState() => _AnimoveSliverFrameState();
}

class _AnimoveSliverFrameState extends State<AnimoveSliverFrame> {
  void _onScroll() {
    final renderObject = context.findRenderObject();
    if (renderObject is RenderAnimoveSliverFrame) {
      final position = widget.controller.position;
      renderObject
        ..scrollAxis = position.axis
        ..scrollOffset = position.pixels;
    }
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(AnimoveSliverFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AnimoveSliverFrameRenderWidget(child: widget.child);
  }
}

class _AnimoveSliverFrameRenderWidget extends SingleChildRenderObjectWidget {
  const _AnimoveSliverFrameRenderWidget({required super.child});

  @override
  RenderAnimoveSliverFrame createRenderObject(BuildContext context) {
    return RenderAnimoveSliverFrame();
  }
}

// --- Animove ---

/// Factory that creates a [Simulation] for one axis of movement.
///
/// - [current]: current visual offset (translation component) from target
/// - [target]: always 0.0 (translation decays to zero)
/// - [velocity]: current velocity at interruption, or 0.0 for fresh start
typedef SimulationFactory =
    Simulation Function(double current, double target, double velocity);

/// Default spring simulation factory.
Simulation defaultSimulationFactory(
  double current,
  double target,
  double velocity,
) {
  return SpringSimulation(
    SpringDescription.withDampingRatio(mass: 1, stiffness: 200, ratio: 1),
    current,
    target,
    velocity,
  );
}

class RenderAnimove extends RenderAnimoveFrame {
  RenderAnimove({
    super.child,
    required Ticker ticker,
    SimulationFactory? simulationFactory,
  }) : _ticker = ticker,
       _simulationFactory = simulationFactory ?? defaultSimulationFactory;

  final Ticker _ticker;
  SimulationFactory _simulationFactory;

  set simulationFactory(SimulationFactory value) {
    _simulationFactory = value;
  }

  // --- Frame lookup ---

  /// Nearest ancestor frame. Kept across detach so we can find the common
  /// ancestor with the new frame on re-attach.
  RenderAnimoveFrame? _frame;

  RenderAnimoveFrame? _findFrame() {
    RenderObject? ancestor = parent;
    while (ancestor != null) {
      if (ancestor is RenderAnimoveFrame) return ancestor;
      ancestor = ancestor.parent;
    }
    return null;
  }

  /// Finds the closest common ancestor frame between two frames.
  /// Returns null if either frame is null or they share no common ancestor.
  static RenderAnimoveFrame? _commonAncestorFrame(
    RenderAnimoveFrame? frame1,
    RenderAnimoveFrame? frame2,
  ) {
    if (frame1 == null || frame2 == null) return null;
    if (frame1 == frame2) return frame1;

    List<RenderAnimoveFrame> ancestors(RenderAnimoveFrame frame) {
      final list = <RenderAnimoveFrame>[frame];
      RenderObject? node = frame.parent;
      while (node != null) {
        if (node is RenderAnimoveFrame) list.add(node);
        node = node.parent;
      }
      return list;
    }

    final a1 = ancestors(frame1);
    final a2 = ancestors(frame2);

    RenderAnimoveFrame? common;
    for (int i = min(a1.length, a2.length) - 1; i > -1; i--) {
      if (a1[i] == a2[i]) {
        common = a1[i];
      } else {
        break;
      }
    }
    return common;
  }

  // --- Animation state ---

  Simulation? _simX;
  Simulation? _simY;
  Duration? _animationStart;

  double _txX = 0.0;
  double _txY = 0.0;
  double _velX = 0.0;
  double _velY = 0.0;

  bool get _isAnimating => _simX != null || _simY != null;

  // --- Position tracking ---

  /// Position relative to [_frame], or global if [_frame] is null.
  /// On detach, includes the visual translation offset so re-attach
  /// can animate from where the user last saw the widget.
  Offset? _posFromFrame;

  // --- Layer for z-ordering ---

  final LayerHandle<OffsetLayer> _layerHandle = LayerHandle<OffsetLayer>();

  // --- Reparenting ---

  /// The common-ancestor frame used for z-ordering during reparent animation.
  /// null when not reparent-animating.
  RenderAnimoveFrame? _animFrame;

  /// The previous frame, saved on attach when a reparent is detected.
  RenderAnimoveFrame? _previousFrame;
  bool _pendingReparent = false;

  bool get isReparentAnimating => _animFrame != null && _animFrame != _frame;

  // --- Lifecycle ---

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    final newFrame = _findFrame();
    if (newFrame != _frame && _posFromFrame != null) {
      _previousFrame = _frame;
      _pendingReparent = true;
    }
    _frame = newFrame;
  }

  @override
  void detach() {
    if (_isAnimating) {
      _posFromFrame = (_posFromFrame ?? Offset.zero) + Offset(_txX, _txY);
    }
    _animFrame?._unregisterAnimating(this);
    _animFrame = null;
    _layerHandle.layer = null;
    _pauseAnimation();
    super.detach();
  }

  @override
  void dispose() {
    _stopAnimation();
    _layerHandle.layer = null;
    super.dispose();
  }

  // --- Animation driving ---

  void _startAnimation(double fromX, double fromY, double velX, double velY) {
    _simX = _simulationFactory(fromX, 0.0, velX);
    _simY = _simulationFactory(fromY, 0.0, velY);
    _animationStart = null;
    _txX = fromX;
    _txY = fromY;
    _velX = velX;
    _velY = velY;

    if (!_ticker.isTicking) {
      _ticker.start();
    }
  }

  void _pauseAnimation() {
    if (_ticker.isTicking) {
      _ticker.stop();
    }
  }

  /// Stops animation on completion: zeros all state including velocity.
  void _stopAnimation() {
    _simX = null;
    _simY = null;
    _animationStart = null;
    _txX = 0.0;
    _txY = 0.0;
    _velX = 0.0;
    _velY = 0.0;

    _animFrame?._unregisterAnimating(this);
    _animFrame = null;
    _layerHandle.layer = null;

    if (_ticker.isTicking) {
      _ticker.stop();
    }
  }

  /// Called by the [Ticker] each frame.
  void onTick(Duration elapsed) {
    if (_simX == null && _simY == null) {
      _ticker.stop();
      return;
    }

    _animationStart ??= elapsed;
    final double t = (elapsed - _animationStart!).inMicroseconds / 1e6;

    bool doneX = true;
    bool doneY = true;

    if (_simX != null) {
      _txX = _simX!.x(t);
      _velX = _simX!.dx(t);
      doneX = _simX!.isDone(t);
    }
    if (_simY != null) {
      _txY = _simY!.x(t);
      _velY = _simY!.dx(t);
      doneY = _simY!.isDone(t);
    }

    if (doneX && doneY) {
      _stopAnimation();
    }

    markNeedsPaint();
    _animFrame?.markNeedsPaint();
  }

  // --- Paint ---

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;

    if (_frame == null) {
      // No frame — track global position, paint without animation.
      _posFromFrame = localToGlobal(Offset.zero);
      paintFrame(context, offset);
      return;
    }

    final newPos = _frame!.getRelativeOffset(this);

    if (!isReparentAnimating) {
      if (_pendingReparent) {
        if (_posFromFrame != null) {
          final commonAncestor = _commonAncestorFrame(_previousFrame, _frame);

          // Convert old visual position to common ancestor (or global) space.
          Offset oldPosInAncestor;
          if (_previousFrame != null && _previousFrame!.attached) {
            final globalOld = _previousFrame!.localToGlobal(_posFromFrame!);
            oldPosInAncestor =
                commonAncestor?.globalToRelative(globalOld) ?? globalOld;
          } else {
            // Previous frame was null (global) or no longer attached.
            oldPosInAncestor =
                commonAncestor?.globalToRelative(_posFromFrame!) ??
                _posFromFrame!;
          }

          // New position in common ancestor (or global) space.
          final newPosInAncestor = commonAncestor != null
              ? commonAncestor.getRelativeOffset(this)
              : localToGlobal(Offset.zero);

          final translation = oldPosInAncestor - newPosInAncestor;
          if (translation.distanceSquared > _kEpsilon * _kEpsilon) {
            _animFrame?._unregisterAnimating(this);
            _animFrame = commonAncestor;
            _animFrame?._registerAnimating(this);
            _startAnimation(translation.dx, translation.dy, _velX, _velY);
          }
        }
        _pendingReparent = false;
        _previousFrame = null;
      } else if (_posFromFrame != null &&
          (_posFromFrame! - newPos).distanceSquared > _kEpsilon * _kEpsilon) {
        // Position changed within same frame — start or interrupt animation.
        final delta = _posFromFrame! - newPos;
        if (_isAnimating) {
          _startAnimation(_txX + delta.dx, _txY + delta.dy, _velX, _velY);
        } else {
          _startAnimation(delta.dx, delta.dy, 0.0, 0.0);
        }
      }
    }

    _posFromFrame = newPos;

    if (_isAnimating && isReparentAnimating) {
      // Push an OffsetLayer so the animation frame can reparent it for
      // z-ordering above everything between origin and destination.
      _layerHandle.layer = OffsetLayer(offset: offset);
      context.pushLayer(_layerHandle.layer!, (ctx, _) {
        paintFrame(ctx, Offset(_txX, _txY));
      }, Offset.zero);
    } else if (_isAnimating) {
      _layerHandle.layer = null;
      paintFrame(context, offset + Offset(_txX, _txY));
    } else {
      _layerHandle.layer = null;
      paintFrame(context, offset);
    }
  }
}

class Animove extends StatefulWidget {
  const Animove({
    required GlobalKey super.key,
    this.simulationFactory,
    required this.child,
  });

  final SimulationFactory? simulationFactory;
  final Widget child;

  @override
  State<Animove> createState() => _AnimoveState();
}

class _AnimoveState extends State<Animove> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

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

  void _onTick(Duration elapsed) {
    final renderObject = context.findRenderObject();
    if (renderObject is RenderAnimove) {
      renderObject.onTick(elapsed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AnimoveRenderWidget(
      ticker: _ticker,
      simulationFactory: widget.simulationFactory ?? defaultSimulationFactory,
      child: widget.child,
    );
  }
}

class _AnimoveRenderWidget extends SingleChildRenderObjectWidget {
  const _AnimoveRenderWidget({
    required this.ticker,
    required this.simulationFactory,
    required super.child,
  });

  final Ticker ticker;
  final SimulationFactory simulationFactory;

  @override
  RenderAnimove createRenderObject(BuildContext context) {
    return RenderAnimove(ticker: ticker, simulationFactory: simulationFactory);
  }

  @override
  void updateRenderObject(BuildContext context, RenderAnimove renderObject) {
    renderObject.simulationFactory = simulationFactory;
  }
}
