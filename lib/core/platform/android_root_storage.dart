import 'package:flutter/services.dart';

class AndroidRootStorage {
  static const MethodChannel _channel = MethodChannel('previewimages/storage');

  static Future<String?> getStorageRoot() {
    return _channel.invokeMethod<String>('getStorageRoot');
  }

  static Future<bool> hasRootStorageAccess() async {
    return await _channel.invokeMethod<bool>('hasRootStorageAccess') ?? false;
  }

  static Future<void> requestRootStorageAccess() {
    return _channel.invokeMethod<void>('requestRootStorageAccess');
  }
}
