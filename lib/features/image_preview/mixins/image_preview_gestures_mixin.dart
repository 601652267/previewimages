import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Owns zoom/pan gestures and disposes the transformation controller.
mixin ImagePreviewGesturesMixin<T extends StatefulWidget> on State<T> {
  double get maxPreviewScale => 5;
  final TransformationController transformationController =
      TransformationController();

  PageController get previewPageController;
  int get currentImageIndex;
  int get imageCount;

  Offset _swipeStart = Offset.zero;
  Offset _swipeEnd = Offset.zero;
  bool _isZoomGesture = false;
  bool _canSwipeNext = false;
  bool _canSwipePrevious = false;
  Offset doubleTapPosition = Offset.zero;

  @override
  void dispose() {
    transformationController.dispose();
    super.dispose();
  }

  void zoomOnDoubleTap() {
    final scale = transformationController.value.getMaxScaleOnAxis();
    if (scale >= maxPreviewScale) {
      return;
    }
    final nextScale = math.min(scale * 1.10, maxPreviewScale);

    final focalPoint = transformationController.toScene(doubleTapPosition);
    transformationController.value = transformationController.value.clone()
      ..translate(focalPoint.dx, focalPoint.dy)
      ..scale(nextScale / scale)
      ..translate(-focalPoint.dx, -focalPoint.dy);
  }

  void startImageGesture(ScaleStartDetails details, Size viewportSize) {
    _swipeStart = details.focalPoint;
    _swipeEnd = details.focalPoint;
    _isZoomGesture = details.pointerCount > 1;
    final matrix = transformationController.value;
    final scale = matrix.getMaxScaleOnAxis();
    final translationX = matrix.getTranslation().x;
    final minTranslationX = viewportSize.width * (1 - scale);
    // A zoomed drag pans the image; only an outward drag starting at an edge
    // can turn the page.
    _canSwipeNext = translationX <= minTranslationX + 1;
    _canSwipePrevious = translationX >= -1;
  }

  void updateImageGesture(ScaleUpdateDetails details) {
    _swipeEnd = details.focalPoint;
    _isZoomGesture = _isZoomGesture ||
        details.pointerCount > 1 ||
        (details.scale - 1).abs() > 0.001;
  }

  void endImageGesture(ScaleEndDetails details) {
    final delta = _swipeEnd - _swipeStart;
    _swipeStart = Offset.zero;
    _swipeEnd = Offset.zero;
    if (_isZoomGesture ||
        delta.dx.abs() < 60 ||
        delta.dx.abs() <= delta.dy.abs()) {
      return;
    }

    if ((delta.dx < 0 && !_canSwipeNext) ||
        (delta.dx > 0 && !_canSwipePrevious)) {
      return;
    }

    goToImage(currentImageIndex + (delta.dx < 0 ? 1 : -1));
  }

  void goToImage(int index) {
    final nextIndex = index.clamp(0, imageCount - 1);
    if (nextIndex != currentImageIndex) {
      previewPageController.animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> confirmResetZoom() async {
    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('还原图片比例'),
        content: const Text('是否还原到最初的比例？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('还原'),
          ),
        ],
      ),
    );

    if (mounted && shouldReset == true) {
      transformationController.value = Matrix4.identity();
    }
  }
}
