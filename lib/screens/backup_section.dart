import 'package:flutter/material.dart';

import '../services/active_day.dart';
import '../services/backup_service.dart';
import '../services/database_service.dart';
import '../services/file_transfer.dart';
import '../services/notification_service.dart';
import '../services/theme_controller.dart';
import 'home_screen.dart';

/// Settings section: export everything to a file, or restore from one.
class BackupSection extends StatefulWidget {
  const BackupSection({super.key});

  @override
  State<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<BackupSection> {
  bool _busy = false;

  Future<void> _export() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final text = await BackupService.export(DatabaseService.instance);
      final saved = await FileTransfer.saveText(
        name: BackupService.suggestedFileName(DateTime.now()),
        text: text,
      );
      if (saved) {
        messenger.showSnackBar(const SnackBar(content: Text('Backup saved.')));
      }
    } on FileTransferException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not create the backup.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final text = await FileTransfer.pickText();
      if (text == null) return; // cancelled
      final backup = BackupService.parse(text);
      if (!mounted) return;
      final confirmed = await _confirm(backup.summary);
      if (confirmed != true) return;

      await BackupService.restore(DatabaseService.instance, backup);
      await _refreshAfterRestore();
      // Start from a clean UI on the restored data.
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
        (route) => false,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Backup restored.')),
      );
    } on BackupException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } on FileTransferException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Import failed. Your data was not changed.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Theme and reminders come from the restored data, not the old one.
  Future<void> _refreshAfterRestore() async {
    final db = DatabaseService.instance;
    final settings = await db.getSettings();
    ThemeController.instance.setFromStored(settings.themeMode);
    try {
      final notifications = NotificationService.instance;
      await notifications.cancelAll();
      await notifications.scheduleWakeReminder(
        hour: settings.wakeReminderHour,
        minute: settings.wakeReminderMinute,
      );
      final day = await ActiveDay.resolve(db, DateTime.now());
      await notifications.scheduleForBlocks(await db.getBlocksForDay(day));
    } catch (_) {
      // Reminders are renewed the next time the app opens; the data itself
      // is already restored.
    }
  }

  Future<bool?> _confirm(BackupSummary summary) {
    String plural(int n, String one, String many) => n == 1 ? '1 $one' : '$n $many';
    final date = summary.exportedAt?.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final from = date == null
        ? ''
        : 'Backup from ${date.year}-${two(date.month)}-${two(date.day)} '
              '${two(date.hour)}:${two(date.minute)}\n\n';
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace all data?'),
        content: Text(
          '$from'
          '${plural(summary.categories, 'category', 'categories')} · '
          '${plural(summary.days, 'day', 'days')} of history · '
          '${plural(summary.notes, 'note', 'notes')} · '
          '${plural(summary.commitments, 'commitment', 'commitments')}\n\n'
          'Importing replaces everything currently in WakeFlow on this '
          'device: routines, history, categories, notes, settings and '
          'credits. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 8, 4),
          child: SizedBox(
            height: 40,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Backup',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        ListTile(
          leading: const Icon(Icons.upload_file_outlined),
          title: const Text('Export backup'),
          subtitle: const Text('Save all your data to a file'),
          enabled: !_busy,
          onTap: _export,
        ),
        ListTile(
          leading: const Icon(Icons.download_outlined),
          title: const Text('Import backup'),
          subtitle: const Text('Restore from a backup file'),
          enabled: !_busy,
          onTap: _import,
        ),
      ],
    );
  }
}
