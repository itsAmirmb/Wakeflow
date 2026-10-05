import 'package:flutter/material.dart';

import '../models/block.dart';
import '../models/checkpoint_report.dart';
import '../services/routine_engine.dart';
import '../widgets/block_status_style.dart';

/// Collects reflection separately from recorded timer progress. Planning is
/// opt-in, and only the injected save boundary can persist anything.
class CheckpointScreen extends StatefulWidget {
  const CheckpointScreen({
    super.key,
    required this.report,
    required this.previewFuture,
    required this.save,
    this.distillPreview,
    this.saveDistill,
  });

  final CheckpointReport report;
  final List<Block> Function() previewFuture;
  final Future<void> Function(
    Map<String, CheckpointAssessment> assessments,
    String note,
    List<Block>? proposed,
  )
  save;

  /// Optional: lets the review end with a distillation (keep real work, drop
  /// the rest) instead of re-planning. The Distill button only shows when
  /// both callbacks are provided.
  final DistillResult Function()? distillPreview;
  final Future<void> Function(
    Map<String, CheckpointAssessment> assessments,
    String note,
    DistillResult result,
  )?
  saveDistill;

  @override
  State<CheckpointScreen> createState() => _CheckpointScreenState();
}

class _CheckpointScreenState extends State<CheckpointScreen> {
  final _formKey = GlobalKey<FormState>();
  final _note = TextEditingController();
  final _assessments = <String, CheckpointAssessment>{};
  List<Block>? _proposed;
  DistillResult? _distill;
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
    if (!mounted || _saving || _proposed != null || _distill != null) return;
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
    setState(() {
      _proposed = null;
      _distill = null;
    });
  }

  void _previewDistill() {
    if (!mounted || _saving || _proposed != null || _distill != null) return;
    if (!_validateAssessments()) return;
    FocusScope.of(context).unfocus();
    try {
      final result = widget.distillPreview!();
      if (result.discarded.isEmpty) {
        _showError('Nothing to distill — every block already holds real progress.');
        return;
      }
      setState(() => _distill = result);
    } catch (_) {
      _showError('Could not preview the distillation. Please try again.');
    }
  }

  Future<void> _saveDistill() async {
    final distill = _distill;
    if (!mounted || _saving || _saved || distill == null) return;
    if (!_validateAssessments()) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      await widget.saveDistill!(
        Map<String, CheckpointAssessment>.unmodifiable(_assessments),
        _note.text,
        distill,
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
    setState(() => _saved = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _save({required bool withProposal}) async {
    if (!mounted || _saving || _saved) return;
    // Stale button callbacks may not switch between save modes.
    if (_distill != null || withProposal != (_proposed != null)) return;
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
    final distill = _distill;
    final inPreview = proposed != null || distill != null;
    final editing = !_saving && !inPreview;
    return PopScope<bool>(
      canPop: _saved || (!_saving && !inPreview),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_saving && inPreview) _cancelPreview();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            distill != null
                ? 'Distill preview'
                : proposed == null
                ? 'Checkpoint'
                : 'New plan preview',
          ),
          leading: BackButton(
            onPressed: _saving
                ? null
                : () {
                    if (inPreview) {
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
              if (distill != null) ...[
                const SizedBox(height: 24),
                Text(
                  'Distillation preview',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Text(
                  'Nothing has been saved yet. Confirming keeps the work you '
                  'really did and removes everything else. Your progress '
                  'report is shown right after; plan the rest of the day with '
                  'Start Day.',
                ),
                const SizedBox(height: 12),
                Text(
                  'Kept · ${distill.completed.length} done, '
                  '${distill.partial.length} partial '
                  '(${distill.partialSeconds ~/ 60} min)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (distill.blocks.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Nothing is kept yet.'),
                  ),
                for (final block in distill.blocks)
                  ListTile(
                    key: ValueKey('kept-${block.id}'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.check_circle_outline),
                    title: Text(block.title),
                    subtitle: Text(
                      '${block.recordedSeconds ~/ 60} min on timer · '
                      '${BlockStatusStyle.of(context, block.status).label}',
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  'Discarded · ${distill.discarded.length} block(s), '
                  '${distill.discardedPlannedMinutes} min planned',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final block in distill.discarded)
                  ListTile(
                    key: ValueKey('discarded-${block.id}'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.remove_circle_outline),
                    title: Text(block.title),
                    subtitle: Text(
                      '${block.plannedDurationMinutes} min planned · '
                      '${BlockStatusStyle.of(context, block.status).label}',
                    ),
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
                if (!inPreview) ...[
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
                  if (widget.distillPreview != null &&
                      widget.saveDistill != null)
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _previewDistill,
                      icon: const Icon(Icons.science_outlined),
                      label: const Text('Distill & see report'),
                    ),
                ] else if (distill != null) ...[
                  FilledButton(
                    onPressed: _saving ? null : _saveDistill,
                    child: const Text('Confirm distill & save'),
                  ),
                  OutlinedButton(
                    onPressed: _saving ? null : _cancelPreview,
                    child: const Text('Cancel preview'),
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
