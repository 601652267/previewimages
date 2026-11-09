import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/file_paths.dart';
import '../../../shared/widgets/image_error.dart';
import '../models/image_region_data.dart';
import 'empty_image_region.dart';
import 'region_icon_button.dart';
import 'region_info_pill.dart';

class ImageRegionTile extends StatefulWidget {
  const ImageRegionTile({
    super.key,
    required this.regionIndex,
    required this.region,
    this.showProgress = false,
    required this.onPickFolder,
    required this.onPageChanged,
    required this.onOpenPreview,
  });

  final int regionIndex;
  final ImageRegionData region;
  final bool showProgress;
  final ValueChanged<int> onPickFolder;
  final void Function(int regionIndex, int pageIndex) onPageChanged;
  final ValueChanged<int> onOpenPreview;

  @override
  State<ImageRegionTile> createState() => _ImageRegionTileState();
}

class _ImageRegionTileState extends State<ImageRegionTile> {
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      initialPage: _safeInitialPage,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  int get _safeInitialPage {
    final imageCount = widget.region.images.length;
    if (imageCount == 0) {
      return 0;
    }
    return widget.region.currentIndex.clamp(0, imageCount - 1).toInt();
  }

  void _seekToImage(double value) {
    final index = value.round();
    if (_pageController.hasClients && index != widget.region.currentIndex) {
      _pageController.jumpToPage(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final region = widget.region;
    final images = region.images;
    final scrollBehavior = ScrollConfiguration.of(context);
    final currentIndex = images.isEmpty
        ? 0
        : region.currentIndex.clamp(0, images.length - 1).toInt();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF111113),
        border: Border.all(color: const Color(0xFF27272A), width: 0.5),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (region.isLoading)
            const Center(child: CircularProgressIndicator())
          else if (images.isEmpty)
            EmptyImageRegion(
              message: region.message,
              folderName: folderName(region.folderPath),
              onPickFolder: () => widget.onPickFolder(widget.regionIndex),
            )
          else
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: () => widget.onOpenPreview(widget.regionIndex),
              child: PageView.builder(
                controller: _pageController,
                scrollBehavior: scrollBehavior.copyWith(
                  dragDevices: <PointerDeviceKind>{
                    ...scrollBehavior.dragDevices,
                    PointerDeviceKind.mouse,
                  },
                ),
                itemCount: images.length,
                onPageChanged: (pageIndex) {
                  widget.onPageChanged(widget.regionIndex, pageIndex);
                },
                itemBuilder: (context, index) {
                  return Image.file(
                    images[index],
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) {
                      return const ImageError();
                    },
                  );
                },
              ),
            ),
          Positioned(
            left: 8,
            top: 8,
            child: RegionInfoPill(
              text: images.isEmpty
                  ? '区域 ${widget.regionIndex + 1}'
                  : '${currentIndex + 1}/${images.length}',
            ),
          ),
          Positioned(
            right: 6,
            top: 6,
            child: RegionIconButton(
              tooltip: '选择文件夹',
              icon: Icons.folder_open,
              onPressed: () => widget.onPickFolder(widget.regionIndex),
            ),
          ),
          if (widget.showProgress)
            Positioned(
              left: 4,
              right: 4,
              bottom: 4,
              height: 32,
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.62),
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 10),
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white38,
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    value: currentIndex.toDouble(),
                    max: math.max(1, images.length - 1).toDouble(),
                    divisions: images.length > 1 ? images.length - 1 : null,
                    onChanged: !region.isLoading && images.length > 1
                        ? _seekToImage
                        : null,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
