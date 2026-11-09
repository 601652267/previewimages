import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/image_region_data.dart';
import 'image_region_tile.dart';

class ImageRegionMosaic extends StatelessWidget {
  const ImageRegionMosaic({
    super.key,
    required this.regions,
    this.showProgress = false,
    required this.onPickFolder,
    required this.onPageChanged,
    required this.onOpenPreview,
  });

  final List<ImageRegionData> regions;
  final bool showProgress;
  final ValueChanged<int> onPickFolder;
  final void Function(int regionIndex, int pageIndex) onPageChanged;
  final ValueChanged<int> onOpenPreview;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final rowCounts = _bestRowCounts(
          regions.length,
          Size(constraints.maxWidth, constraints.maxHeight),
        );
        var regionIndex = 0;

        return ColoredBox(
          color: const Color(0xFF09090B),
          child: Column(
            children: <Widget>[
              for (final rowCount in rowCounts)
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (var columnIndex = 0;
                          columnIndex < rowCount;
                          columnIndex++)
                        Expanded(
                          child: ImageRegionTile(
                            key: ValueKey<String>(
                              'region-${regions[regionIndex].id}-'
                              '${regions[regionIndex].revision}',
                            ),
                            regionIndex: regionIndex,
                            region: regions[regionIndex++],
                            showProgress: showProgress,
                            onPickFolder: onPickFolder,
                            onPageChanged: onPageChanged,
                            onOpenPreview: onOpenPreview,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  List<int> _bestRowCounts(int count, Size size) {
    if (count <= 1) {
      return const <int>[1];
    }

    var bestRows = 1;
    var bestScore = double.infinity;
    final safeWidth = math.max(size.width, 1);
    final safeHeight = math.max(size.height, 1);

    for (var rows = 1; rows <= count; rows++) {
      final rowCounts = _rowCountsFor(count, rows);
      final rowHeight = safeHeight / rows;
      var totalAspectScore = 0.0;
      var largestAspectScore = 0.0;

      for (final rowCount in rowCounts) {
        final cellAspectRatio = (safeWidth / rowCount) / rowHeight;
        final aspectScore = math.log(cellAspectRatio).abs();
        totalAspectScore += aspectScore;
        largestAspectScore = math.max(largestAspectScore, aspectScore);
      }

      final averageAspectScore = totalAspectScore / rowCounts.length;
      final balancePenalty = (rowCounts.first - rowCounts.last).abs() * 0.04;
      final score =
          averageAspectScore + largestAspectScore * 0.15 + balancePenalty;

      if (score < bestScore) {
        bestScore = score;
        bestRows = rows;
      }
    }

    return _rowCountsFor(count, bestRows);
  }

  List<int> _rowCountsFor(int count, int rows) {
    final baseCount = count ~/ rows;
    final extraCount = count % rows;

    return List<int>.generate(
      rows,
      (index) => baseCount + (index < extraCount ? 1 : 0),
    );
  }
}
