import 'package:animove/animove.dart';
import 'package:flutter/material.dart';

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

// Items: a=0, b=1, c=2, d=3, e=4
// Layout:
//   Column(
//     Row(A, Row(B, C)),
//     CustomScrollView(D, <spacer>, E),
//   )

class SwapDemo extends StatefulWidget {
  const SwapDemo({super.key});

  @override
  State<SwapDemo> createState() => _SwapDemoState();
}

class _SwapDemoState extends State<SwapDemo> {
  final _keys = List.generate(7, (i) => GlobalKey(debugLabel: 'item-$i'));
  final _scrollController = ScrollController();
  final _horizontalScrollController = ScrollController();

  // Positions: which item index is at each slot.
  // Slots: 0=A, 1=B, 2=C, 3=D, 4=E
  late List<int> _slots = [0, 1, 2, 3, 4, 5, 6];

  final _labels = ['A', 'B', 'C', 'D', 'E', 'F', 'G'];
  final _colors = [
    Colors.red,
    Colors.orange,
    Colors.teal,
    Colors.blue,
    Colors.purple,
    Colors.green,
    Colors.yellow,
  ];

  @override
  void dispose() {
    _scrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  void _swap(int slotX, int slotY) {
    setState(() {
      final newSlots = List.of(_slots);
      final temp = newSlots[slotX];
      newSlots[slotX] = newSlots[slotY];
      newSlots[slotY] = temp;
      _slots = newSlots;
    });
  }

  Widget _item(int slot) {
    final i = _slots[slot];
    return Animove(
      key: _keys[i],
      child: Container(
        width: 120,
        height: 50,
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: _colors[i],
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          _labels[i],
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Animove Swap Demo')),
      body: AnimoveFrame(
        child: Column(
          children: [
            // --- Button bar ---
            Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton(
                    onPressed: () => _swap(1, 2),
                    child: const Text('B ↔ C (same parent)'),
                  ),
                  ElevatedButton(
                    onPressed: () => _swap(0, 1),
                    child: const Text('A ↔ B (diff parent)'),
                  ),
                  ElevatedButton(
                    onPressed: () => _swap(3, 4),
                    child: const Text('D ↔ E (in scroll)'),
                  ),
                  ElevatedButton(
                    onPressed: () => _swap(0, 3),
                    child: const Text('A ↔ D (out of scroll)'),
                  ),
                  ElevatedButton(
                    onPressed: () => _swap(5, 6),
                    child: const Text('F ↔ G (horizontal scroll)'),
                  ),
                  ElevatedButton(
                    onPressed: () => _swap(3, 5),
                    child: const Text('D ↔ F (between scrolls)'),
                  ),
                ],
              ),
            ),
            const Divider(),

            // --- Top row: A, Row(B, C) ---
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _item(0), // A
                  const SizedBox(width: 16),
                  Row(
                    children: [
                      _item(1), // B
                      _item(2), // C
                    ],
                  ),
                ],
              ),
            ),
            const Divider(),

            // --- Scrollable area: D, spacer, E ---
            Expanded(
              child: AnimoveSliverFrame(
                controller: _scrollController,
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
                      child: Container(
                        height: 600,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'Scroll spacer\n(600px tall)',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
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
              ),
            ),
            Expanded(
              child: AnimoveSliverFrame(
                controller: _horizontalScrollController,
                child: CustomScrollView(
                  controller: _horizontalScrollController,
                  scrollDirection: Axis.horizontal,
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: _item(5),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Container(
                        width: 600,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'Scroll spacer\n(600px wide)',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: _item(6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
