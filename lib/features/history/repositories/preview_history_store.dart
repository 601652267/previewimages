import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/preview_history_entry.dart';

class PreviewHistoryStore {
  static const maxEntries = 10;
  static const storageKey = 'preview_history_v1';

  final List<PreviewHistoryEntry> _entries = <PreviewHistoryEntry>[];
  Future<void> _pendingWrite = Future<void>.value();

  List<PreviewHistoryEntry> get entries => List.unmodifiable(_entries);

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(storageKey);
    if (raw == null) {
      return;
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return;
    }
    if (decoded is! List) {
      return;
    }
    final loaded = <PreviewHistoryEntry>[];
    for (final value in decoded) {
      try {
        loaded.add(PreviewHistoryEntry.fromJson(
          Map<String, dynamic>.from(value as Map),
        ));
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    loaded.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _entries.clear();
    final ids = <String>{};
    _entries
        .addAll(loaded.where((entry) => ids.add(entry.id)).take(maxEntries));
  }

  Future<void> remember(PreviewHistoryEntry entry) {
    if (entry.regions.every((region) => region.folderPath == null)) {
      return Future<void>.value();
    }
    _entries.removeWhere((existing) => existing.id == entry.id);
    _entries.insert(0, entry);
    if (_entries.length > maxEntries) {
      _entries.removeRange(maxEntries, _entries.length);
    }
    return _persist();
  }

  Future<void> remove(String id) {
    _entries.removeWhere((entry) => entry.id == id);
    return _persist();
  }

  Future<void> clear() {
    _entries.clear();
    return _persist();
  }

  Future<void> _persist() {
    final raw = jsonEncode(_entries.map((entry) => entry.toJson()).toList());
    // Serialize writes so rapid swipes cannot overwrite a newer position.
    final write = _pendingWrite.then((_) async {
      final preferences = await SharedPreferences.getInstance();
      if (!await preferences.setString(storageKey, raw)) {
        throw Exception('无法保存历史记录');
      }
    });
    _pendingWrite =
        write.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return write;
  }
}
