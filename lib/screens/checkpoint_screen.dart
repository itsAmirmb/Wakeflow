import 'package:flutter/material.dart';

import '../models/block.dart';
import '../models/checkpoint_report.dart';

/// Collects reflection separately from recorded timer progress. Planning is
/// opt-in, and only the injected save boundary can persist anything.
class CheckpointScreen extends StatefulWidget {
  const CheckpointScreen({
    super.key,
    required this.report,
    required this.previewFuture,
    required this.save,
  });

  final CheckpointReport report;
  final List<Block> Function() previewFuture;
  final Future<void> Function(
    Map<String, CheckpointAssessment> assessments,
    String note,
    List<Block>? proposed,
  )
  save;

  @override
  State<CheckpointScreen> createState() => _CheckpointScreenState();
}

class _CheckpointScreenState extends State<CheckpointScreen> {
  final _formKey = GlobalKey<FormState>();
  final _note = TextEditingController();
  final _assessments = <String, CheckpointAssessment>{};
  List<Block>? _proposed;
  bool _saving = false;
  bool _saved = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  bool _validateAssessments() {
    final validFields = _formKey.currentState!.validate();
    final allSelected = widget.report.categories.every(
      (progress) => _assessments.containsKey(progress.category.id),
    );
    if (!allSelected) {
      _showError('Choose an assessment for every category before continuing.');
    }
    return validFields && allSelected;
  }

  void _preview() {
    if (!mounted || _saving || _proposed != null) return;
    if (!_validateAssessments()) return;
    FocusScope.of(context).unfocus();
    try {
      final proposed = List<Block>.unmodifiable(widget.previewFuture());
      setState(() => _proposed = proposed);
    } catch (_) {
      _showError('Could not preview the new plan. Please try again.');
    }
  }

  void _cancelPreview() {
    if (!mounted || _saving) return;
    setState(() => _proposed = null);
  }

  Future<void> _save({required bool withProposal}) async {
    if (!mounted || _saving || _saved) return;
    // Stale button callbacks may not switch between save modes.
    if (withProposal != (_proposed != null)) return;
    if (!_validateAssessments()) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      await widget.save(
        Map<String, CheckpointAssessment>.unmodifiable(_assessments),
        _note.text,
        withProposal ? _proposed : null,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError(
        'Could not save the checkpoint. Your answers are kept. Try again.',
      );
      return;
    }
    if (!mounted) return;
    // Rebuild the PopScope before leaving, keeping duplicate saves disabled.
    setState(() => _saved = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final proposed = _proposed;
    final editing = !_saving && proposed == null;
    return PopScope<bool>(
      canPop: _saved || (!_saving && proposed == null),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_saving && proposed != null) _cancelPreview();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(proposed == null ? 'Checkpoint' : 'New plan preview'),
          leading: BackButton(
            onPressed: _saving
                ? null
                : () {
                    if (proposed != null) {
                      _cancelPreview();
                    } else {
                      Navigator.maybePop(context);
                    }
                  },
          ),
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${widget.report.remainingMinutes} min remaining · '
                'Finish by ${TimeOfDay.fromDateTime(widget.report.dayEnd).format(context)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Reflect on your progress. Reaching a goal does not add timer '
                'minutes. Recorded work and completed history stay unchanged.',
              ),
              const SizedBox(height: 16),
              if (widget.report.categories.isEmpty)
                const Text('No categories to assess.'),
              for (final progress in widget.report.categories)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${progress.category.icon} ${progress.category.name}'
                              .trim(),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text('Target total: ${progress.targetMinutes} min'),
                        Text(
                          'Scheduled till now: ${progress.expectedMinutes} min',
                        ),
                        Text('Actual recorded: ${progress.doneMinutes} min'),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<CheckpointAssessment>(
                          key: ValueKey('assessment-${progress.category.id}'),
                          initialValue: _assessments[progress.category.id],
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Your assessment',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: CheckpointAssessment.reached,
                              child: Text('Reached'),
                            ),
                            DropdownMenuItem(
                              value: CheckpointAssessment.partial,
                              child: Text('Partially reached'),
                            ),
                            DropdownMenuItem(
                              value: CheckpointAssessment.notReached,
                              child: Text('Not reached'),
                            ),
                          ],
                          onChanged: editing
                              ? (value) {
                                  if (value != null) {
                                    setState(() {
                                      _assessments[progress.category.id] =
                                          value;
                                    });
                                  }
                                }
                              : null,
                          validator: (value) => value == null
                              ? 'Choose an assessment for this category.'
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('checkpoint-note'),
                controller: _note,
                readOnly: !editing,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              if (proposed != null) ...[
                const SizedBox(height: 24),
                Text(
                  'Proposed pending blocks',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Text(
                  'Nothing has been saved. Only the future plan will be replaced '
                  'when you confirm; completed history is not editable.',
                ),
                if (!proposed.any((b) => b.status == BlockStatus.pending))
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('No pending blocks in the proposed plan.'),
                  ),
                for (final block in proposed.where(
                  (b) => b.status == BlockStatus.pending,
                ))
                  ListTile(
                    key: ValueKey('proposed-${block.id}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(block.title),
                    subtitle: Text('${block.plannedDurationMinutes} min'),
                  ),
              ],
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_saving) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  const Text('Saving checkpoint…', textAlign: TextAlign.center),
                ],
                if (proposed == null) ...[
                  FilledButton(
                    onPressed: _saving
                        ? null
                        : () => _save(withProposal: false),
                    child: const Text('Save & continue'),
                  ),
                  OutlinedButton(
                    onPressed: _saving ? null : _preview,
                    child: const Text('Preview new plan'),
                  ),
                ] else ...[
                  FilledButton(
                    onPressed: _saving ? null : () => _save(withProposal: true),
                    child: const Text('Confirm & save'),
                  ),
                  OutlinedButton(
                    onPressed: _saving ? null : _cancelPreview,
                    child: const Text('Cancel preview'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
