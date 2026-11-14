final _nameParts = RegExp(r'[0-9]+|[^0-9]+');
final _leadingZeros = RegExp(r'^0+');

/// Compares names without case sensitivity, treating digit runs as numbers.
/// Numeric ties use fewer leading zeros, then original spelling for stability.
int compareFileNamesNaturally(String left, String right) {
  final leftParts = _nameParts.allMatches(left.toLowerCase()).toList();
  final rightParts = _nameParts.allMatches(right.toLowerCase()).toList();
  var paddingOrder = 0;

  for (var index = 0;
      index < leftParts.length && index < rightParts.length;
      index++) {
    final leftPart = leftParts[index].group(0)!;
    final rightPart = rightParts[index].group(0)!;
    final int order;
    if (_isDigitRun(leftPart) && _isDigitRun(rightPart)) {
      final leftNumber = leftPart.replaceFirst(_leadingZeros, '');
      final rightNumber = rightPart.replaceFirst(_leadingZeros, '');
      // Comparing significant digits avoids integer overflow or precision loss.
      final lengthOrder = leftNumber.length.compareTo(rightNumber.length);
      order =
          lengthOrder != 0 ? lengthOrder : leftNumber.compareTo(rightNumber);
      if (paddingOrder == 0) {
        paddingOrder = leftPart.length.compareTo(rightPart.length);
      }
    } else {
      order = leftPart.compareTo(rightPart);
    }
    if (order != 0) {
      return order;
    }
  }

  final partCountOrder = leftParts.length.compareTo(rightParts.length);
  if (partCountOrder != 0) {
    return partCountOrder;
  }
  return paddingOrder != 0 ? paddingOrder : left.compareTo(right);
}

bool _isDigitRun(String part) {
  final first = part.codeUnitAt(0);
  return first >= 0x30 && first <= 0x39;
}
