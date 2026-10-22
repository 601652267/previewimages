import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:previewimages/main.dart';
import 'package:previewimages/preview_history.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PreviewHistoryEntry entry(int number, {int position = 0}) {
    return PreviewHistoryEntry(
      updatedAt: DateTime(2026, 10, 5, 12, number),
      regions: <PreviewHistoryRegion>[
        PreviewHistoryRegion(
            folderPath: '/images/$number', currentIndex: position),
      ],
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('previewimages/history_folders'),
      (_) async => null,
    );
  });

  test('keeps ten newest entries and persists them across store reloads',
      () async {
    final store = PreviewHistoryStore();
    await store.load();
    for (var index = 0; index < 12; index++) {
      await store.remember(entry(index));
    }
    final restored = PreviewHistoryStore();
    await restored.load();
    expect(restored.entries.length, 10);
    expect(restored.entries.first.regions.single.folderPath, '/images/11');
    expect(restored.entries.last.regions.single.folderPath, '/images/2');
  });

  test('rapid position updates deduplicate and persist the final position',
      () async {
    final store = PreviewHistoryStore();
    await store.load();
    final writes = <Future<void>>[];
    for (var position = 0; position < 20; position++) {
      writes.add(store.remember(entry(1, position: position)));
    }
    await Future.wait(writes);
    final restored = PreviewHistoryStore();
    await restored.load();
    expect(restored.entries.length, 1);
    expect(restored.entries.single.regions.single.currentIndex, 19);
    await restored.remove(restored.entries.single.id);
    await store.load();
    expect(store.entries, isEmpty);
    await store.remember(entry(2));
    await store.clear();
    await restored.load();
    expect(restored.entries, isEmpty);
  });

  test('ignores empty arrangements and malformed stored rows', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      PreviewHistoryStore.storageKey: jsonEncode(<Object?>[
        null,
        <String, Object?>{'regions': 'bad'},
        entry(4).toJson(),
      ]),
    });
    final store = PreviewHistoryStore();
    await store.load();
    expect(store.entries.length, 1);
    await store.remember(PreviewHistoryEntry(
      updatedAt: DateTime.now(),
      regions: const <PreviewHistoryRegion>[PreviewHistoryRegion()],
    ));
    expect(store.entries.length, 1);
  });

  testWidgets('history starts empty and can be opened from the toolbar',
      (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.runAsync(() => tester.tap(find.text('历史')));
    await tester.pumpAndSettle();
    expect(find.text('历史记录 0/10'), findsOneWidget);
    expect(find.text('暂无历史记录\n选择图片文件夹后自动保存'), findsOneWidget);
  });

  testWidgets('restores regions and image identity after files change',
      (tester) async {
    final directory = Directory.systemTemp.createTempSync('preview_history_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
      '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    for (final name in <String>['a', 'b', 'c']) {
      File('${directory.path}${Platform.pathSeparator}$name.png')
          .writeAsBytesSync(bytes);
    }
    final saved = PreviewHistoryEntry(
      updatedAt: DateTime.now(),
      showProgress: true,
      regions: <PreviewHistoryRegion>[
        PreviewHistoryRegion(
          folderPath: directory.path,
          imagePath: '${directory.path}${Platform.pathSeparator}c.png',
          currentIndex: 1,
        ),
        const PreviewHistoryRegion(),
      ],
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      PreviewHistoryStore.storageKey: jsonEncode(<Object>[saved.toJson()]),
    });
    await tester.pumpWidget(const MyApp());
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.runAsync(() => tester.tap(find.text('历史')));
    await tester.pumpAndSettle();
    expect(find.text('历史记录 1/10'), findsOneWidget);
    await tester.tap(find.byType(ListTile));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '2'), findsOneWidget);
    final mosaic =
        tester.widget<ImageRegionMosaic>(find.byType(ImageRegionMosaic));
    expect(mosaic.regions.first.currentIndex, 2);
    expect(mosaic.regions.first.images.length, 3);
    expect(mosaic.regions.last.folderPath, isNull);
    expect(mosaic.showProgress, isTrue);

    await tester.drag(find.byType(PageView).first, const Offset(600, 0));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    final stored = PreviewHistoryStore();
    await tester.runAsync(stored.load);
    expect(stored.entries.single.regions.first.currentIndex, 1);

    await tester.runAsync(() => tester.tap(find.text('历史')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除记录'));
    await tester.pumpAndSettle();
    expect(find.text('历史记录 0/10'), findsOneWidget);
  });

  testWidgets(
      'missing folders show a recoverable message and clamp missing images',
      (tester) async {
    final directory =
        Directory.systemTemp.createTempSync('preview_history_missing_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
      '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    File('${directory.path}${Platform.pathSeparator}only.png')
        .writeAsBytesSync(bytes);
    final saved = PreviewHistoryEntry(
      updatedAt: DateTime.now(),
      regions: <PreviewHistoryRegion>[
        PreviewHistoryRegion(
          folderPath: directory.path,
          imagePath: '${directory.path}${Platform.pathSeparator}deleted.png',
          currentIndex: 100,
        ),
        PreviewHistoryRegion(
            folderPath: '${directory.path}${Platform.pathSeparator}gone',
            currentIndex: 5),
      ],
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      PreviewHistoryStore.storageKey: jsonEncode(<Object>[saved.toJson()]),
    });
    await tester.pumpWidget(const MyApp());
    await tester.runAsync(() async => Future<void>.delayed(Duration.zero));
    await tester.runAsync(() => tester.tap(find.text('历史')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ListTile));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    final mosaic =
        tester.widget<ImageRegionMosaic>(find.byType(ImageRegionMosaic));
    expect(mosaic.regions.first.currentIndex, 0);
    expect(mosaic.regions.last.isLoading, isFalse);
    expect(find.text('文件夹不存在或无访问权限，请重新选择'), findsOneWidget);
    expect(find.text('选择文件夹'), findsOneWidget);
  });
}
