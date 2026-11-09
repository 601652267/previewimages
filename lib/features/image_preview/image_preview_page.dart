import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/widgets/image_error.dart';
import 'mixins/image_preview_gestures_mixin.dart';

class ImagePreviewPage extends StatefulWidget {
  const ImagePreviewPage({
    super.key,
    required this.files,
    required this.initialIndex,
    this.onPageChanged,
  });

  final List<File> files;
  final int initialIndex;
  final ValueChanged<int>? onPageChanged;

  @override
  State<ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<ImagePreviewPage>
    with ImagePreviewGesturesMixin<ImagePreviewPage> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  PageController get previewPageController => _pageController;

  @override
  int get currentImageIndex => _currentIndex;

  @override
  int get imageCount => widget.files.length;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.files.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _closePreview() {
    Navigator.of(context).pop(_currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _closePreview();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        extendBody: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.light,
          ),
          foregroundColor: Colors.white,
          leading: IconButton(
            tooltip: '关闭',
            icon: const Icon(Icons.close),
            onPressed: _closePreview,
          ),
          actions: <Widget>[
            IconButton(
              tooltip: '上一张',
              icon: const Icon(Icons.chevron_left),
              onPressed:
                  _currentIndex > 0 ? () => goToImage(_currentIndex - 1) : null,
            ),
            IconButton(
              tooltip: '下一张',
              icon: const Icon(Icons.chevron_right),
              onPressed: _currentIndex < widget.files.length - 1
                  ? () => goToImage(_currentIndex + 1)
                  : null,
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text('${_currentIndex + 1}/${widget.files.length}'),
              ),
            ),
          ],
        ),
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTapDown: (details) {
            doubleTapPosition = details.localPosition;
          },
          onDoubleTap: zoomOnDoubleTap,
          onLongPress: confirmResetZoom,
          child: PageView.builder(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.files.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
              widget.onPageChanged?.call(index);
            },
            itemBuilder: (context, index) {
              return LayoutBuilder(
                builder: (context, constraints) => InteractiveViewer(
                  transformationController: transformationController,
                  minScale: 1,
                  maxScale: maxPreviewScale,
                  onInteractionStart: (details) => startImageGesture(
                    details,
                    constraints.biggest,
                  ),
                  onInteractionUpdate: updateImageGesture,
                  onInteractionEnd: endImageGesture,
                  child: SizedBox.expand(
                    child: Image.file(
                      widget.files[index],
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => const ImageError(),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
