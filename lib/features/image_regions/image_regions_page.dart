import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/platform/history_folder_access.dart';
import '../../core/services/image_directory_service.dart';
import '../../core/utils/file_paths.dart';
import '../folder_picker/mixins/folder_selection_mixin.dart';
import '../history/models/preview_history_entry.dart';
import '../history/models/preview_history_region.dart';
import '../history/preview_history_page.dart';
import '../image_preview/image_preview_page.dart';
import 'mixins/preview_history_mixin.dart';
import 'models/image_region_data.dart';
import 'widgets/image_region_mosaic.dart';
import 'widgets/region_count_bar.dart';

class ImageRegionsPage extends StatefulWidget {
  const ImageRegionsPage({super.key, this.initialRegionCount = 1});

  final int initialRegionCount;

  @override
  State<ImageRegionsPage> createState() => _ImageRegionsPageState();
}

class _ImageRegionsPageState extends State<ImageRegionsPage>
    with
        PreviewHistoryMixin<ImageRegionsPage>,
        FolderSelectionMixin<ImageRegionsPage> {
  static const int _maxRegionCount = 36;

  late final TextEditingController _regionCountController;
  late List<ImageRegionData> _regions;
  int _nextRegionId = 0;
  bool _showProgress = false;
  bool _isRestoring = false;

  @override
  Iterable<String> get activeFolderPaths =>
      _regions.map((region) => region.folderPath).whereType<String>();

  @override
  void initState() {
    super.initState();
    final initialCount = _normalizeRegionCount(widget.initialRegionCount);
    _regionCountController = TextEditingController(text: '$initialCount');
    _regions = List.generate(initialCount, (_) => _createRegion());
  }

  @override
  void dispose() {
    _regionCountController.dispose();
    super.dispose();
  }

  ImageRegionData _createRegion() {
    return ImageRegionData(id: _nextRegionId++);
  }

  static int _normalizeRegionCount(int count) {
    return count.clamp(1, _maxRegionCount).toInt();
  }

  void _recordHistory() {
    if (_isRestoring || _regions.any((region) => region.isLoading)) {
      return;
    }
    final entry = PreviewHistoryEntry(
      updatedAt: DateTime.now(),
      showProgress: _showProgress,
      regions: _regions.map((region) {
        return PreviewHistoryRegion(
          folderPath: region.folderPath,
          currentIndex: region.currentIndex,
          imagePath: region.images.isEmpty
              ? null
              : region
                  .images[
                      region.currentIndex.clamp(0, region.images.length - 1)]
                  .path,
        );
      }).toList(),
    );
    unawaited(savePreviewHistory(entry));
  }

  Future<void> _openHistory() async {
    await historyLoaded;
    try {
      await historyStore.load();
    } on Exception catch (error) {
      showHistoryError('无法读取历史记录：$error');
      return;
    }
    if (!mounted || _isRestoring) {
      return;
    }
    final entry = await Navigator.of(context).push<PreviewHistoryEntry>(
      MaterialPageRoute<PreviewHistoryEntry>(
        builder: (_) => PreviewHistoryPage(store: historyStore),
      ),
    );
    if (entry != null && mounted) {
      await _restoreHistory(entry);
    } else if (mounted) {
      try {
        await retainHistoryFolders();
      } on Exception catch (error) {
        showHistoryError('无法更新文件夹访问记录：$error');
      }
    }
  }

  Future<void> _restoreHistory(PreviewHistoryEntry entry) async {
    final regions = entry.regions.map((saved) {
      return _createRegion()
        ..folderPath = saved.folderPath
        ..isLoading = saved.folderPath != null;
    }).toList();
    setState(() {
      _isRestoring = true;
      _regions = regions;
      _showProgress = entry.showProgress;
      _regionCountController.text = '${regions.length}';
    });
    await Future.wait(List.generate(regions.length, (index) async {
      final region = regions[index];
      final saved = entry.regions[index];
      if (saved.folderPath == null) {
        return;
      }
      try {
        await HistoryFolderAccess.restore(saved.folderPath!);
        final images =
            await ImageDirectoryService.listImages(saved.folderPath!);
        if (!mounted) {
          return;
        }
        final imageIndex =
            images.indexWhere((image) => image.path == saved.imagePath);
        setState(() {
          region
            ..images = images
            ..currentIndex = images.isEmpty
                ? 0
                : imageIndex >= 0
                    ? imageIndex
                    : saved.currentIndex.clamp(0, images.length - 1)
            ..isLoading = false
            ..message = images.isEmpty ? '没有找到图片' : null
            ..revision = region.revision + 1;
        });
      } on Exception {
        if (mounted) {
          setState(() {
            region
              ..isLoading = false
              ..message = '文件夹不存在或无访问权限，请重新选择'
              ..revision = region.revision + 1;
          });
        }
      }
    }));
    if (mounted) {
      setState(() => _isRestoring = false);
      // Retain the original saved position when a folder is temporarily unavailable.
      await savePreviewHistory(PreviewHistoryEntry(
        updatedAt: DateTime.now(),
        regions: List.generate(regions.length, (index) {
          final region = regions[index];
          return region.images.isEmpty
              ? entry.regions[index]
              : PreviewHistoryRegion(
                  folderPath: region.folderPath,
                  currentIndex: region.currentIndex,
                  imagePath: region.images[region.currentIndex].path,
                );
        }),
        showProgress: entry.showProgress,
      ));
    }
  }

  void _applyRegionCount(String rawValue) {
    if (_isRestoring) {
      _regionCountController.text = '${_regions.length}';
      return;
    }
    final parsed = int.tryParse(rawValue);
    if (parsed == null) {
      return;
    }

    final nextCount = _normalizeRegionCount(parsed);
    if (nextCount.toString() != rawValue) {
      _regionCountController.value = TextEditingValue(
        text: '$nextCount',
        selection: TextSelection.collapsed(offset: '$nextCount'.length),
      );
    }

    if (nextCount == _regions.length) {
      return;
    }

    setState(() {
      if (nextCount > _regions.length) {
        _regions = <ImageRegionData>[
          ..._regions,
          ...List.generate(nextCount - _regions.length, (_) => _createRegion()),
        ];
      } else {
        _regions = _regions.take(nextCount).toList();
      }
    });
    _recordHistory();
  }

  void _decrementRegionCount() {
    _setRegionCount(_regions.length - 1);
  }

  void _incrementRegionCount() {
    _setRegionCount(_regions.length + 1);
  }

  void _setRegionCount(int count) {
    final nextCount = _normalizeRegionCount(count);
    _regionCountController.value = TextEditingValue(
      text: '$nextCount',
      selection: TextSelection.collapsed(offset: '$nextCount'.length),
    );
    _applyRegionCount('$nextCount');
  }

  Future<void> _pickFolder(int regionIndex) async {
    if (_isRestoring ||
        regionIndex >= _regions.length ||
        _regions[regionIndex].isLoading) {
      return;
    }

    final region = _regions[regionIndex];

    setState(() {
      _regions[regionIndex]
        ..isLoading = true
        ..message = null;
    });

    String? directoryPath;
    String? pickMessage;
    try {
      final result = await selectImageFolder();
      directoryPath = result.path == null ? null : normalizePath(result.path!);
      pickMessage = result.message;
    } on Exception catch (error) {
      if (!mounted || !_regions.contains(region)) {
        return;
      }

      setState(() {
        region
          ..isLoading = false
          ..message = '无法打开文件夹选择器：$error';
      });
      return;
    }

    if (!mounted || !_regions.contains(region)) {
      return;
    }

    if (directoryPath == null) {
      setState(() {
        region
          ..isLoading = false
          ..message = pickMessage;
      });
      return;
    }

    try {
      region.folderPath = directoryPath;
      await HistoryFolderAccess.remember(directoryPath);
      final images = await ImageDirectoryService.listImages(directoryPath);
      if (!mounted || !_regions.contains(region)) {
        return;
      }

      setState(() {
        region
          ..folderPath = directoryPath
          ..images = images
          ..currentIndex = 0
          ..isLoading = false
          ..message = images.isEmpty ? '没有找到图片' : null
          ..revision = region.revision + 1;
      });
      _recordHistory();
    } on Exception catch (error) {
      if (!mounted || !_regions.contains(region)) {
        return;
      }

      setState(() {
        region
          ..folderPath = directoryPath
          ..images = const <File>[]
          ..currentIndex = 0
          ..isLoading = false
          ..message = '无法读取文件夹：$error'
          ..revision = region.revision + 1;
      });
    }
  }

  void _setRegionPage(int regionIndex, int pageIndex) {
    if (regionIndex >= _regions.length) {
      return;
    }

    setState(() {
      _regions[regionIndex].currentIndex = pageIndex;
    });
    _recordHistory();
  }

  Future<void> _openPreview(int regionIndex) async {
    if (regionIndex >= _regions.length) {
      return;
    }

    final region = _regions[regionIndex];
    if (region.images.isEmpty) {
      return;
    }

    final previewIndex = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        builder: (_) {
          return ImagePreviewPage(
            files: region.images,
            initialIndex: region.currentIndex,
            onPageChanged: (index) {
              if (_regions.contains(region)) {
                region.currentIndex = index;
                _recordHistory();
              }
            },
          );
        },
      ),
    );

    if (!mounted || previewIndex == null || !_regions.contains(region)) {
      return;
    }

    setState(() {
      region
        ..currentIndex = previewIndex
        ..revision = region.revision + 1;
    });
    _recordHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('图片预览'),
        centerTitle: false,
        actions: <Widget>[
          TextButton.icon(
            onPressed: _isRestoring ? null : _openHistory,
            icon: const Icon(Icons.history, size: 20),
            label: const Text('历史'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _showProgress = !_showProgress;
              });
              _recordHistory();
            },
            style: TextButton.styleFrom(
              foregroundColor: _showProgress
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurface,
              backgroundColor: _showProgress
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
            ),
            child: const Text('进度'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: <Widget>[
          RegionCountBar(
            controller: _regionCountController,
            count: _regions.length,
            maxCount: _maxRegionCount,
            onChanged: _applyRegionCount,
            onDecrement: _decrementRegionCount,
            onIncrement: _incrementRegionCount,
          ),
          Expanded(
            child: ImageRegionMosaic(
              regions: _regions,
              showProgress: _showProgress,
              onPickFolder: _pickFolder,
              onPageChanged: _setRegionPage,
              onOpenPreview: _openPreview,
            ),
          ),
        ],
      ),
    );
  }
}
