import 'dart:io';

import '../utils/file_paths.dart';

class ImageDirectoryService {
  static Future<List<File>> listImages(String directoryPath) async {
    final directory = Directory(directoryPath);
    final files = <File>[];

    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && _isSupportedImage(entity.path)) {
        files.add(entity);
      }
    }

    files.sort((a, b) {
      return fileName(a.path).toLowerCase().compareTo(
            fileName(b.path).toLowerCase(),
          );
    });
    return files;
  }

  static bool _isSupportedImage(String path) {
    final lowerPath = path.toLowerCase();
    return lowerPath.endsWith('.png') ||
        lowerPath.endsWith('.jpg') ||
        lowerPath.endsWith('.jpeg') ||
        lowerPath.endsWith('.gif') ||
        lowerPath.endsWith('.webp');
  }
}
