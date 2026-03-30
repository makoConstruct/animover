import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

const double _kEpsilon = 0.0001;

// --- Frame ---

class RenderAnimoveFrame extends RenderProxyBox {
  RenderAnimoveFrame({RenderBox? child}) : super(child);

  /// Returns [child]'s position in this frame's coordinate space.
  Offset getRelativeOffset(RenderBox child) {
    return child.localToGlobal(Offset.zero, ancestor: this);
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

  @override
  Offset getRelativeOffset(RenderBox child) {
    final base = super.getRelativeOffset(child);
    return switch (_scrollAxis) {
      Axis.vertical => base + Offset(0, _scrollOffset),
      Axis.horizontal => base + Offset(_scrollOffset, 0),
    };
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

class RenderAnimove extends RenderProxyBox {
  RenderAnimove({
    RenderBox? child,
    required Ticker ticker,
    SimulationFactory? simulationFactory,
  }) : _ticker = ticker,
       _simulationFactory = simulationFactory ?? defaultSimulationFactory,
       super(child);

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

  // --- Reparenting ---

  Offset? _savedGlobalPos;
  bool _pendingReparent = false;

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
    _savedGlobalPos = _lastGlobalPos;
    _stopAnimation();
    _frame = null;
    super.detach();
  }

  @override
  void dispose() {
    _stopAnimation();
    super.dispose();
  }

  // --- Animation driving ---

  void _startAnimation(double fromX, double fromY, double velX, double velY) {
    _simX = _simulationFactory(fromX, 0.0, velX);
    _simY = _simulationFactory(fromY, 0.0, velY);
    _animationStart = null; // will be set on first tick
    _txX = fromX;
    _txY = fromY;
    _velX = velX;
    _velY = velY;

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
  }

  // --- Paint ---

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;

    final frame = _frame;
    if (frame == null) {
      // No frame found — paint normally
      context.paintChild(child!, offset);
      return;
    }

    final relativePos = frame.getRelativeOffset(this);

    if (_pendingReparent && _savedGlobalPos != null) {
      // Reparented: map old global position into new frame's coordinate space
      final oldPosInFrame = MatrixUtils.transformPoint(
        frame.getTransformTo(null)..invert(),
        _savedGlobalPos!,
      );
      final translation = oldPosInFrame - relativePos;
      _startAnimation(translation.dx, translation.dy, 0.0, 0.0);
      _pendingReparent = false;
      _savedGlobalPos = null;
    } else if (_cachedRelativePos != null &&
        (_cachedRelativePos! - relativePos).distance > _kEpsilon) {
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

    if (_isAnimating) {
      context.paintChild(child!, offset + Offset(_txX, _txY));
    } else {
      context.paintChild(child!, offset);
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
