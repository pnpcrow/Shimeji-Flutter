// Unit tests for the pure helpers of the context menu model.
import 'package:flutter_test/flutter_test.dart';

import 'package:shimeji_flutter/src/menu/context_menu_model.dart';

void main() {
  group('splitCamelCase', () {
    test('splits lower->upper boundaries', () {
      expect(splitCamelCase('WalkAbout'), 'Walk About');
    });

    test('keeps IE pairs together like the Java original', () {
      expect(splitCamelCase('PullUpIE'), 'Pull Up IE');
    });

    test('leaves already flat names alone', () {
      expect(splitCamelCase('Fall'), 'Fall');
    });
  });
}
