import 'dart:io';

class ImageRegionData {
  ImageRegionData({required this.id});

  final int id;
  String? folderPath;
  List<File> images = const <File>[];
  int currentIndex = 0;
  bool isLoading = false;
  String? message;
  int revision = 0;
}
