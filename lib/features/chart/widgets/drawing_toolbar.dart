import 'package:flutter/material.dart';

import '../drawing/drawings.dart';

/// Picks a drawing tool for the chart, and deletes drawings. Shows what the
/// picked tool expects next.
class DrawingToolbar extends StatelessWidget {
  const DrawingToolbar({super.key, required this.controller});

  final DrawingController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final tool = controller.tool;
        final hint = switch (tool) {
          DrawingTool.horizontalLine => 'Tap a price level',
          DrawingTool.trendLine when controller.draft != null =>
            'Tap the second point',
          DrawingTool.trendLine => 'Tap two points, or drag',
          null when controller.selectedIndex != null =>
            'Drag the line or its ends to move it',
          null => null,
        };
        return Row(
          children: [
            IconButton(
              key: const ValueKey('tool-horizontal-line'),
              tooltip: 'Horizontal line',
              isSelected: tool == DrawingTool.horizontalLine,
              icon: const Icon(Icons.horizontal_rule),
              onPressed: () =>
                  controller.selectTool(DrawingTool.horizontalLine),
            ),
            IconButton(
              key: const ValueKey('tool-trend-line'),
              tooltip: 'Trend line',
              isSelected: tool == DrawingTool.trendLine,
              icon: const Icon(Icons.trending_up),
              onPressed: () => controller.selectTool(DrawingTool.trendLine),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hint ?? '',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            IconButton(
              tooltip: 'Delete drawing',
              icon: const Icon(Icons.delete_outline),
              onPressed: controller.selectedIndex == null
                  ? null
                  : controller.deleteSelected,
            ),
            IconButton(
              tooltip: 'Remove all drawings',
              icon: const Icon(Icons.layers_clear_outlined),
              onPressed: controller.drawings.isEmpty
                  ? null
                  : controller.clear,
            ),
          ],
        );
      },
    );
  }
}
