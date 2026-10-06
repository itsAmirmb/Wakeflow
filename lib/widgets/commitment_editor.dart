import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/commitment.dart';
import '../services/day_key.dart';

class CommitmentEditResult {
  final Commitment? saved;
  final bool deleted;

  const CommitmentEditResult({this.saved, this.deleted = false});
}

/// Bottom sheet to add, edit or delete a commitment. [presetDate] starts a new
/// one as a single-day event on that date (used from Start Day).
Future<CommitmentEditResult?> showCommitmentEditor(
  BuildContext context, {
  Commitment? existing,
  DateTime? presetDate,
}) {
  return showModalBottomSheet<CommitmentEditResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _CommitmentForm(existing: existing, presetDate: presetDate),
  );
}

class _CommitmentForm extends StatefulWidget {
  final Commitment? existing;
  final DateTime? presetDate;

  const _CommitmentForm({this.existing, this.presetDate});

  @override
  State<_CommitmentForm> createState() => _CommitmentFormState();
}

class _CommitmentFormState extends State<_CommitmentForm> {
  final _title = TextEditingController();
  late int _start;
  late int _end;
  late bool _recurring;
  late Set<int> _weekdays;
  late DateTime _date;
  String? _error;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _title.text = c?.title ?? '';
    _start = c?.startMinutes ?? 9 * 60;
    _end = c?.endMinutes ?? 10 * 60;
    _recurring = c?.isRecurring ?? widget.presetDate == null;
    _weekdays = {...?c?.weekdays};
    final today = DateTime.now();
    _date = c?.date != null
        ? DateTime.parse(c!.date!)
        : widget.presetDate ?? DateTime(today.year, today.month, today.day);
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickTime({required bool start}) async {
    final value = start ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: value ~/ 60, minute: value % 60),
    );
    if (picked == null || !mounted) return;
    final minutes = picked.hour * 60 + picked.minute;
    setState(() {
      _error = null;
      if (start) {
        _start = minutes;
        // Keep the span valid while the start moves.
        if (_end <= _start) _end = math.min(_start + 60, 1439);
      } else {
        _end = minutes;
      }
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, now.day - 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(first) ? first : _date,
      firstDate: first,
      lastDate: DateTime(now.year + 2, now.month, now.day),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  void _submit() {
    final title = _title.text.trim();
    String? error;
    if (title.isEmpty) {
      error = 'Enter a title';
    } else if (_end <= _start) {
      error = 'The end must be after the start';
    } else if (_recurring && _weekdays.isEmpty) {
      error = 'Pick at least one weekday';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(
      context,
      CommitmentEditResult(
        saved: Commitment(
          id:
              widget.existing?.id ??
              'com_${DateTime.now().microsecondsSinceEpoch}',
          title: title,
          startMinutes: _start,
          endMinutes: _end,
          weekdays: _recurring ? _weekdays : const {},
          date: _recurring ? null : dayKey(_date),
          enabled: widget.existing?.enabled ?? true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Start the week where the locale does (0 = Sunday ... 6 = Saturday).
    final first = MaterialLocalizations.of(context).firstDayOfWeekIndex;
    final weekdayOrder = [
      for (var i = 0; i < 7; i++) (first + i) % 7 == 0 ? 7 : (first + i) % 7,
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.existing == null ? 'New commitment' : 'Edit commitment',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _title,
              maxLength: 40,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'Class, work shift...',
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickTime(start: true),
                    icon: const Icon(Icons.schedule),
                    label: Text('From ${Commitment.hm(_start)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickTime(start: false),
                    icon: const Icon(Icons.schedule),
                    label: Text('To ${Commitment.hm(_end)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Weekly')),
                ButtonSegment(value: false, label: Text('One day')),
              ],
              selected: {_recurring},
              onSelectionChanged: (selection) => setState(() {
                _recurring = selection.first;
                _error = null;
              }),
            ),
            const SizedBox(height: 12),
            if (_recurring)
              Wrap(
                spacing: 8,
                children: [
                  for (final day in weekdayOrder)
                    FilterChip(
                      label: Text(Commitment.weekdayNames[day]!),
                      selected: _weekdays.contains(day),
                      onSelected: (on) => setState(() {
                        on ? _weekdays.add(day) : _weekdays.remove(day);
                        _error = null;
                      }),
                    ),
                ],
              )
            else
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event),
                label: Text(dayKey(_date)),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (widget.existing != null)
                  TextButton.icon(
                    onPressed: () => Navigator.pop(
                      context,
                      const CommitmentEditResult(deleted: true),
                    ),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _submit, child: const Text('Save')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
