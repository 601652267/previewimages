import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:previewimages/features/image_regions/widgets/image_region_mosaic.dart';
import 'package:previewimages/features/history/models/preview_history_entry.dart';
import 'package:previewimages/features/history/models/preview_history_region.dart';
import 'package:previewimages/features/history/repositories/preview_history_store.dart';
import 'package:previewimages/features/history/repositories/history_file_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/history_test_environment.dart';

Future<void> disposeAndDeleteImages(
  WidgetTester tester,
  Directory directory,
) async {
  // Windows keeps files locked while an image read is still in flight.
  await tester.pumpWidget(const SizedBox.shrink());
  PaintingBinding.instance.imageCache
    ..clear()
    ..clearLiveImages();
  await tester.runAsync(() async {
    for (var attempt = 0;; attempt++) {
      try {
        await directory.delete(recursive: true);
        return;
      } on FileSystemException {
        if (!await directory.exists()) {
          return;
        }
        if (attempt >= 19) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  });
}

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

  late Directory historyDirectory;

  setUp(() async {
    historyDirectory = await createHistoryTestDirectory();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('previewimages/history_folders'),
      (_) async => null,
    );
  });

  tearDown(() async {
    await deleteHistoryTestDirectory(historyDirectory);
  });

  test('keeps thirty newest entries and persists them across store reloads',
      () async {
    final store = PreviewHistoryStore();
    await store.load();
    for (var index = 0; index < 32; index++) {
      await store.remember(entry(index));
    }
    final restored = PreviewHistoryStore();
    await restored.load();
    expect(restored.entries.length, 30);
    expect(restored.entries.first.regions.single.folderPath, '/images/31');
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

  test('merges saves from three stores that loaded the same old history',
      () async {
    final stores = List.generate(3, (_) => PreviewHistoryStore());
    await Future.wait(stores.map((store) => store.load()));
    await Future.wait(
        List.generate(3, (index) => stores[index].remember(entry(index))));
    for (final store in stores) {
      await store.load();
      expect(store.entries.length, 3);
      expect(
          store.entries.map((value) => value.regions.single.folderPath).toSet(),
          <String>{'/images/0', '/images/1', '/images/2'});
    }
    await stores.first.remember(entry(1, position: 9));
    await stores.last.load();
    expect(stores.last.entries.length, 3);
    expect(
        stores.last.entries
            .firstWhere((value) => value.id == entry(1).id)
            .regions
            .single
            .currentIndex,
        9);
  });

  test('stale stores cannot resurrect deleted or cleared history', () async {
    final first = PreviewHistoryStore();
    final second = PreviewHistoryStore();
    await first.remember(entry(1));
    await second.load();
    await first.remove(entry(1).id);
    await second.remember(entry(2));
    await first.load();
    expect(first.entries.map((value) => value.id), <String>[entry(2).id]);
    await first.clear();
    await second.remember(entry(3));
    await first.load();
    expect(first.entries.map((value) => value.id), <String>[entry(3).id]);
  });

  test('enforces one shared thirty-entry limit across simultaneous stores',
      () async {
    final stores = List.generate(3, (_) => PreviewHistoryStore());
    await Future.wait(List.generate(
        32, (index) => stores[index % stores.length].remember(entry(index))));
    for (final store in stores) {
      await store.load();
      expect(store.entries.length, 30);
      expect(store.entries.first.id, entry(31).id);
      expect(store.entries.last.id, entry(2).id);
    }
  });

  test('releases the file lock when a transaction fails', () async {
    final file =
        File('${historyDirectory.path}${Platform.pathSeparator}failure.json');
    final storage = HistoryFileStorage(fileProvider: () async => file);
    await expectLater(
        storage.transaction((_) => throw StateError('test failure')),
        throwsStateError);
    final store = PreviewHistoryStore(storage: storage);
    await store.remember(entry(7));
    await store.load();
    expect(store.entries.single.id, entry(7).id);
  });

  test('imports legacy history once without reimporting after clear', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      PreviewHistoryStore.storageKey: jsonEncode([entry(4).toJson()]),
    });
    final first = PreviewHistoryStore();
    await first.load();
    expect(first.entries.single.id, entry(4).id);
    await first.clear();
    final second = PreviewHistoryStore();
    await second.load();
    expect(second.entries, isEmpty);
  });

  test(
      'real processes preserve each others latest progress under concurrent writes',
      () async {
    final configFile = File('.dart_tool/package_config.json').absolute;
    final config = jsonDecode(await configFile.readAsString()) as Map;
    final flutterPackage = (config['packages'] as List)
        .firstWhere((value) => value['name'] == 'flutter') as Map;
    final flutterDirectory = Directory.fromUri(
        configFile.uri.resolve(flutterPackage['rootUri'] as String));
    final dart = File.fromUri(flutterDirectory.uri.resolve(
            '../../bin/cache/dart-sdk/bin/dart${Platform.isWindows ? '.exe' : ''}'))
        .path;
    final file =
        File('${historyDirectory.path}${Platform.pathSeparator}processes.json');
    final processes = <Process>[];
    final outputs = <Future<List<String>>>[];
    final errors = <Future<String>>[];
    final ready = <Future<void>>[];
    for (var index = 0; index < 4; index++) {
      final process = await Process.start(dart, [
        '--packages=${configFile.path}',
        File('test/support/history_process_worker.dart').absolute.path,
        file.path,
        '$index',
        '${PreviewHistoryStore.maxEntries}',
      ]);
      processes.add(process);
      addTearDown(() => process.kill());
      errors.add(process.stderr.transform(utf8.decoder).join());
      final started = Completer<void>();
      ready.add(started.future);
      outputs.add(process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .map((line) {
        if (line == 'READY') started.complete();
        return line;
      }).toList());
    }
    await Future.wait(ready).timeout(const Duration(seconds: 30));
    for (final process in processes) {
      process.stdin.writeln('go');
      await process.stdin.flush();
    }
    final exits =
        await Future.wait(processes.map((process) => process.exitCode))
            .timeout(const Duration(seconds: 30));
    final stderr = await Future.wait(errors);
    expect(exits, everyElement(0), reason: stderr.join('\n'));
    expect(await Future.wait(outputs), everyElement(contains('DONE')));
    final store = PreviewHistoryStore(
        storage: HistoryFileStorage(fileProvider: () async => file));
    await store.load();
    expect(store.entries.length, 4);
    expect(store.entries.map((value) => value.regions.single.currentIndex),
        everyElement(14));
  });

  testWidgets('history starts empty and can be opened from the toolbar',
      (tester) async {
    await pumpHistoryApp(tester);
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await openHistory(tester);
    await tester.pumpAndSettle();
    expect(find.text('历史记录 0/30'), findsOneWidget);
    expect(find.text('暂无历史记录\n选择图片文件夹后自动保存'), findsOneWidget);
  });

  testWidgets('restores regions and image identity after natural sorting',
      (tester) async {
    final directory = Directory.systemTemp.createTempSync('preview_history_');
    addTearDown(() => disposeAndDeleteImages(tester, directory));
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
      '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    for (final name in <String>['1', '2', '10']) {
      File('${directory.path}${Platform.pathSeparator}$name.png')
          .writeAsBytesSync(bytes);
    }
    final saved = PreviewHistoryEntry(
      updatedAt: DateTime.now(),
      showProgress: true,
      regions: <PreviewHistoryRegion>[
        PreviewHistoryRegion(
          folderPath: directory.path,
          imagePath: '${directory.path}${Platform.pathSeparator}10.png',
          currentIndex: 1,
        ),
        const PreviewHistoryRegion(),
      ],
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      PreviewHistoryStore.storageKey: jsonEncode(<Object>[saved.toJson()]),
    });
    await pumpHistoryApp(tester);
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await openHistory(tester);
    await tester.pumpAndSettle();
    expect(find.text('历史记录 1/30'), findsOneWidget);
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
    await flushHistoryIO(tester);
    final stored = PreviewHistoryStore();
    await flushHistoryIO(tester, store: stored);
    expect(stored.entries.single.regions.first.currentIndex, 1);

    await openHistory(tester);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('删除记录'));
    });
    await flushHistoryIO(tester);
    await tester.pumpAndSettle();
    expect(find.text('历史记录 0/30'), findsOneWidget);
    await flushHistoryIO(tester);
  });

  testWidgets(
      'missing folders show a recoverable message and clamp missing images',
      (tester) async {
    final directory =
        Directory.systemTemp.createTempSync('preview_history_missing_');
    addTearDown(() => disposeAndDeleteImages(tester, directory));
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
    await pumpHistoryApp(tester);
    await tester.runAsync(() async => Future<void>.delayed(Duration.zero));
    await openHistory(tester);
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
    await flushHistoryIO(tester);
  });

  testWidgets('history refreshes on opening and on request without polling',
      (tester) async {
    await pumpHistoryApp(tester);
    final second = PreviewHistoryStore();
    await tester.runAsync(() async {
      await second.remember(entry(2));
      await second.remember(entry(3));
    });
    await openHistory(tester);
    expect(find.text('历史记录 2/30'), findsOneWidget);

    await tester.runAsync(() => second.remember(entry(4)));
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('历史记录 2/30'), findsOneWidget);
    await tester.runAsync(() => tester.tap(find.byTooltip('刷新历史记录')));
    await flushHistoryIO(tester);
    expect(find.text('历史记录 3/30'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('清空'));
    });
    await flushHistoryIO(tester);
    await flushHistoryIO(tester, store: second);
    expect(second.entries, isEmpty);
    expect(find.text('历史记录 0/30'), findsOneWidget);
  });
}
