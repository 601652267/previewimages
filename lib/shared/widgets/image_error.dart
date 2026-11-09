import 'package:flutter/material.dart';

class ImageError extends StatelessWidget {
  const ImageError({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(
        Icons.broken_image_outlined,
        color: Colors.white70,
        size: 42,
      ),
    );
  }
}
