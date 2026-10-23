import 'package:flutter/material.dart';

import '../models/view_model.dart';
import '../theme.dart';
import '../ui/tv/tv_focusable.dart';

class LayoutBar extends StatelessWidget {
  const LayoutBar({
    super.key,
    required this.gridSize,
    required this.onSelected,
    required this.mainStream,
    required this.onStreamSelected,
    required this.onShowAll,
    this.onSaveView,
  });

  final GridSize gridSize;
  final ValueChanged<GridSize> onSelected;
  final bool mainStream;
  final ValueChanged<bool> onStreamSelected;
  final VoidCallback onShowAll;
  final VoidCallback? onSaveView;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF111318),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
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
            TvFocusable(
              borderRadius: BorderRadius.circular(18),
              backgroundColor: const Color(0xFF1D2026),
              onTap: onShowAll,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.view_module_outlined, size: 16),
                    SizedBox(width: 5),
                    Text('Todas', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(value: false, label: Text('Substream')),
                ButtonSegment<bool>(value: true, label: Text('Principal')),
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
            const SizedBox(width: 20),
            if (onSaveView != null)
              TextButton.icon(
                onPressed: onSaveView,
                icon: const Icon(Icons.bookmark_add_outlined, size: 17),
                label: const Text(
                  'Guardar vista',
                  style: TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
