import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Preferences and the optional app-lock verifier for this device only.
class DeviceSettings {
  const DeviceSettings({FlutterSecureStorage storage = const FlutterSecureStorage()})
      : _storage = storage;

  final FlutterSecureStorage _storage;

  Future<bool> darkThemeEnabled() async =>
      (await _storage.read(key: 'dark_theme')) != 'false';

  Future<void> setDarkThemeEnabled(bool value) =>
      _storage.write(key: 'dark_theme', value: value.toString());

  Future<bool> biometricLockEnabled() async =>
      (await _storage.read(key: 'biometric_lock')) == 'true';

  Future<void> setBiometricLockEnabled(bool value) =>
      _storage.write(key: 'biometric_lock', value: value.toString());

  Future<bool> hasPin() async =>
      (await _storage.read(key: 'pin_verifier')) != null;

  Future<void> setPin(String pin) async {
    if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) {
      throw const FormatException('PIN must contain 4 to 8 digits.');
    }
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final hash = await Isolate.run(() => derivePinHash(pin, salt));
    await _storage.write(key: 'pin_verifier',
      value: jsonEncode({'salt': base64Encode(salt), 'hash': hash}));
  }

  Future<bool> verifyPin(String pin) async {
    final raw = await _storage.read(key: 'pin_verifier');
    if (raw == null || !RegExp(r'^\d{4,8}$').hasMatch(pin)) return false;
    try {
      final verifier = jsonDecode(raw) as Map<String, dynamic>;
      final expected = verifier['hash'] as String;
      final salt = base64Decode(verifier['salt'] as String);
      final actual = await Isolate.run(() => derivePinHash(pin, salt));
      if (actual.length != expected.length) return false;
      var difference = 0;
      for (var index = 0; index < actual.length; index++) {
        difference |= actual.codeUnitAt(index) ^ expected.codeUnitAt(index);
      }
      return difference == 0;
    } catch (_) {
      return false;
    }
  }
}

String derivePinHash(String pin, List<int> salt) {
  const iterations = 120000;
  final hmac = Hmac(sha256, utf8.encode(pin));
  var block = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
  final derived = Uint8List.fromList(block);
  for (var round = 1; round < iterations; round++) {
    block = hmac.convert(block).bytes;
    for (var index = 0; index < derived.length; index++) {
      derived[index] ^= block[index];
    }
  }
  return base64Encode(derived);
}
