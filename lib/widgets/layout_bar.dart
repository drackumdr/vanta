import 'package:flutter/material.dart';

import '../models/view_model.dart';
import '../theme.dart';

class LayoutBar extends StatelessWidget {
  const LayoutBar({
    super.key,
    required this.gridSize,
    required this.onSelected,
    required this.mainStream,
    required this.onStreamSelected,
    this.onSaveView,
  });

  final GridSize gridSize;
  final ValueChanged<GridSize> onSelected;
  final bool mainStream;
  final ValueChanged<bool> onStreamSelected;
  final VoidCallback? onSaveView;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF111318),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          for (final size in GridSize.values) ...[
            VantaTheme.layoutPill(
              label: '${size.count}',
              selected: gridSize == size,
              onTap: () => onSelected(size),
            ),
            const SizedBox(width: 8),
          ],
          const SizedBox(width: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment<bool>(
                value: false,
                label: Text('Substream'),
              ),
              ButtonSegment<bool>(
                value: true,
                label: Text('Principal'),
              ),
            ],
            selected: {mainStream},
            onSelectionChanged: (selection) {
              onStreamSelected(selection.first);
            },
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStateProperty.all(
                const TextStyle(fontSize: 11),
              ),
            ),
          ),
          const Spacer(),
          if (onSaveView != null)
            TextButton.icon(
              onPressed: onSaveView,
              icon: const Icon(Icons.bookmark_add_outlined, size: 17),
              label: const Text('Guardar vista', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
