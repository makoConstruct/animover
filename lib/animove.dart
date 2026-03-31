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

    if (_animatingDescendants.isEmpty) {
      // No animations — paint normally, no extra layer
      context.paintChild(child!, offset);
      return;
    }

    // Push a fresh container layer so we can reparent animating layers on top.
    final containerLayer = OffsetLayer(offset: offset);
    context.pushLayer(containerLayer, (ctx, _) {
      ctx.paintChild(child!, Offset.zero);

      for (final animove in _animatingDescendants) {
        final layer = animove._offsetLayer;
        if (layer != null) {
          layer.remove();
          // Reparent animations use root-frame-relative position;
          // normal animations use nearest-frame-relative position.
          layer.offset = animove._isReparentAnim
              ? (animove._registeredRelativePos ?? Offset.zero)
              : (animove._cachedRelativePos ?? Offset.zero);
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
    RenderBox? child,
    required Ticker ticker,
    SimulationFactory? simulationFactory,
  }) : _ticker = ticker,
       _simulationFactory = simulationFactory ?? defaultSimulationFactory,
       super(child: child);

  final Ticker _ticker;
  SimulationFactory _simulationFactory;

  set simulationFactory(SimulationFactory value) {
    _simulationFactory = value;
  }

  // --- Frame lookup ---

  RenderAnimoveFrame? _frame;

  RenderAnimoveFrame? _findFrame() {
    RenderObject? ancestor = parent;
    while (ancestor != null) {
      if (ancestor is RenderAnimoveFrame) return ancestor;
      ancestor = ancestor.parent;
    }
    return null;
  }

  /// Finds the outermost ancestor frame. Used for reparent animations so
  /// the overlay can paint on top of everything between origin and destination.
  RenderAnimoveFrame? _findRootFrame() {
    RenderAnimoveFrame? result;
    RenderObject? ancestor = parent;
    while (ancestor != null) {
      if (ancestor is RenderAnimoveFrame) result = ancestor;
      ancestor = ancestor.parent;
    }
    return result;
  }

  // --- Animation state ---

  Simulation? _simX;
  Simulation? _simY;
  Duration? _animationStart;

  // Current translation offset (visual displacement from layout position)
  double _txX = 0.0;
  double _txY = 0.0;

  // Current velocity
  double _velX = 0.0;
  double _velY = 0.0;

  bool get _isAnimating => _simX != null || _simY != null;

  // --- Position tracking ---

  Offset? _cachedRelativePos;
  Offset? _lastGlobalPos;

  // --- Layer for z-ordering ---
  // LayerHandle keeps refcount > 0 so the layer isn't disposed when
  // the frame reparents it (remove() drops the parent's handle).

  final LayerHandle<OffsetLayer> _layerHandle = LayerHandle<OffsetLayer>();
  OffsetLayer? get _offsetLayer => _layerHandle.layer;

  // --- Reparenting ---

  Offset? _savedGlobalPos;
  double _savedVelX = 0.0;
  double _savedVelY = 0.0;
  bool _pendingReparent = false;

  // During reparent animations, z-ordering registers with the root frame
  // (not the nearest frame) so the overlay covers everything between
  // origin and destination. _registeredFrame tracks which frame we're
  // registered with; _registeredRelativePos is our position in that
  // frame's coordinate space (for layer placement).
  bool _isReparentAnim = false;
  RenderAnimoveFrame? _registeredFrame;
  Offset? _registeredRelativePos;

  // --- Lifecycle ---

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _frame = _findFrame();
    if (_savedGlobalPos != null) {
      _pendingReparent = true;
    }
  }

  @override
  void detach() {
    if (_isAnimating && _lastGlobalPos != null) {
      // Save visual position (layout + animation translation) and velocity
      // so reparent animation can continue smoothly.
      _savedGlobalPos = _lastGlobalPos! + Offset(_txX, _txY);
      _savedVelX = _velX;
      _savedVelY = _velY;
    } else {
      _savedGlobalPos = _lastGlobalPos;
      _savedVelX = 0.0;
      _savedVelY = 0.0;
    }
    _cachedRelativePos = null;
    _stopAnimation();
    _frame = null;
    super.detach();
  }

  @override
  void dispose() {
    _stopAnimation();
    _layerHandle.layer = null;
    super.dispose();
  }

  // --- Animation driving ---

  void _startAnimation(
    double fromX, double fromY, double velX, double velY, {
    RenderAnimoveFrame? zOrderFrame,
  }) {
    // Unregister from previous frame if switching
    _registeredFrame?._unregisterAnimating(this);

    _simX = _simulationFactory(fromX, 0.0, velX);
    _simY = _simulationFactory(fromY, 0.0, velY);
    _animationStart = null; // will be set on first tick
    _txX = fromX;
    _txY = fromY;
    _velX = velX;
    _velY = velY;

    _registeredFrame = zOrderFrame ?? _frame;
    _registeredFrame?._registerAnimating(this);

    if (!_ticker.isTicking) {
      _ticker.start();
    }
  }

  void _stopAnimation() {
    _simX = null;
    _simY = null;
    _animationStart = null;
    _txX = 0.0;
    _txY = 0.0;
    _velX = 0.0;
    _velY = 0.0;

    _registeredFrame?._unregisterAnimating(this);
    _registeredFrame = null;
    _isReparentAnim = false;
    _registeredRelativePos = null;
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
    // Ensure the registered frame repaints too — repaint boundaries between
    // us and it would otherwise prevent it from updating (or removing) our
    // reparented z-ordering layer.
    _registeredFrame?.markNeedsPaint();
  }

  // --- Paint ---

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;

    final frame = _frame;
    if (frame == null) {
      // No frame found — paint as frame only (no animation)
      paintFrame(context, offset);
      return;
    }

    if (_isReparentAnim) {
      // During reparent animation, track position in the registered (root)
      // frame's space for z-ordering layer placement. Skip normal position-
      // change detection — it uses a different coordinate space.
      if (_registeredFrame != null) {
        _registeredRelativePos = _registeredFrame!.getRelativeOffset(this);
      }
      _lastGlobalPos = localToGlobal(Offset.zero);
    } else {
      final relativePos = frame.getRelativeOffset(this);

      if (_pendingReparent && _savedGlobalPos != null) {
        // Reparented: use the root frame for z-ordering so the overlay
        // covers everything between origin and destination.
        final rootFrame = _findRootFrame() ?? frame;
        final rootRelPos = rootFrame.getRelativeOffset(this);
        final oldRelPos = rootFrame.globalToRelative(_savedGlobalPos!);
        final translation = oldRelPos - rootRelPos;
        // Only animate if the position actually changed (skip trivial
        // reparents like sliver garbage-collection at the same content pos).
        if (translation.distanceSquared > _kEpsilon * _kEpsilon) {
          _isReparentAnim = true;
          _registeredRelativePos = rootRelPos;
          _startAnimation(
            translation.dx, translation.dy, _savedVelX, _savedVelY,
            zOrderFrame: rootFrame,
          );
        }
        _pendingReparent = false;
        _savedGlobalPos = null;
      } else if (_cachedRelativePos != null &&
          (_cachedRelativePos! - relativePos).distanceSquared >
              _kEpsilon * _kEpsilon) {
        // Position changed — start or interrupt animation
        final delta = _cachedRelativePos! - relativePos;
        if (_isAnimating) {
          // Interruption: compose current visual translation with new delta
          final newTxX = _txX + delta.dx;
          final newTxY = _txY + delta.dy;
          _startAnimation(newTxX, newTxY, _velX, _velY);
        } else {
          _startAnimation(delta.dx, delta.dy, 0.0, 0.0);
        }
      }

      _cachedRelativePos = relativePos;
      _lastGlobalPos = localToGlobal(Offset.zero);
    }

    if (_isAnimating) {
      // Push an OffsetLayer so the registered frame can reparent it for
      // z-ordering. The LayerHandle keeps refcount > 0 during reparenting.
      _layerHandle.layer = OffsetLayer(offset: offset);
      context.pushLayer(_offsetLayer!, (ctx, _) {
        // Inside our animation layer, paint as a frame (handles z-ordering
        // for any animating descendants nested inside us).
        paintFrame(ctx, Offset(_txX, _txY));
      }, Offset.zero);
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
