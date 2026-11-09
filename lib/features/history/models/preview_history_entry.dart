import 'dart:convert';

import 'preview_history_region.dart';

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
