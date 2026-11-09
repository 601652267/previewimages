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
  });

  final TextEditingController controller;
  final int count;
  final int maxCount;
  final ValueChanged<String> onChanged;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 1,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: <Widget>[
              const Text('区域数'),
              const SizedBox(width: 10),
              SizedBox(
                width: 76,
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
              const SizedBox(width: 8),
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
              const SizedBox(width: 4),
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
              const Spacer(),
              Text(
                '$count/$maxCount',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
