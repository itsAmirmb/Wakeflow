/// Credit rules. Everything is integer "credit seconds" (1 credit = 60 of
/// them) so balances never suffer floating-point drift.
///
/// Earning: [earnPercent] % of the real time a block's timer ran, so
/// 10 minutes on the timer = 1 credit.
class Credits {
  const Credits._();

  static const int earnPercent = 10;
  static const int secondsPerCredit = 60;

  /// Credit seconds earned by [timerSeconds] of real timer time.
  static int earnedSeconds(int timerSeconds) =>
      timerSeconds <= 0 ? 0 : timerSeconds * earnPercent ~/ 100;

  static int costSeconds(int credits) => credits * secondsPerCredit;

  /// Credits with one decimal, rounded DOWN so a balance is never overstated
  /// (e.g. 359 s -> "5.9", not "6.0").
  static String format(int creditSeconds) {
    final tenths = (creditSeconds < 0 ? 0 : creditSeconds) ~/ 6;
    return '${tenths ~/ 10}.${tenths % 10}';
  }
}

class InsufficientCreditsException implements Exception {
  final int balanceSeconds;
  final int costSeconds;
  const InsufficientCreditsException(this.balanceSeconds, this.costSeconds);

  @override
  String toString() => 'Not enough credits.';
}
