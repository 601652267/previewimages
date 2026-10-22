import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PreviewHistoryRegion {
  const PreviewHistoryRegion({
    this.folderPath,
    this.imagePath,
    this.currentIndex = 0,
  });

  final String? folderPath;
  final String? imagePath;
  final int currentIndex;

  Map<String, Object?> toJson() => <String, Object?>{
        'folderPath': folderPath,
        'imagePath': imagePath,
        'currentIndex': currentIndex,
      };

  factory PreviewHistoryRegion.fromJson(Map<String, dynamic> json) {
    return PreviewHistoryRegion(
      folderPath: json['folderPath'] as String?,
      imagePath: json['imagePath'] as String?,
      currentIndex: (json['currentIndex'] as int? ?? 0).clamp(0, 1 << 30),
    );
  }
}

class PreviewHistoryEntry {
  PreviewHistoryEntry({
    required this.updatedAt,
    required List<PreviewHistoryRegion> regions,
    this.showProgress = false,
  }) : regions = List.unmodifiable(regions);

  final DateTime updatedAt;
  final List<PreviewHistoryRegion> regions;
  final bool showProgress;

  // Browsing the same arrangement updates its progress instead of adding a row.
  String get id =>
      jsonEncode(regions.map((region) => region.folderPath).toList());

  Map<String, Object?> toJson() => <String, Object?>{
        'updatedAt': updatedAt.toIso8601String(),
        'regions': regions.map((region) => region.toJson()).toList(),
        'showProgress': showProgress,
      };

  factory PreviewHistoryEntry.fromJson(Map<String, dynamic> json) {
    final regions = (json['regions'] as List<dynamic>)
        .map((value) => PreviewHistoryRegion.fromJson(
              Map<String, dynamic>.from(value as Map),
            ))
        .toList();
    if (regions.isEmpty ||
        regions.length > 36 ||
        regions.every((region) => region.folderPath == null)) {
      throw const FormatException('Invalid preview regions');
    }
    return PreviewHistoryEntry(
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      regions: regions,
      showProgress: json['showProgress'] as bool? ?? false,
    );
  }
}

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

class HistoryFolderAccess {
  static const _channel = MethodChannel('previewimages/history_folders');

  static Future<void> remember(String path) async {
    if (Platform.isMacOS) {
      await _channel.invokeMethod<void>('rememberFolder', path);
    }
  }

  static Future<void> restore(String path) async {
    if (Platform.isMacOS) {
      await _channel.invokeMethod<void>('restoreFolderAccess', path);
    }
  }

  static Future<void> retain(Iterable<String> paths) async {
    if (Platform.isMacOS) {
      await _channel.invokeMethod<void>(
          'retainFolders', paths.toSet().toList());
    }
  }
}
