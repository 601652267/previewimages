import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/utils/file_paths.dart';
import 'widgets/current_path_bar.dart';

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
    _currentPath = normalizePath(widget.rootPath);
    unawaited(_loadFolders());
  }

  bool get _canGoUp {
    return normalizePath(_currentPath) != normalizePath(widget.rootPath);
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
      return fileName(a.path).toLowerCase().compareTo(
            fileName(b.path).toLowerCase(),
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
      _currentPath = normalizePath(folder.path);
    });
    unawaited(_loadFolders());
  }

  void _goUp() {
    if (!_canGoUp) {
      return;
    }

    final parentPath = normalizePath(Directory(_currentPath).parent.path);
    final rootPath = normalizePath(widget.rootPath);
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
          CurrentPathBar(path: _currentPath),
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
            fileName(folder.path),
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
