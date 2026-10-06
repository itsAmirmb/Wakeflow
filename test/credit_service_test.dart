import 'package:flutter_test/flutter_test.dart';
import 'package:wakeflow/services/credit_service.dart';

void main() {
  test('earns 10% of timer seconds', () {
    expect(Credits.earnedSeconds(600), 60); // 10 min -> 1 credit
    expect(Credits.earnedSeconds(3600), 360); // 1 h -> 6 credits
    expect(Credits.earnedSeconds(0), 0);
    expect(Credits.earnedSeconds(-5), 0);
  });

  test('a 60-credit reward costs 3600 credit seconds', () {
    expect(Credits.costSeconds(60), 3600);
    // 10 hours of timer time earns exactly one movie.
    expect(Credits.earnedSeconds(10 * 3600), Credits.costSeconds(60));
  });

  test('format rounds down so a balance is never overstated', () {
    expect(Credits.format(0), '0.0');
    expect(Credits.format(359), '5.9');
    expect(Credits.format(360), '6.0');
    expect(Credits.format(-10), '0.0');
  });
}
