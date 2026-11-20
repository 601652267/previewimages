import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:previewimages/app.dart';
import 'package:previewimages/features/history/repositories/history_file_storage.dart';
import 'package:previewimages/features/history/repositories/preview_history_store.dart';
import 'package:previewimages/features/image_regions/image_regions_page.dart';
import 'package:previewimages/features/image_regions/mixins/preview_history_mixin.dart';

class TestHistoryPathProvider extends PathProviderPlatform {
  TestHistoryPathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

Future<Directory> createHistoryTestDirectory() async {
  final directory =
      await Directory.systemTemp.createTemp('preview_history_store_');
  PathProviderPlatform.instance = TestHistoryPathProvider(directory.path);
  return directory;
}

Future<void> deleteHistoryTestDirectory(Directory directory) async {
  final storage = HistoryFileStorage(
    fileProvider: () async => File(
        '${directory.path}${Platform.pathSeparator}${PreviewHistoryStore.fileName}'),
  );
  await storage.transaction((entries) => entries);
  await directory.delete(recursive: true);
}

PreviewHistoryMixin<ImageRegionsPage> historyState(WidgetTester tester) {
  return tester.state(find.byType(ImageRegionsPage, skipOffstage: false))
      as PreviewHistoryMixin<ImageRegionsPage>;
}

Future<void> pumpHistoryApp(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(const MyApp());
    await historyState(tester).historyLoaded;
  });
  await tester.pump();
}

Future<void> openHistory(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.tap(find.text('历史'));
  });
  await flushHistoryIO(tester);
  await tester.pumpAndSettle();
}

Future<void> flushHistoryIO(WidgetTester tester,
    {PreviewHistoryStore? store}) async {
  var completed = false;
  final operation =
      (store ?? historyState(tester).historyStore).load().whenComplete(() {
    completed = true;
  });
  // File IO is real, while widget callbacks and timers use the fake clock.
  // Alternate event-loop time with frames instead of blocking the fake zone.
  for (var attempt = 0; attempt < 200 && !completed; attempt++) {
    await tester.pump();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
  }
  expect(completed, isTrue, reason: 'History file transactions did not finish');
  await operation;
  await tester.pump();
}
