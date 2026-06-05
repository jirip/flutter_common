import 'package:flutter_test/flutter_test.dart';
import 'package:jirip_app/jirip_app.dart';

void main() {
  group('Updater banner state', () {
    test('idle does not show banner', () {
      final updater = Updater(appKey: 'test');
      expect(updater.shouldShowBanner, isFalse);
    });

    test('dismiss with no available state is a no-op', () {
      final updater = Updater(appKey: 'test');
      updater.dismissCurrent();
      expect(updater.shouldShowBanner, isFalse);
    });
  });
}
