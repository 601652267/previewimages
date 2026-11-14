import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:previewimages/core/services/image_directory_service.dart';
import 'package:previewimages/core/utils/file_name_comparator.dart';
import 'package:previewimages/core/utils/file_paths.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('previewimages_sort_');
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  Future<void> createFiles(List<String> names) async {
    for (final name in names) {
      await File('${directory.path}${Platform.pathSeparator}$name')
          .writeAsString('');
    }
  }

  Future<List<String>> imageNames() async {
    final images = await ImageDirectoryService.listImages(directory.path);
    return images.map((image) => fileName(image.path)).toList();
  }

  test('sorts image names naturally instead of putting 10 before 2', () async {
    await createFiles(<String>[
      '图片20.png',
      '图片2.png',
      '图片10.png',
      '图片1.png',
      'B2.png',
      'a10.PNG',
      'A2.JPG',
      'a1.jpeg',
    ]);

    expect(await imageNames(), <String>[
      'a1.jpeg',
      'A2.JPG',
      'a10.PNG',
      'B2.png',
      '图片1.png',
      '图片2.png',
      '图片10.png',
      '图片20.png',
    ]);
  });

  test('compares numeric parts before padding and handles very large numbers',
      () async {
    final expected = <String>[
      'page1_part2.png',
      'page01_part2.png',
      'page001_part2.png',
      'page1_part10.png',
      'page001_part10.png',
      'page2_part1.png',
      'page9007199254740992.png',
      'page9007199254740993.png',
      'page999999999999999999999999999999999999.png',
    ];
    await createFiles(expected.reversed.toList());

    expect(await imageNames(), expected);
  });

  test('sorts supported images without including directories or other files',
      () async {
    await createFiles(<String>[
      '10.PNG',
      '5.png',
      '4.jpg',
      '3.GIF',
      '2.jpeg',
      '1.webp',
      '0.txt',
      '6.svg',
    ]);
    await Directory('${directory.path}${Platform.pathSeparator}0.png').create();

    expect(await imageNames(), <String>[
      '1.webp',
      '2.jpeg',
      '3.GIF',
      '4.jpg',
      '5.png',
      '10.PNG',
    ]);
  });

  test('accepts empty and single-image directories', () async {
    expect(await imageNames(), isEmpty);
    await createFiles(<String>['only.png']);
    expect(await imageNames(), <String>['only.png']);
  });

  test('uses a deterministic order for case-only and zero-padded names', () {
    final expected = <String>[
      'Image0.png',
      'image0.png',
      'image00.png',
      'image1.png',
      'image01.png',
      'image2.png',
      'image10.png',
    ];
    final sorted = expected.reversed.toList()..sort(compareFileNamesNaturally);
    expect(sorted, expected);
    for (var i = 0; i < expected.length; i++) {
      expect(compareFileNamesNaturally(expected[i], expected[i]), 0);
      for (var j = i + 1; j < expected.length; j++) {
        expect(
            compareFileNamesNaturally(expected[i], expected[j]), lessThan(0));
        expect(compareFileNamesNaturally(expected[j], expected[i]),
            greaterThan(0));
      }
    }
  });
}
