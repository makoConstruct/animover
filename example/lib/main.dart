import 'package:animated_to/animated_to.dart';
import 'package:animove/animove.dart';
import 'package:flutter/material.dart';
import 'package:hero_animation/hero_animation.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Animove Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const SwapDemo(),
    );
  }
}

class SwapDemo extends StatefulWidget {
  const SwapDemo({super.key});

  @override
  State<SwapDemo> createState() => _SwapDemoState();
}

enum Library { animove, animatedTo, heroAnimation }

String libraryName(Library library) {
  return switch (library) {
    Library.animove => 'Animove',
    Library.animatedTo => 'Animated To',
    Library.heroAnimation => 'Hero Animation',
  };
}

class _SwapDemoState extends State<SwapDemo> {
  // 13 items: A–G (slots 0–6), H–K (nested, slots 7–10), L–M (non-sliver, slots 11–12)
  final _keys = List.generate(13, (i) => GlobalKey(debugLabel: 'item-$i'));
  final _itemWidgetKeys = List.generate(
    13,
    (i) => GlobalKey(debugLabel: 'item-widget-$i'),
  );

  // Two extra GlobalKeys for the outer animove wrappers in the nested section.
  final _nestedGroupKeys = [
    GlobalKey(debugLabel: 'group-0'),
    GlobalKey(debugLabel: 'group-1'),
  ];

  final _scrollController = ScrollController();
  final _horizontalScrollController = ScrollController();
  final _nonSliverScrollController = ScrollController();

  Library library = Library.animove;

  // Which group key is shown at each outer-group position (left=0, right=1).
  List<int> _nestedGroupOrder = [0, 1];

  // --- Library wrappers ---

  Widget createAnimove({
    required Widget child,
    required GlobalKey key,
    required String tag,
  }) {
    return switch (library) {
      Library.animove => Animove(key: key, child: child),
      Library.animatedTo => AnimatedTo.spring(globalKey: key, child: child),
      Library.heroAnimation => HeroAnimation.child(tag: tag, child: child),
    };
  }

  Widget createAnimoveFrame({required Widget child}) {
    return switch (library) {
      Library.animove => AnimoveFrame(child: child),
      Library.animatedTo => AnimatedToBoundary(child: child),
      Library.heroAnimation => HeroAnimationScene(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        child: child,
      ),
    };
  }

  // animated_to and hero_animation have no SliverFrame equivalent;
  // cross-scroll animation will be missing scroll-offset correction for those libraries.
  Widget createAnimoveSliverFrame({
    required Widget child,
    required ScrollController controller,
  }) {
    return switch (library) {
      Library.animove => AnimoveSliverFrame(
        controller: controller,
        child: child,
      ),
      Library.animatedTo => child,
      Library.heroAnimation => child,
    };
  }

  // --- Item data ---

  // Slot → item index mapping (starts as identity).
  late List<int> _slots = List.generate(13, (i) => i);

  final _labels = [
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
  ];
  final _colors = [
    Colors.red, // A 0
    Colors.orange, // B 1
    Colors.teal, // C 2
    Colors.blue, // D 3
    Colors.purple, // E 4
    Colors.green, // F 5
    Colors.amber, // G 6
    Colors.pink, // H 7
    Colors.cyan, // I 8
    Colors.indigo, // J 9
    Colors.lime, // K 10
    Colors.brown, // L 11
    Colors.deepOrange, // M 12
  ];

  @override
  void dispose() {
    _scrollController.dispose();
    _horizontalScrollController.dispose();
    _nonSliverScrollController.dispose();
    super.dispose();
  }

  // --- Swap helpers ---

  void _swap(int slotX, int slotY) {
    setState(() {
      final s = List.of(_slots);
      final tmp = s[slotX];
      s[slotX] = s[slotY];
      s[slotY] = tmp;
      _slots = s;
    });
  }

  void _swapNestedGroups() {
    setState(() {
      _nestedGroupOrder = [_nestedGroupOrder[1], _nestedGroupOrder[0]];
    });
  }

  // --- Widget builders ---

  Widget _item(int slot) {
    final i = _slots[slot];
    return _ItemWidget(
      key: _itemWidgetKeys[i],
      animoveKey: _keys[i],
      color: _colors[i],
      label: _labels[i],
      library: library,
    );
  }

  // Outer animove wrapping the two inner animoves for a nested group.
  // Group 0 → slots 7, 8.  Group 1 → slots 9, 10.
  Widget _nestedGroupWidget(int groupIdx) {
    final first = 7 + groupIdx * 2;
    return createAnimove(
      child: Row(children: [_item(first), _item(first + 1)]),
      key: _nestedGroupKeys[groupIdx],
      tag: 'group-$groupIdx',
    );
  }

