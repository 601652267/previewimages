import 'package:flutter/material.dart';

import 'repositories/preview_history_store.dart';
import 'widgets/preview_history_tile.dart';

class PreviewHistoryPage extends StatefulWidget {
  const PreviewHistoryPage({super.key, required this.store});

  final PreviewHistoryStore store;

  @override
  State<PreviewHistoryPage> createState() => _PreviewHistoryPageState();
}

class _PreviewHistoryPageState extends State<PreviewHistoryPage> {
  Future<void> _change(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) setState(() {});
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法更新历史记录：$error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.store.entries;
    return Scaffold(
      appBar: AppBar(
        title: Text('历史记录 ${entries.length}/${PreviewHistoryStore.maxEntries}'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新历史记录',
            onPressed: () => _change(widget.store.load),
            icon: const Icon(Icons.refresh),
          ),
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
                return PreviewHistoryTile(
                  entry: entry,
                  onRestore: () => Navigator.of(context).pop(entry),
                  onDelete: () => _change(() => widget.store.remove(entry.id)),
                );
              },
            ),
    );
  }
}
