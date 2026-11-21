import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RegionCountBar extends StatelessWidget {
  const RegionCountBar({
    super.key,
    required this.controller,
    required this.count,
    required this.maxCount,
    required this.onChanged,
    required this.onDecrement,
    required this.onIncrement,
    required this.onOpenHistory,
    required this.showProgress,
    required this.onToggleProgress,
  });

  final TextEditingController controller;
  final int count;
  final int maxCount;
  final ValueChanged<String> onChanged;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final VoidCallback? onOpenHistory;
  final bool showProgress;
  final VoidCallback onToggleProgress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      elevation: 1,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Text('区域数'),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 46,
                    height: 32,
                    child: TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                      ),
                      onChanged: onChanged,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    style: IconButton.styleFrom(
                      minimumSize: const Size(32, 32),
                      padding: const EdgeInsets.all(4),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    iconSize: 20,
                    onPressed: count <= 1 ? null : onDecrement,
                    tooltip: '减少',
                    icon: const Icon(Icons.remove),
                  ),
                  const SizedBox(width: 2),
                  IconButton.filledTonal(
                    style: IconButton.styleFrom(
                      minimumSize: const Size(32, 32),
                      padding: const EdgeInsets.all(4),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    iconSize: 20,
                    onPressed: count >= maxCount ? null : onIncrement,
                    tooltip: '增加',
                    icon: const Icon(Icons.add),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$count/$maxCount',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextButton(
                    onPressed: onOpenHistory,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(36, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('历史'),
                  ),
                  TextButton(
                    onPressed: onToggleProgress,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(36, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor:
                          showProgress ? colors.primary : colors.onSurface,
                      backgroundColor:
                          showProgress ? colors.primaryContainer : null,
                    ),
                    child: const Text('进度'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
