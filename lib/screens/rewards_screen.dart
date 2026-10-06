import 'package:flutter/material.dart';

import '../models/reward.dart';
import '../services/credit_service.dart';
import '../services/database_service.dart';

/// Credit balance, redeemable rewards and redemption history.
class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  final DatabaseService _db = DatabaseService.instance;
  int _balance = 0;
  List<Map<String, Object?>> _history = const [];
  bool _loading = true;
  bool _redeeming = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final balance = await _db.getCreditBalance();
      final history = await _db.getRedemptions();
      if (!mounted) return;
      setState(() {
        _balance = balance;
        _history = history;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Could not load credits.');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _redeem(Reward reward) async {
    if (_redeeming) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Redeem ${reward.title}?'),
        content: Text(
          'Spend ${reward.costCredits} credits for ${reward.description}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Redeem'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _redeeming = true);
    try {
      await _db.redeemReward(reward);
      _snack('Enjoy: ${reward.description}!');
    } on InsufficientCreditsException {
      _snack('Not enough credits yet.');
    } catch (_) {
      _snack('Could not redeem. Please try again.');
    } finally {
      if (mounted) setState(() => _redeeming = false);
    }
    await _load();
  }

  static String _stamp(String iso) {
    final t = DateTime.tryParse(iso)?.toLocal();
    if (t == null) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text('Credits', style: text.labelLarge),
                  const SizedBox(height: 4),
                  Text(
                    Credits.format(_balance),
                    style: text.displayMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You earn ${Credits.earnPercent}% of your timer time '
                    '(10 minutes on the timer = 1 credit). '
                    'A running block counts once you pause or finish it.',
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Rewards', style: text.titleMedium),
          const SizedBox(height: 8),
          for (final reward in kRewards) _rewardCard(context, reward),
          const SizedBox(height: 16),
          Text('Redeemed', style: text.titleMedium),
          const SizedBox(height: 8),
          if (_history.isEmpty)
            Text(
              'Nothing redeemed yet.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            )
          else
            for (final row in _history)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle_outline),
                title: Text('${row['rewardTitle'] ?? 'Reward'}'),
                subtitle: Text(_stamp('${row['createdAt']}')),
                trailing: Text(
                  '-${Credits.format(-((row['creditSeconds'] as int?) ?? 0))}',
                ),
              ),
        ],
      ),
    );
  }

  Widget _rewardCard(BuildContext context, Reward reward) {
    final cost = Credits.costSeconds(reward.costCredits);
    final canAfford = _balance >= cost;
    final progress = (_balance / cost).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(reward.icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reward.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(reward.description),
                    ],
                  ),
                ),
                Text('${reward.costCredits} credits'),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: Semantics(
                button: true,
                label: 'Redeem ${reward.title}',
                child: FilledButton(
                  onPressed: canAfford && !_redeeming
                      ? () => _redeem(reward)
                      : null,
                  child: Text(canAfford ? 'Redeem' : 'Not enough credits'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
