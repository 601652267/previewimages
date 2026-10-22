import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'preview_history.dart';
import 'preview_history_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Preview Images',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
        useMaterial3: true,
      ),
      home: const ImageRegionsPage(initialRegionCount: 1),
    );
  }
}

class ImageRegionsPage extends StatefulWidget {
  const ImageRegionsPage({super.key, this.initialRegionCount = 1});

  final int initialRegionCount;

  @override
  State<ImageRegionsPage> createState() => _ImageRegionsPageState();
}

class _ImageRegionsPageState extends State<ImageRegionsPage> {
  static const int _maxRegionCount = 36;

  late final TextEditingController _regionCountController;
  late List<ImageRegionData> _regions;
  int _nextRegionId = 0;
  bool _showProgress = false;
  final PreviewHistoryStore _history = PreviewHistoryStore();
  late final Future<void> _historyLoaded;
  bool _isRestoring = false;

  @override
  void initState() {
    super.initState();
    final initialCount = _normalizeRegionCount(widget.initialRegionCount);
    _regionCountController = TextEditingController(text: '$initialCount');
    _regions = List.generate(initialCount, (_) => _createRegion());
    _historyLoaded = _loadHistory();
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

  Future<void> _loadHistory() async {
    try {
      await _history.load();
    } on Exception catch (error) {
      _showHistoryError('无法读取历史记录：$error');
    }
  }

  void _showHistoryError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
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
    unawaited(_saveHistory(entry));
  }

  Future<void> _saveHistory(PreviewHistoryEntry entry) async {
    try {
      await _historyLoaded;
      await _history.remember(entry);
      await _retainHistoryFolders();
    } on Exception catch (error) {
      _showHistoryError('无法保存历史记录：$error');
    }
  }

  Future<void> _retainHistoryFolders() {
    return HistoryFolderAccess.retain(<String>[
      for (final entry in _history.entries)
        for (final region in entry.regions)
          if (region.folderPath != null) region.folderPath!,
      for (final region in _regions)
        if (region.folderPath != null) region.folderPath!,
    ]);
  }

  Future<void> _openHistory() async {
    await _historyLoaded;
    if (!mounted || _isRestoring) {
      return;
    }
    final entry = await Navigator.of(context).push<PreviewHistoryEntry>(
      MaterialPageRoute<PreviewHistoryEntry>(
        builder: (_) => PreviewHistoryPage(store: _history),
      ),
    );
    if (entry != null && mounted) {
      await _restoreHistory(entry);
    } else if (mounted) {
      try {
        await _retainHistoryFolders();
      } on Exception catch (error) {
        _showHistoryError('无法更新文件夹访问记录：$error');
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
        final images = await _listImages(saved.folderPath!);
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
      await _saveHistory(PreviewHistoryEntry(
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
      final result = await _selectFolder();
      directoryPath = result.path == null ? null : _normalizePath(result.path!);
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
      final images = await _listImages(directoryPath);
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

  Future<_FolderPickResult> _selectFolder() async {
    if (Platform.isAndroid) {
      return _selectAndroidRootFolder();
    }

    final directoryPath = await FilePicker.getDirectoryPath(
      dialogTitle: '选择图片文件夹',
    );
    return _FolderPickResult(path: directoryPath);
  }

  Future<_FolderPickResult> _selectAndroidRootFolder() async {
    final hasAccess = await _AndroidRootStorage.hasRootStorageAccess();

    if (!hasAccess) {
      if (!mounted) {
        return const _FolderPickResult();
      }

      final shouldOpenSettings = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('需要根目录访问权限'),
            content: const Text('请在系统设置中允许所有文件访问权限，开启后返回应用再选择文件夹。'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('去开启'),
              ),
            ],
          );
        },
      );

      if (shouldOpenSettings == true) {
        await _AndroidRootStorage.requestRootStorageAccess();
      }

      return const _FolderPickResult(
        message: '请开启所有文件访问权限后再次选择文件夹',
      );
    }

    final rootPath =
        await _AndroidRootStorage.getStorageRoot() ?? '/storage/emulated/0';

    if (!mounted) {
      return const _FolderPickResult();
    }

    final directoryPath = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => AndroidRootFolderPickerPage(rootPath: rootPath),
      ),
    );

