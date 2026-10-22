import 'dart:io';

import 'package:flutter/material.dart';

import 'preview_history.dart';

class PreviewHistoryPage extends StatefulWidget {
  const PreviewHistoryPage({super.key, required this.store});

  final PreviewHistoryStore store;

  @override
  State<PreviewHistoryPage> createState() => _PreviewHistoryPageState();
}

class _PreviewHistoryPageState extends State<PreviewHistoryPage> {
  Future<void> _change(Future<void> Function() action) async {
    final write = action();
    setState(() {});
    try {
      await write;
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法保存历史记录：$error')),
        );
      }
    }
  }

  String _folderName(String path) {
    final parts =
        path.split(Platform.pathSeparator).where((part) => part.isNotEmpty);
    return parts.isEmpty ? path : parts.last;
  }

  String _date(DateTime value) {
    final date = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.store.entries;
    return Scaffold(
      appBar: AppBar(
        title: Text('历史记录 ${entries.length}/${PreviewHistoryStore.maxEntries}'),
        actions: <Widget>[
          TextButton(
            onPressed:
                entries.isEmpty ? null : () => _change(widget.store.clear),
            child: const Text('清空'),
          ),
        ],
      ),
      body: entries.isEmpty
          ? const Center(
              child: Text('暂无历史记录\n选择图片文件夹后自动保存', textAlign: TextAlign.center),
            )
          : ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final entry = entries[index];
                final folders = entry.regions
                    .where((region) => region.folderPath != null)
                    .map((region) => _folderName(region.folderPath!))
                    .join(' · ');
                final progress = entry.regions
                    .asMap()
                    .entries
                    .where((region) => region.value.folderPath != null)
                    .map((region) =>
                        '区域${region.key + 1}：第${region.value.currentIndex + 1}张')
                    .join(' · ');
                return ListTile(
                  leading: const Icon(Icons.folder_copy_outlined),
                  title: Tooltip(
                    message: entry.regions
                        .where((region) => region.folderPath != null)
                        .map((region) => region.folderPath!)
                        .join('\n'),
                    child: Text(folders,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                  subtitle: Text(
                    '${entry.regions.length} 个区域 · ${_date(entry.updatedAt)}\n$progress',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    tooltip: '删除记录',
                    onPressed: () =>
                        _change(() => widget.store.remove(entry.id)),
                    icon: const Icon(Icons.delete_outline),
                  ),
                  onTap: () => Navigator.of(context).pop(entry),
                );
              },
            ),
    );
  }
}
