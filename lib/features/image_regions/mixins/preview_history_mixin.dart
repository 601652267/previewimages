import 'package:flutter/material.dart';

import '../../../core/platform/history_folder_access.dart';
import '../../history/models/preview_history_entry.dart';
import '../../history/repositories/preview_history_store.dart';

/// Coordinates persistence while the owning page supplies its active folders.
mixin PreviewHistoryMixin<T extends StatefulWidget> on State<T> {
  final PreviewHistoryStore historyStore = PreviewHistoryStore();
  late final Future<void> historyLoaded;

  Iterable<String> get activeFolderPaths;

  @override
  void initState() {
    super.initState();
    historyLoaded = _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      await historyStore.load();
    } on Exception catch (error) {
      showHistoryError('无法读取历史记录：$error');
    }
  }

  void showHistoryError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> savePreviewHistory(PreviewHistoryEntry entry) async {
    try {
      await historyLoaded;
      await historyStore.remember(entry);
      await retainHistoryFolders();
    } on Exception catch (error) {
      showHistoryError('无法保存历史记录：$error');
    }
  }

  Future<void> retainHistoryFolders() {
    return HistoryFolderAccess.retain(<String>[
      for (final entry in historyStore.entries)
        for (final region in entry.regions)
          if (region.folderPath != null) region.folderPath!,
      ...activeFolderPaths,
    ]);
  }
}
