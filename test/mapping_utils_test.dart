import 'package:flutter_test/flutter_test.dart';
import 'package:ledsync/core/mapping_utils.dart';

void main() {
  group('setOptionalMapping', () {
    test('adds mapping when value is non-empty', () {
      final out = setOptionalMapping({}, key: 'com.example.app', value: 'Breathing');
      expect(out['com.example.app'], 'Breathing');
    });

    test('removes mapping when value is null', () {
      final out = setOptionalMapping(
        {'com.example.app': 'Breathing'},
        key: 'com.example.app',
        value: null,
      );
      expect(out.containsKey('com.example.app'), isFalse);
    });

    test('removes mapping when value is blank', () {
      final out = setOptionalMapping(
        {'com.example.app': 'Breathing'},
        key: 'com.example.app',
        value: '   ',
      );
      expect(out.containsKey('com.example.app'), isFalse);
    });
  });
}
