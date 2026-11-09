import 'dart:io';

import 'package:flutter/material.dart';

import '../models/preview_history_entry.dart';

class PreviewHistoryTile extends StatelessWidget {
  const PreviewHistoryTile(
      {super.key,
      required this.entry,
      required this.onRestore,
      required this.onDelete});

  final PreviewHistoryEntry entry;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

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
        child: Text(folders, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
      subtitle: Text(
        '${entry.regions.length} 个区域 · ${_date(entry.updatedAt)}\n$progress',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: IconButton(
        tooltip: '删除记录',
        onPressed: onDelete,
        icon: const Icon(Icons.delete_outline),
      ),
      onTap: onRestore,
    );
  }
}
