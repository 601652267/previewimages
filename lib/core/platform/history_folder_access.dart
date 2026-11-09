import 'dart:io';

import 'package:flutter/services.dart';

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
