import 'dart:convert';
import 'dart:io';

import 'package:previewimages/features/history/models/preview_history_entry.dart';
import 'package:previewimages/features/history/models/preview_history_region.dart';
import 'package:previewimages/features/history/repositories/history_file_storage.dart';

Future<void> main(List<String> arguments) async {
  final storage =
      HistoryFileStorage(fileProvider: () async => File(arguments[0]));
  stdout.writeln('READY');
  await stdin.transform(utf8.decoder).transform(const LineSplitter()).first;
  for (var index = 0; index < 15; index++) {
    final entry = PreviewHistoryEntry(
      updatedAt: DateTime.now(),
      regions: [
        PreviewHistoryRegion(
            folderPath: '/images/${arguments[1]}', currentIndex: index)
      ],
    );
    await storage.transaction((entries) {
      entries.removeWhere((existing) => existing.id == entry.id);
      entries.insert(0, entry);
      return entries.take(10).toList();
    });
  }
  stdout.writeln('DONE');
}