    return _FolderPickResult(path: directoryPath);
  }

  Future<List<File>> _listImages(String directoryPath) async {
    final directory = Directory(directoryPath);
    final files = <File>[];

    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && _isSupportedImage(entity.path)) {
        files.add(entity);
      }
    }

    files.sort((a, b) {
      return _fileName(a.path).toLowerCase().compareTo(
            _fileName(b.path).toLowerCase(),
          );
    });
    return files;
  }

  bool _isSupportedImage(String path) {
    final lowerPath = path.toLowerCase();
    return lowerPath.endsWith('.png') ||
        lowerPath.endsWith('.jpg') ||
        lowerPath.endsWith('.jpeg') ||
        lowerPath.endsWith('.gif') ||
        lowerPath.endsWith('.webp');
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
          _RegionCountBar(
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

class ImageRegionData {
  ImageRegionData({required this.id});

  final int id;
  String? folderPath;
  List<File> images = const <File>[];
  int currentIndex = 0;
  bool isLoading = false;
  String? message;
  int revision = 0;
}

class _FolderPickResult {
  const _FolderPickResult({this.path, this.message});

  final String? path;
  final String? message;
}

class _AndroidRootStorage {
  static const MethodChannel _channel = MethodChannel('previewimages/storage');

  static Future<String?> getStorageRoot() {
    return _channel.invokeMethod<String>('getStorageRoot');
  }

  static Future<bool> hasRootStorageAccess() async {
    return await _channel.invokeMethod<bool>('hasRootStorageAccess') ?? false;
  }

  static Future<void> requestRootStorageAccess() {
    return _channel.invokeMethod<void>('requestRootStorageAccess');
  }
}

class _RegionCountBar extends StatelessWidget {
  const _RegionCountBar({
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

class ImageRegionMosaic extends StatelessWidget {
  const ImageRegionMosaic({
    super.key,
    required this.regions,
    this.showProgress = false,
    required this.onPickFolder,
    required this.onPageChanged,
    required this.onOpenPreview,
  });

  final List<ImageRegionData> regions;
  final bool showProgress;
  final ValueChanged<int> onPickFolder;
  final void Function(int regionIndex, int pageIndex) onPageChanged;
  final ValueChanged<int> onOpenPreview;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final rowCounts = _bestRowCounts(
          regions.length,
          Size(constraints.maxWidth, constraints.maxHeight),
        );
        var regionIndex = 0;

        return ColoredBox(
          color: const Color(0xFF09090B),
          child: Column(
            children: <Widget>[
              for (final rowCount in rowCounts)
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (var columnIndex = 0;
                          columnIndex < rowCount;
                          columnIndex++)
                        Expanded(
                          child: ImageRegionTile(
                            key: ValueKey<String>(
                              'region-${regions[regionIndex].id}-'
                              '${regions[regionIndex].revision}',
                            ),
                            regionIndex: regionIndex,
                            region: regions[regionIndex++],
                            showProgress: showProgress,
                            onPickFolder: onPickFolder,
                            onPageChanged: onPageChanged,
                            onOpenPreview: onOpenPreview,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  List<int> _bestRowCounts(int count, Size size) {
    if (count <= 1) {
      return const <int>[1];
    }

    var bestRows = 1;
    var bestScore = double.infinity;
    final safeWidth = math.max(size.width, 1);
    final safeHeight = math.max(size.height, 1);

    for (var rows = 1; rows <= count; rows++) {
      final rowCounts = _rowCountsFor(count, rows);
      final rowHeight = safeHeight / rows;
      var totalAspectScore = 0.0;
      var largestAspectScore = 0.0;

      for (final rowCount in rowCounts) {
        final cellAspectRatio = (safeWidth / rowCount) / rowHeight;
        final aspectScore = math.log(cellAspectRatio).abs();
        totalAspectScore += aspectScore;
        largestAspectScore = math.max(largestAspectScore, aspectScore);
      }

      final averageAspectScore = totalAspectScore / rowCounts.length;
      final balancePenalty = (rowCounts.first - rowCounts.last).abs() * 0.04;
      final score =
          averageAspectScore + largestAspectScore * 0.15 + balancePenalty;

      if (score < bestScore) {
        bestScore = score;
        bestRows = rows;
      }
    }

    return _rowCountsFor(count, bestRows);
  }

  List<int> _rowCountsFor(int count, int rows) {
    final baseCount = count ~/ rows;
    final extraCount = count % rows;

    return List<int>.generate(
      rows,
      (index) => baseCount + (index < extraCount ? 1 : 0),
    );
  }
}

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
            _EmptyRegion(
              message: region.message,
              folderName: _folderName(region.folderPath),
              onPickFolder: () => widget.onPickFolder(widget.regionIndex),
            )
          else
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: () => widget.onOpenPreview(widget.regionIndex),
              child: PageView.builder(
                controller: _pageController,
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
                      return const _ImageError();
                    },
                  );
                },
              ),
            ),
          Positioned(
            left: 8,
            top: 8,
            child: _InfoPill(
              text: images.isEmpty
                  ? '区域 ${widget.regionIndex + 1}'
                  : '${currentIndex + 1}/${images.length}',
            ),
          ),
          Positioned(
            right: 6,
            top: 6,
            child: _RoundIconButton(
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

class _EmptyRegion extends StatelessWidget {
  const _EmptyRegion({
    required this.message,
    required this.folderName,
    required this.onPickFolder,
  });

  final String? message;
  final String folderName;
  final VoidCallback onPickFolder;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onPickFolder,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.add_photo_alternate_outlined,
                size: 40,
                color: colorScheme.primary,
              ),
              const SizedBox(height: 10),
              Text(
                '选择文件夹',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                    ),
              ),
              if (message != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFE4E4E7),
                      ),
                ),
              ] else if (folderName.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  folderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFA1A1AA),
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class AndroidRootFolderPickerPage extends StatefulWidget {
  const AndroidRootFolderPickerPage({super.key, required this.rootPath});

  final String rootPath;

  @override
  State<AndroidRootFolderPickerPage> createState() =>
      _AndroidRootFolderPickerPageState();
}

class _AndroidRootFolderPickerPageState
    extends State<AndroidRootFolderPickerPage> {
  late String _currentPath;
  var _folders = <Directory>[];
  var _isLoading = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    _currentPath = _normalizePath(widget.rootPath);
    unawaited(_loadFolders());
  }

  bool get _canGoUp {
    return _normalizePath(_currentPath) != _normalizePath(widget.rootPath);
  }

  Future<void> _loadFolders() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    final folders = <Directory>[];
    try {
      await for (final entity
          in Directory(_currentPath).list(followLinks: false)) {
        if (entity is Directory) {
          folders.add(entity);
        }
      }
    } on FileSystemException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _folders = const <Directory>[];
        _isLoading = false;
        _message = '无法读取目录：${error.message}';
      });
      return;
    }

    folders.sort((a, b) {
      return _fileName(a.path).toLowerCase().compareTo(
            _fileName(b.path).toLowerCase(),
          );
    });

    if (!mounted) {
      return;
    }

    setState(() {
      _folders = folders;
      _isLoading = false;
      _message = folders.isEmpty ? '没有可访问的子文件夹' : null;
    });
  }

  void _openFolder(Directory folder) {
    setState(() {
      _currentPath = _normalizePath(folder.path);
    });
    unawaited(_loadFolders());
  }

  void _goUp() {
    if (!_canGoUp) {
      return;
    }

    final parentPath = _normalizePath(Directory(_currentPath).parent.path);
    final rootPath = _normalizePath(widget.rootPath);
    if (parentPath != rootPath &&
        !parentPath.startsWith('$rootPath${Platform.pathSeparator}')) {
      return;
    }

    setState(() {
      _currentPath = parentPath;
    });
    unawaited(_loadFolders());
  }

  void _selectCurrentFolder() {
    Navigator.of(context).pop(_currentPath);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: _canGoUp ? '返回上级' : '关闭',
          icon: Icon(_canGoUp ? Icons.arrow_back : Icons.close),
          onPressed: _canGoUp ? _goUp : () => Navigator.of(context).pop(),
        ),
        title: const Text('选择根目录文件夹'),
        actions: <Widget>[
          IconButton(
            tooltip: '选择当前文件夹',
            icon: const Icon(Icons.check),
            onPressed: _selectCurrentFolder,
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _CurrentPathBar(path: _currentPath),
          Expanded(
            child: _buildFolderList(context),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: _selectCurrentFolder,
            icon: const Icon(Icons.check),
            label: const Text('选择当前文件夹'),
          ),
        ),
      ),
    );
  }

  Widget _buildFolderList(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_message != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _message!,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: _folders.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final folder = _folders[index];
        return ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: Text(
            _fileName(folder.path),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openFolder(folder),
        );
      },
    );
  }
}

