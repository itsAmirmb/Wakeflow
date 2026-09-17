import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakeflow/models/block.dart';
import 'package:wakeflow/models/category.dart';
import 'package:wakeflow/models/checkpoint_report.dart';
import 'package:wakeflow/screens/checkpoint_screen.dart';

const category = Category(
  id: 'work',
  name: 'Work',
  icon: '',
  percentage: 1,
  minimumMinutes: 0,
  preferredBlockMinMinutes: 15,
  preferredBlockMaxMinutes: 60,
);

CheckpointReport report() => CheckpointReport(
  now: DateTime(2026, 9, 17, 12),
  dayEnd: DateTime(2026, 9, 17, 18),
  categories: const [
    CategoryProgress(
      category: category,
      targetSeconds: 120 * 60,
      expectedSeconds: 50 * 60,
      actualSeconds: 17 * 60,
    ),
  ],
);

const history = Block(
  id: 'history',
  categoryId: 'work',
  title: 'Completed history',
  plannedDurationMinutes: 20,
  status: BlockStatus.completed,
  accumulatedSeconds: 17 * 60,
);
const future = Block(
  id: 'future',
  categoryId: 'work',
  title: 'Proposed work',
  plannedDurationMinutes: 35,
);

typedef SaveCheckpoint = Future<void> Function(
  Map<String, CheckpointAssessment>,
  String,
  List<Block>?,
);

Future<void> openScreen(
  WidgetTester tester, {
  required List<Block> Function() preview,
  required SaveCheckpoint save,
  ValueChanged<bool?>? onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: TextButton(
              onPressed: () async {
                final result = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CheckpointScreen(
                      report: report(),
                      previewFuture: preview,
                      save: save,
                    ),
                  ),
                );
                onResult?.call(result);
              },
              child: const Text('Open checkpoint'),
            ),
          );
        },
      ),
    ),
  );
  await tester.tap(find.text('Open checkpoint'));
  await tester.pumpAndSettle();
}

Future<void> assess(WidgetTester tester, String label) async {
  final field = find.byKey(const ValueKey('assessment-work'));
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

VoidCallback buttonCallback(WidgetTester tester, String label) => tester
    .widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    )
    .onPressed!;

void main() {
  testWidgets(
    'requires assessment; plain save preserves routine and actual time',
    (tester) async {
      var previews = 0;
      var saves = 0;
      bool? result;
      Map<String, CheckpointAssessment>? answers;
      String? note;
      List<Block>? proposal;
      await openScreen(
        tester,
        preview: () {
          previews++;
          return [history, future];
        },
        save: (a, n, p) async {
          saves++;
          answers = a;
          note = n;
          proposal = p;
        },
        onResult: (value) => result = value,
      );
      expect(find.text('Target total: 120 min'), findsOneWidget);
      expect(find.text('Scheduled till now: 50 min'), findsOneWidget);
      expect(find.text('Actual recorded: 17 min'), findsOneWidget);
      expect(previews, 0);
      await tester.tap(find.text('Save & continue'));
      await tester.pumpAndSettle();
      expect(saves, 0);
      await assess(tester, 'Reached');
      expect(find.text('Actual recorded: 17 min'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('checkpoint-note')),
        'Good focus',
      );
      await tester.tap(find.text('Save & continue'));
      await tester.pumpAndSettle();
      expect(saves, 1);
      expect(answers, {'work': CheckpointAssessment.reached});
      expect(note, 'Good focus');
      expect(proposal, isNull);
      expect(previews, 0);
      expect(history.accumulatedSeconds, 17 * 60);
      expect(result, isTrue);
    },
  );

  testWidgets(
    'preview and both cancel paths do not write; confirm saves all blocks',
    (tester) async {
      var previews = 0;
      var saves = 0;
      List<Block>? saved;
      await openScreen(
        tester,
        preview: () {
          previews++;
          return [history, future];
        },
        save: (_, _, p) async {
          saves++;
          saved = p;
        },
      );
      await assess(tester, 'Partially reached');
      await tester.tap(find.text('Preview new plan'));
      await tester.pumpAndSettle();
      expect(previews, 1);
      expect(saves, 0);
      // The preview is below the reflection form in a lazily built ListView;
      // ensureVisible cannot locate an item until scrolling has built it.
      await tester.scrollUntilVisible(
        find.text('Proposed work'),
        200,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ).first,
      );
      expect(find.text('35 min'), findsOneWidget);
      expect(find.text('Completed history'), findsNothing);
      await tester.tap(find.text('Cancel preview'));
      await tester.pumpAndSettle();
      expect(saves, 0);
      await tester.tap(find.text('Preview new plan'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Save & continue'), findsOneWidget);
      expect(saves, 0);
      await tester.tap(find.text('Preview new plan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm & save'));
      await tester.pumpAndSettle();
      expect(previews, 3);
      expect(saves, 1);
      expect(saved, [history, future]);
      expect(identical(saved!.first, history), isTrue);
    },
  );

  testWidgets('pending save blocks duplicate actions and back navigation', (
    tester,
  ) async {
    final gate = Completer<void>();
    var saves = 0;
    bool? result;
    await openScreen(
      tester,
      preview: () => [future],
      save: (_, _, _) {
        saves++;
        return gate.future;
      },
      onResult: (value) => result = value,
    );
    await assess(tester, 'Not reached');
    final save = buttonCallback(tester, 'Save & continue');
    save();
    save();
    await tester.pump();
    expect(saves, 1);
    expect(
      tester.widget<PopScope<bool>>(find.byType(PopScope<bool>)).canPop,
      isFalse,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save & continue'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Preview new plan'),
          )
          .onPressed,
      isNull,
    );
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(CheckpointScreen), findsOneWidget);
    expect(result, isNull);
    gate.complete();
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(find.byType(CheckpointScreen), findsNothing);
    save();
    expect(saves, 1);
  });

  testWidgets(
    'failed confirmation retains answers, note, proposal and permits retry',
    (tester) async {
      var saves = 0;
      var previews = 0;
      await openScreen(
        tester,
        preview: () {
          previews++;
          return [history, future];
        },
        save: (a, n, p) async {
          saves++;
          expect(a, {'work': CheckpointAssessment.partial});
          expect(n, 'Try a shorter block');
          expect(p, [history, future]);
          if (saves == 1) throw StateError('storage unavailable');
        },
      );
      await assess(tester, 'Partially reached');
      await tester.enterText(
        find.byKey(const ValueKey('checkpoint-note')),
        'Try a shorter block',
      );
      await tester.tap(find.text('Preview new plan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm & save'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Could not save the checkpoint. Your answers are kept. Try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Confirm & save'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('checkpoint-note')),
            )
            .controller!
            .text,
        'Try a shorter block',
      );
      await tester.tap(find.text('Confirm & save'));
      await tester.pumpAndSettle();
      expect(saves, 2);
      expect(previews, 1);
      expect(find.byType(CheckpointScreen), findsNothing);
    },
  );

  testWidgets(
    'preview failure keeps reflection editable and performs no save',
    (tester) async {
      var saves = 0;
      await openScreen(
        tester,
        preview: () => throw StateError('no plan'),
        save: (_, _, _) async {
          saves++;
        },
      );
      await assess(tester, 'Reached');
      await tester.tap(find.text('Preview new plan'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not preview the new plan. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('Save & continue'), findsOneWidget);
      expect(saves, 0);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(CheckpointScreen), findsNothing);
      expect(saves, 0);
    },
  );
}
