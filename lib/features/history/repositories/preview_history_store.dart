import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/preview_history_entry.dart';
import 'history_file_storage.dart';

class PreviewHistoryStore {
  PreviewHistoryStore({HistoryFileStorage? storage})
      : _storage = storage ??
            HistoryFileStorage(
              fileProvider: _historyFile,
              initialEntries: _legacyEntries,
            );

  static const maxEntries = 10;
  static const storageKey = 'preview_history_v1';
  static const fileName = 'preview_history_v2.json';

  final HistoryFileStorage _storage;
  final List<PreviewHistoryEntry> _entries = <PreviewHistoryEntry>[];
  Future<void> _pendingOperation = Future<void>.value();

  List<PreviewHistoryEntry> get entries => List.unmodifiable(_entries);

  static Future<File> _historyFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}$fileName');
  }

  static Future<List<PreviewHistoryEntry>> _legacyEntries() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    return HistoryFileStorage.decodeEntries(preferences.getString(storageKey));
  }

  Future<void> load() => _update((_) {});

  Future<void> remember(PreviewHistoryEntry entry) {
    if (entry.regions.every((region) => region.folderPath == null)) {
      return Future<void>.value();
    }
    return _update((latest) {
      latest.removeWhere((existing) => existing.id == entry.id);
      latest.insert(0, entry);
    });
  }

  Future<void> remove(String id) =>
      _update((latest) => latest.removeWhere((entry) => entry.id == id));

  Future<void> clear() => _update((latest) => latest.clear());

  Future<void> _update(void Function(List<PreviewHistoryEntry>) change) {
    final operation = _pendingOperation.then((_) async {
      final updated = await _storage.transaction((latest) {
        change(latest);
        latest.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        final ids = <String>{};
        return latest
            .where((entry) => ids.add(entry.id))
            .take(maxEntries)
            .toList();
      });
      _entries
        ..clear()
        ..addAll(updated);
    });
    _pendingOperation =
        operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return operation;
  }
}
