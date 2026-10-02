import 'package:flutter_test/flutter_test.dart';
import 'package:homebudget_flutter/data/device_settings.dart';

void main() {
  test('device PIN derivation matches an independent PBKDF2 vector', () {
    expect(derivePinHash('1234', List<int>.generate(16, (index) => index)),
      'UHAyHKNNva/pslNx0cD4O8r+Bz+64fInTwCm1saOmJk=');
  });
}
