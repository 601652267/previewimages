import 'package:flutter/material.dart';

class RegionIconButton extends StatelessWidget {
  const RegionIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: 0.62),
        foregroundColor: Colors.white,
      ),
      tooltip: tooltip,
      icon: Icon(icon),
      onPressed: onPressed,
    );
  }
}
