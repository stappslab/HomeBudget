import 'package:flutter_test/flutter_test.dart';
import 'package:homebudget_flutter/utils/money.dart';

void main() {
  group('parseCents', () {
    test('parses decimal commas and whole currency units', () {
      expect(parseCents('12,50'), 1250);
      expect(parseCents('12'), 1200);
    });

    test('rejects malformed or over-precise amounts', () {
      expect(parseCents('12,345'), isNull);
      expect(parseCents('abc'), isNull);
      expect(parseCents('1' * 1000000), isNull);
    });
  });

  test('budget amounts accept whole units and common grouping', () {
    expect(parseBudgetCents('50000'), 5000000);
    expect(parseBudgetCents('50.000'), 5000000);
    expect(parseBudgetCents('50,000'), 5000000);
    expect(parseBudgetCents('50.000,50'), 5000050);
    expect(parseBudgetCents('50,000.50'), 5000050);
    expect(parseBudgetCents('invalid'), isNull);
    expect(parseBudgetCents('1' * 1000000), isNull);
  });

  group('manual exchange rates', () {
    test('parses rates with up to six decimal places', () {
      expect(parseRateMicros('100.43'), 100430000);
      expect(parseRateMicros('0,0085'), 8500);
      expect(parseRateMicros('1'), 1000000);
    });

    test('rejects invalid rates and converts minor units with rounding', () {
      expect(parseRateMicros('0'), isNull);
      expect(parseRateMicros('-1'), isNull);
      expect(parseRateMicros('1.1234567'), isNull);
      expect(parseRateMicros('1' * 1000000), isNull);
      expect(convertCents(2500, 100430000), 251075);
    });
  });
}
