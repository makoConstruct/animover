import 'dart:math';

import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

export 'anisized_container.dart';
export 'timely_parabolic_simulation.dart';

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
    SpringDescription.withDampingRatio(mass: 1, stiffness: 400, ratio: 1),
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
    bool enabled = true,
  }) : _ticker = ticker,
       _simulationFactory = simulationFactory ?? defaultSimulationFactory,
       _enabled = enabled;

  final Ticker _ticker;
  SimulationFactory _simulationFactory;

  set simulationFactory(SimulationFactory value) {
    _simulationFactory = value;
  }

  bool _enabled;
  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (!_enabled && _isAnimating) {
      _stopAnimation();
      markNeedsPaint();
    }
  }

  // --- Frame lookup ---

  /// Nearest ancestor frame. Kept across detach so we can find the common
  /// ancestor with the new frame on re-attach.
  RenderAnimoveFrame? _frame;

  RenderAnimoveFrame? _findFrame() {
    RenderObject? ancestor = parent;
    while (true) {
      if (ancestor == null || ancestor is RenderAnimoveFrame) {
        return ancestor as RenderAnimoveFrame?;
      }
      ancestor = ancestor.parent;
    }
  }

  /// Finds the closest common ancestor frame between two frames.
  /// Returns null if either frame is null or they share no common ancestor.
  static RenderAnimoveFrame? _findCommonAncestorFrame(
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
    for (int i = 0; i < min(a1.length, a2.length); ++i) {
      if (a1[a1.length - i - 1] == a2[a2.length - i - 1]) {
        common = a1[a1.length - i - 1];
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
  Duration? _lastTickElapsed;

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

  /// The frame that was active at the last paint. Used during attach to
  /// identify the common ancestor with the new frame.
  RenderAnimoveFrame? _previousFrame;

  // --- Layer for z-ordering ---

  final LayerHandle<OffsetLayer> _layerHandle = LayerHandle<OffsetLayer>();

  // --- Reparenting ---

  /// The common-ancestor frame between [_previousFrame] and the new frame,
  /// found during attach. Used for z-ordering during reparent animation.
  /// Nulled when the animation completes.
  RenderAnimoveFrame? _commonAncestorFrame;

  /// The old visual position converted to [_commonAncestorFrame]'s coordinate
  /// space, computed during attach. Consumed by paint to start the reparent
  /// animation.
  Offset? _positionFromCommonAncestor;

  bool _pendingReparent = false;

  bool _useLayerForAnimation = false;

  // --- Lifecycle ---

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    final newFrame = _findFrame();
    if (newFrame != _previousFrame && _posFromFrame != null) {
      _useLayerForAnimation = true;
      // considering making new common ancestor be the common ancestor between the current nearest frame, the previous nearest frame, and also the previous common ancestor, to account for situations where the animation was already in a very high z-index and we don't want to suddely lower it.
      _commonAncestorFrame = _findCommonAncestorFrame(_previousFrame, newFrame);
      // if (_commonAncestorFrame != null && _commonAncestorFrame!.attached) {
      //   commonAncestor = _findCommonAncestorFrame(_commonAncestorFrame, newFrame);
      // }

      // Convert old visual position to common ancestor (or global) space.
      if (_previousFrame != null && _previousFrame!.attached) {
        final globalOld = _previousFrame!.localToGlobal(_posFromFrame!);
        _positionFromCommonAncestor =
            _commonAncestorFrame?.globalToRelative(globalOld) ?? globalOld;
      } else {
        // Previous frame was null (global) or no longer attached.
        _positionFromCommonAncestor =
            _commonAncestorFrame?.globalToRelative(_posFromFrame!) ??
            _posFromFrame!;
      }

      _pendingReparent = true;
    }
    _frame = newFrame;
  }

  @override
  void detach() {
    if (_isAnimating) {
      _posFromFrame ??= Offset.zero;
    }
    _commonAncestorFrame?._unregisterAnimating(this);
    _commonAncestorFrame = null;
    _positionFromCommonAncestor = null;
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
    // we act as if the animation started one tick ago. This makes things one frame more responsive than they otherwise would be, it's also absolutely necessary in situations where the animation is being interrupted every frame by a traditional layout animation, without this, the animoves wouldn't be able to start to move until that layout animation ends.
    _animationStart = _lastTickElapsed;
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
    _lastTickElapsed = null;
    _txX = 0.0;
    _txY = 0.0;
    _velX = 0.0;
    _velY = 0.0;

    _commonAncestorFrame?._unregisterAnimating(this);
    _commonAncestorFrame = null;
    _positionFromCommonAncestor = null;
    _useLayerForAnimation = false;
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
    _lastTickElapsed = elapsed;
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
    _commonAncestorFrame?.markNeedsPaint();
  }

  // --- Paint ---

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;

    if (_frame == null) {
      // No frame — track global position, paint without animation.
      _posFromFrame = localToGlobal(Offset.zero);
      _previousFrame = null;
      paintFrame(context, offset);
      return;
    }

    final newPos = _frame!.getRelativeOffset(this);

    if (_pendingReparent) {
      if (_positionFromCommonAncestor != null && _enabled) {
        // New position in common ancestor (or global) space.
        final newPosInAncestor = _commonAncestorFrame != null
            ? _commonAncestorFrame!.getRelativeOffset(this)
            : localToGlobal(Offset.zero);

        final translation =
            _positionFromCommonAncestor! -
            newPosInAncestor +
            Offset(_txX, _txY);
        if (translation.distanceSquared > _kEpsilon * _kEpsilon) {
          _commonAncestorFrame?._registerAnimating(this);
          _startAnimation(translation.dx, translation.dy, _velX, _velY);
        } else {
          _commonAncestorFrame = null;
        }
      }
      _pendingReparent = false;
      _positionFromCommonAncestor = null;
    } else if (_enabled &&
        _posFromFrame != null &&
        (_posFromFrame! - newPos).distanceSquared > _kEpsilon * _kEpsilon) {
      // Position changed within same frame — start or interrupt animation.
      final delta = _posFromFrame! + Offset(_txX, _txY) - newPos;
      _startAnimation(delta.dx, delta.dy, _velX, _velY);
    }

    _posFromFrame = newPos;
    _previousFrame = _frame;

    if (_isAnimating && _useLayerForAnimation) {
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
    this.enabled = true,
    required this.child,
  });

  final SimulationFactory? simulationFactory;
  final bool enabled;
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
      enabled: widget.enabled,
      child: widget.child,
    );
  }
}

class _AnimoveRenderWidget extends SingleChildRenderObjectWidget {
  const _AnimoveRenderWidget({
    required this.ticker,
    required this.simulationFactory,
    required this.enabled,
    required super.child,
  });

  final Ticker ticker;
  final SimulationFactory simulationFactory;
  final bool enabled;

  @override
  RenderAnimove createRenderObject(BuildContext context) {
    return RenderAnimove(
      ticker: ticker,
      simulationFactory: simulationFactory,
      enabled: enabled,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderAnimove renderObject) {
    renderObject
      ..simulationFactory = simulationFactory
      ..enabled = enabled;
  }
}