class _CurrentPathBar extends StatelessWidget {
  const _CurrentPathBar({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: <Widget>[
            const Icon(Icons.storage, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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

class _ImagePreviewPageState extends State<ImagePreviewPage> {
  static const double _maxScale = 5;
  late final PageController _pageController;
  final TransformationController _transformationController =
      TransformationController();
  late int _currentIndex;
  Offset _swipeStart = Offset.zero;
  Offset _swipeEnd = Offset.zero;
  bool _isZoomGesture = false;
  bool _canSwipeNext = false;
  bool _canSwipePrevious = false;
  Offset _doubleTapPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.files.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _closePreview() {
    Navigator.of(context).pop(_currentIndex);
  }

  void _zoomOnDoubleTap() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    if (scale >= _maxScale) {
      return;
    }
    final nextScale = math.min(scale * 1.10, _maxScale);

    final focalPoint = _transformationController.toScene(_doubleTapPosition);
    _transformationController.value = _transformationController.value.clone()
      ..translate(focalPoint.dx, focalPoint.dy)
      ..scale(nextScale / scale)
      ..translate(-focalPoint.dx, -focalPoint.dy);
  }

  void _startImageGesture(ScaleStartDetails details, Size viewportSize) {
    _swipeStart = details.focalPoint;
    _swipeEnd = details.focalPoint;
    _isZoomGesture = details.pointerCount > 1;
    final matrix = _transformationController.value;
    final scale = matrix.getMaxScaleOnAxis();
    final translationX = matrix.getTranslation().x;
    final minTranslationX = viewportSize.width * (1 - scale);
    // A zoomed drag pans the image; only an outward drag starting at an edge
    // can turn the page.
    _canSwipeNext = translationX <= minTranslationX + 1;
    _canSwipePrevious = translationX >= -1;
  }

  void _updateImageGesture(ScaleUpdateDetails details) {
    _swipeEnd = details.focalPoint;
    _isZoomGesture = _isZoomGesture ||
        details.pointerCount > 1 ||
        (details.scale - 1).abs() > 0.001;
  }

  void _endImageGesture(ScaleEndDetails details) {
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

    _goToImage(_currentIndex + (delta.dx < 0 ? 1 : -1));
  }

  void _goToImage(int index) {
    final nextIndex = index.clamp(0, widget.files.length - 1);
    if (nextIndex != _currentIndex) {
      _pageController.animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _confirmResetZoom() async {
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
      _transformationController.value = Matrix4.identity();
    }
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
              onPressed: _currentIndex > 0
                  ? () => _goToImage(_currentIndex - 1)
                  : null,
            ),
            IconButton(
              tooltip: '下一张',
              icon: const Icon(Icons.chevron_right),
              onPressed: _currentIndex < widget.files.length - 1
                  ? () => _goToImage(_currentIndex + 1)
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
            _doubleTapPosition = details.localPosition;
          },
          onDoubleTap: _zoomOnDoubleTap,
          onLongPress: _confirmResetZoom,
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
                  transformationController: _transformationController,
                  minScale: 1,
                  maxScale: _maxScale,
                  onInteractionStart: (details) => _startImageGesture(
                    details,
                    constraints.biggest,
                  ),
                  onInteractionUpdate: _updateImageGesture,
                  onInteractionEnd: _endImageGesture,
                  child: SizedBox.expand(
                    child: Image.file(
                      widget.files[index],
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => const _ImageError(),
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

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.text,
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.white,
              ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
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

class _ImageError extends StatelessWidget {
  const _ImageError();

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

String _folderName(String? path) {
  if (path == null || path.isEmpty) {
    return '';
  }

  final normalizedPath = _normalizePath(path);
  return _fileName(normalizedPath);
}

String _normalizePath(String path) {
  var normalizedPath = path;
  while (normalizedPath.length > 1 &&
      normalizedPath.endsWith(Platform.pathSeparator)) {
    normalizedPath = normalizedPath.substring(0, normalizedPath.length - 1);
  }
  return normalizedPath;
}

String _fileName(String path) {
  final segments = path.split(Platform.pathSeparator);
  if (segments.isEmpty) {
    return path;
  }
  return segments.last;
}
