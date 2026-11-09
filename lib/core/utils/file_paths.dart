import 'dart:io';

String folderName(String? path) {
  if (path == null || path.isEmpty) {
    return '';
  }

  final normalizedPath = normalizePath(path);
  return fileName(normalizedPath);
}

String normalizePath(String path) {
  var normalizedPath = path;
  while (normalizedPath.length > 1 &&
      normalizedPath.endsWith(Platform.pathSeparator)) {
    normalizedPath = normalizedPath.substring(0, normalizedPath.length - 1);
  }
  return normalizedPath;
}

String fileName(String path) {
  final segments = path.split(Platform.pathSeparator);
  if (segments.isEmpty) {
    return path;
  }
  return segments.last;
}
