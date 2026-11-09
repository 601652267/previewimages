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
