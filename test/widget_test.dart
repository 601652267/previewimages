import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:previewimages/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pinchImage(
  WidgetTester tester,
  Finder viewer, {
  required double startGap,
  required double endGap,
}) async {
  final center = tester.getCenter(viewer);
  final firstFinger = await tester.startGesture(
    center - Offset(startGap / 2, 0),
    pointer: 1,
  );
  final secondFinger = await tester.startGesture(
    center + Offset(startGap / 2, 0),
    pointer: 2,
  );
  for (var step = 1; step <= 8; step++) {
    final gap = startGap + (endGap - startGap) * step / 8;
    await firstFinger.moveTo(center - Offset(gap / 2, 0));
    await secondFinger.moveTo(center + Offset(gap / 2, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pump(const Duration(milliseconds: 200));
  await firstFinger.up();
  await secondFinger.up();
  await tester.pumpAndSettle();
}

void main() {
  late Directory imageDirectory;
  late List<File> files;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  setUpAll(() {
    imageDirectory = Directory.systemTemp.createTempSync('previewimages_test_');
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
      '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    files = List.generate(
      3,
      (index) =>
          File('${imageDirectory.path}${Platform.pathSeparator}$index.png')
            ..writeAsBytesSync(bytes),
    );
  });

  tearDownAll(() {
    imageDirectory.deleteSync(recursive: true);
  });

  testWidgets('starts with one image region', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('图片预览'), findsOneWidget);
    expect(find.text('区域数'), findsOneWidget);
    expect(find.widgetWithText(TextField, '1'), findsOneWidget);
    expect(find.text('选择文件夹'), findsOneWidget);
    expect(tester.getSize(find.byType(TextField)).height, 32);
    expect(find.byType(Slider), findsNothing);

    await tester.tap(find.text('进度'));
    await tester.pump();
    expect(find.byType(Slider), findsOneWidget);
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);

    await tester.tap(find.text('进度'));
    await tester.pump();
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('progress seeks independently and follows image swipes',
      (tester) async {
    final regions = List.generate(
      2,
      (index) => ImageRegionData(id: index)
        ..folderPath = '/images/folder-$index'
        ..images = files,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          return ImageRegionMosaic(
            regions: regions,
            showProgress: true,
            onPickFolder: (_) {},
            onOpenPreview: (_) {},
            onPageChanged: (regionIndex, pageIndex) {
              setState(() => regions[regionIndex].currentIndex = pageIndex);
            },
          );
        }),
      ),
    ));

    expect(find.text('folder-0'), findsNothing);
    final slider = find.byType(Slider).first;
    await tester
        .tapAt(tester.getRect(slider).centerRight - const Offset(12, 0));
    await tester.pump();
    expect(regions.first.currentIndex, 2);
    expect(regions.last.currentIndex, 0);
    expect(tester.widget<Slider>(slider).value, 2);

    await tester.drag(find.byType(PageView).first, const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(regions.first.currentIndex, 1);
    expect(tester.widget<Slider>(slider).value, 1);
    expect(regions.last.currentIndex, 0);
  });

  testWidgets('preview image extends behind the transparent navigation bar',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ImagePreviewPage(files: files, initialIndex: 0),
    ));

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(scaffold.extendBodyBehindAppBar, isTrue);
    expect(appBar.backgroundColor, Colors.transparent);
    expect(appBar.title, isNull);
    expect(tester.getTopLeft(find.byType(PageView)).dy, 0);
    expect(tester.getSize(find.byType(PageView)),
        tester.getSize(find.byType(Scaffold)));
  });

  testWidgets('preview keeps pinch zoom across pages and confirms reset',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ImagePreviewPage(files: files, initialIndex: 0),
    ));

    final viewer = find.byType(InteractiveViewer).hitTestable();
    final controller =
        tester.widget<InteractiveViewer>(viewer).transformationController!;
    await pinchImage(tester, viewer, startGap: 80, endGap: 240);

    final zoom = controller.value.getMaxScaleOnAxis();
    expect(zoom, greaterThan(1));

    await tester.tap(find.byTooltip('下一张'));
    await tester.pumpAndSettle();
    expect(find.text('2/3'), findsOneWidget);
    expect(controller.value.getMaxScaleOnAxis(), closeTo(zoom, 0.001));

    await tester.tap(find.byTooltip('上一张'));
    await tester.pumpAndSettle();
    expect(find.text('1/3'), findsOneWidget);
    expect(controller.value.getMaxScaleOnAxis(), closeTo(zoom, 0.001));

    await tester.longPress(viewer);
    await tester.pumpAndSettle();
    expect(find.text('是否还原到最初的比例？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(controller.value.getMaxScaleOnAxis(), closeTo(zoom, 0.001));

    await tester.longPress(viewer);
    await tester.pumpAndSettle();
    await tester.tap(find.text('还原'));
    await tester.pumpAndSettle();
    expect(controller.value, Matrix4.identity());
    expect(find.text('1/3'), findsOneWidget);

    await tester.drag(viewer, const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('2/3'), findsOneWidget);
    expect(controller.value.getMaxScaleOnAxis(), 1);
  });

  testWidgets('zoomed image pans freely and shrinks from maximum zoom',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ImagePreviewPage(files: files, initialIndex: 0),
    ));
    final viewer = find.byType(InteractiveViewer).hitTestable();
    final controller =
        tester.widget<InteractiveViewer>(viewer).transformationController!;
    await pinchImage(tester, viewer, startGap: 80, endGap: 400);
    await pinchImage(tester, viewer, startGap: 80, endGap: 400);
    expect(controller.value.getMaxScaleOnAxis(), closeTo(5, 0.001));

    final initialTranslation = controller.value.getTranslation();
    await tester.drag(viewer, const Offset(-120, 0));
    await tester.pumpAndSettle();
    final horizontalTranslation = controller.value.getTranslation();
    expect(horizontalTranslation.x, lessThan(initialTranslation.x));
    expect(find.text('1/3'), findsOneWidget);

    await tester.drag(viewer, const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(controller.value.getTranslation().y,
        greaterThan(horizontalTranslation.y));
    expect(find.text('1/3'), findsOneWidget);

    await pinchImage(tester, viewer, startGap: 400, endGap: 8);
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1, 0.001));
    expect(find.text('1/3'), findsOneWidget);
    expect(controller.value.getTranslation().x, closeTo(0, 0.001));
    expect(controller.value.getTranslation().y, closeTo(0, 0.001));
  });

  testWidgets('zoomed swipes turn pages only when starting at the image edge',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ImagePreviewPage(files: files, initialIndex: 0),
    ));
    final viewer = find.byType(InteractiveViewer).hitTestable();
    final controller =
        tester.widget<InteractiveViewer>(viewer).transformationController!;
    await pinchImage(tester, viewer, startGap: 80, endGap: 240);
    final zoom = controller.value.getMaxScaleOnAxis();
    expect(zoom, greaterThan(1));

    await tester.drag(viewer, const Offset(-1200, 0));
    await tester.pumpAndSettle();
    expect(find.text('1/3'), findsOneWidget);
    await tester.drag(viewer, const Offset(-150, 0));
    await tester.pumpAndSettle();
    expect(find.text('2/3'), findsOneWidget);
    expect(controller.value.getMaxScaleOnAxis(), closeTo(zoom, 0.001));

    await tester.drag(viewer, const Offset(1200, 0));
    await tester.pumpAndSettle();
    expect(find.text('2/3'), findsOneWidget);
    await tester.drag(viewer, const Offset(150, 0));
    await tester.pumpAndSettle();
    expect(find.text('1/3'), findsOneWidget);
    expect(controller.value.getMaxScaleOnAxis(), closeTo(zoom, 0.001));
  });

  testWidgets('double tap zooms by ten percent around the tap up to the limit',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ImagePreviewPage(files: files, initialIndex: 0),
    ));
    final viewer = find.byType(InteractiveViewer).hitTestable();
    final controller =
        tester.widget<InteractiveViewer>(viewer).transformationController!;
    final tapPosition = tester.getCenter(viewer) + const Offset(70, 50);
    final originalScenePoint = controller.toScene(tapPosition);

    Future<void> doubleTapImage() async {
      await tester.tapAt(tapPosition);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(tapPosition);
      await tester.pumpAndSettle();
    }

    await doubleTapImage();
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1.10, 0.00001));
    expect((controller.toScene(tapPosition) - originalScenePoint).distance,
        lessThan(0.00001));
    await doubleTapImage();
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1.21, 0.00001));
    expect(find.text('1/3'), findsOneWidget);

    await tester.tap(find.byTooltip('下一张'));
    await tester.pumpAndSettle();
    expect(find.text('2/3'), findsOneWidget);
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1.21, 0.00001));

    controller.value = Matrix4.identity()
      ..translate(tapPosition.dx * (1 - 4.9), tapPosition.dy * (1 - 4.9))
      ..scale(4.9);
    await tester.pump();
    await doubleTapImage();
    expect(controller.value.getMaxScaleOnAxis(), closeTo(5, 0.00001));
    final cappedTransform = controller.value.clone();
    await doubleTapImage();
    expect(controller.value, cappedTransform);
  });
}
