import 'dart:convert';
import 'dart:io';

import '../models/preview_history_entry.dart';

/// Reads and changes shared history while holding an OS file lock.
class HistoryFileStorage {
  HistoryFileStorage({
    required Future<File> Function() fileProvider,
    Future<List<PreviewHistoryEntry>> Function()? initialEntries,
  })  : _fileProvider = fileProvider,
        _initialEntries = initialEntries;

  final Future<File> Function() _fileProvider;
  final Future<List<PreviewHistoryEntry>> Function()? _initialEntries;
  Future<File>? _file;

  // Unix file locks belong to the process, so also serialize store objects in
  // the same isolate. Separate application processes use the OS lock below.
  static final Map<String, Future<void>> _queues = {};

  Future<List<PreviewHistoryEntry>> transaction(
    List<PreviewHistoryEntry> Function(List<PreviewHistoryEntry>) change,
  ) async {
    final file = await (_file ??= _fileProvider());
    final key = file.absolute.path;
    final previous = _queues[key] ?? Future<void>.value();
    final operation = previous.then((_) => _lockedTransaction(file, change));
    final finished =
        operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _queues[key] = finished;
    await finished;
    if (identical(_queues[key], finished)) {
      _queues.remove(key);
    }
    return operation;
  }

  Future<List<PreviewHistoryEntry>> _lockedTransaction(
    File file,
    List<PreviewHistoryEntry> Function(List<PreviewHistoryEntry>) change,
  ) async {
    await file.parent.create(recursive: true);
    // Never delete this lock file: all processes must lock the same file.
    final lock = await File('${file.path}.lock').open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.blockingExclusive);
      final exists = await file.exists();
      final raw = exists ? await file.readAsString() : null;
      final current = exists
          ? decodeEntries(raw)
          : await (_initialEntries?.call() ??
              Future.value(<PreviewHistoryEntry>[]));
      final updated = change(current);
      final encoded = jsonEncode(<String, Object>{
        'version': 2,
        'entries': updated.map((entry) => entry.toJson()).toList(),
      });
      if (raw != encoded) {
        // Complete the new file before replacing the previous history.
        final temporary = File('${file.path}.tmp');
        await temporary.writeAsString(encoded, flush: true);
        await temporary.rename(file.path);
      }
      return updated;
    } finally {
      // Closing the handle also releases the lock after errors or cancellation.
      await lock.close();
    }
  }

  static List<PreviewHistoryEntry> decodeEntries(String? raw) {
    if (raw == null) {
      return <PreviewHistoryEntry>[];
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return <PreviewHistoryEntry>[];
    }
    final rows = decoded is Map ? decoded['entries'] : decoded;
    if (rows is! List) {
      return <PreviewHistoryEntry>[];
    }
    final entries = <PreviewHistoryEntry>[];
    for (final value in rows) {
      try {
        entries.add(PreviewHistoryEntry.fromJson(
          Map<String, dynamic>.from(value as Map),
        ));
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    return entries;
  }
}