  Widget _buttonSection(String label, List<(String, VoidCallback)> buttons) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
          ),
          Expanded(
            child: Wrap(
              spacing: 4,
              runSpacing: 2,
              children: [
                for (final (label, cb) in buttons)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: cb,
                    child: Text(label, style: const TextStyle(fontSize: 11)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Animove Swap Demo')),
      body: createAnimoveFrame(
        child: Column(
          children: [
            // --- Library selector ---
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: SegmentedButton<Library>(
                segments: Library.values
                    .map(
                      (lib) => ButtonSegment(
                        value: lib,
                        label: Text(libraryName(lib)),
                      ),
                    )
                    .toList(),
                selected: {library},
                onSelectionChanged: (sel) =>
                    setState(() => library = sel.first),
              ),
            ),

            // --- Button bars ---
            _buttonSection('Top row', [
              ('B ↔ C (same parent)', () => _swap(1, 2)),
              ('A ↔ B (diff parent)', () => _swap(0, 1)),
            ]),
            _buttonSection('Scroll areas', [
              ('D ↔ E (vert)', () => _swap(3, 4)),
              ('A ↔ D (base↔vert)', () => _swap(0, 3)),
              ('F ↔ G (horiz)', () => _swap(5, 6)),
              ('D ↔ F (vert↔horiz)', () => _swap(3, 5)),
              ('L ↔ M (non-sliver)', () => _swap(11, 12)),
              ('L ↔ D (non-sliver↔vert)', () => _swap(11, 3)),
              ('M ↔ E (non-sliver↔vert)', () => _swap(12, 4)),
              ('L ↔ A (non-sliver↔base)', () => _swap(11, 0)),
            ]),
            _buttonSection('Nested', [
              ('H ↔ I (left group)', () => _swap(7, 8)),
              ('J ↔ K (right group)', () => _swap(9, 10)),
              ('H ↔ J (across groups)', () => _swap(7, 9)),
              ('Groups ↔', _swapNestedGroups),
            ]),

            const Divider(height: 1),

            // --- Top row: A, Row(B, C) ---
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _item(0), // A
                  const SizedBox(width: 16),
                  Row(children: [_item(1), _item(2)]), // B, C
                ],
              ),
            ),

            const Divider(height: 1),

            // --- Nested animoves: outer(H, I)  outer(J, K) ---
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _nestedGroupWidget(_nestedGroupOrder[0]),
                  const SizedBox(width: 16),
                  _nestedGroupWidget(_nestedGroupOrder[1]),
                ],
              ),
            ),

            const Divider(height: 1),

            // --- Three scroll areas side-by-side ---
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Vertical sliver (D, spacer, E)
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) =>
                          createAnimoveSliverFrame(
                            child: CustomScrollView(
                              controller: _scrollController,
                              slivers: [
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: _item(3), // D
                                  ),
                                ),
                                SliverToBoxAdapter(
                                  child: _ScrollSpacer(
                                    span: constraints.maxHeight + 30,
                                  ),
                                ),
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: _item(4), // E
                                  ),
                                ),
                              ],
                            ),
                            controller: _scrollController,
                          ),
                    ),
                  ),

                  const VerticalDivider(width: 1),

                  // Horizontal sliver (F, spacer, G)
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) =>
                          createAnimoveSliverFrame(
                            child: CustomScrollView(
                              controller: _horizontalScrollController,
                              scrollDirection: Axis.horizontal,
                              slivers: [
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: _item(5), // F
                                  ),
                                ),
                                SliverToBoxAdapter(
                                  child: _ScrollSpacer(
                                    span: constraints.maxWidth + 30,
                                    axis: Axis.horizontal,
                                  ),
                                ),
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: _item(6), // G
                                  ),
                                ),
                              ],
                            ),
                            controller: _horizontalScrollController,
                          ),
                    ),
                  ),

                  const VerticalDivider(width: 1),

                  // Non-sliver (SingleChildScrollView) with L, spacer, M
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        reverse: true,
                        child: createAnimoveFrame(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            // mainAxisAlignment: MainAxisAlignment.end,
                            // verticalDirection: VerticalDirection.up,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: _item(11), // L
                              ),
                              _ScrollSpacer(span: constraints.maxHeight + 30),
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: _item(12), // M
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemWidget extends StatefulWidget {
  const _ItemWidget({
    required super.key,
    required this.animoveKey,
    required this.color,
    required this.label,
    required this.library,
  });

  final GlobalKey animoveKey;
  final Color color;
  final String label;
  final Library library;

  @override
  State<_ItemWidget> createState() => _ItemWidgetState();
}

class _ItemWidgetState extends State<_ItemWidget> {
  bool _enabled = true;

  Widget _buildContent() {
    return GestureDetector(
      onTap: () => setState(() => _enabled = !_enabled),
      child: Opacity(
        opacity: _enabled ? 1.0 : 0.4,
        child: AnisizedContainer(
          width: 120,
          height: 50,
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return switch (widget.library) {
      Library.animove => Animove(
        key: widget.animoveKey,
        enabled: _enabled,
        child: _buildContent(),
      ),
      Library.animatedTo => AnimatedTo.spring(
        globalKey: widget.animoveKey,
        enabled: _enabled,
        child: _buildContent(),
      ),
      Library.heroAnimation => HeroAnimation.child(
        tag: widget.label,
        child: _buildContent(),
      ),
    };
  }
}

class _ScrollSpacer extends StatefulWidget {
  const _ScrollSpacer({required this.span, this.axis = Axis.vertical});

  final double span;
  final Axis axis;

  @override
  State<_ScrollSpacer> createState() => _ScrollSpacerState();
}

class _ScrollSpacerState extends State<_ScrollSpacer> {
  bool _short = false;

  @override
  Widget build(BuildContext context) {
    final size = _short ? 60.0 : widget.span;
    return GestureDetector(
      onTap: () => setState(() => _short = !_short),
      child: Container(
        height: widget.axis == Axis.vertical ? size : null,
        width: widget.axis == Axis.horizontal ? size : null,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: const Text(
          'spacer',
          style: TextStyle(color: Colors.grey, fontSize: 14),
        ),
      ),
    );
  }
}
