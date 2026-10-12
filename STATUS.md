# WakeFlow — Project Status

> Current-state document. `prop.md` is the original plan and vision; **this file is the truth about what exists now.**
> Give both to any AI assistant. Where they disagree, this file wins.
> Last updated at: **v0.14.13** (branch `ling-3.0`; v0.14.12 = commit `964ad7f`).

## 1. What it is
Flutter/Dart, Android-only, local-first app (renamed from "Smart Routine"). At wake time it works out the day mode, splits the remaining usable time between categories by percentage, and generates blocks that are run with a timer. Unexpected events are handled by recalculating **only the future**; completed history is never rewritten.

Core principles (unchanged from `prop.md`): Never Zero Day · Past immutable / Current preserved / Future recalculated · Decision reduction · Simplicity first.

## 2. Tech stack
- Flutter, Dart SDK `^3.13.3`, Android only.
- Dependencies (keep it this small): `sqflite`, `path`, `flutter_local_notifications`, `timezone`. Dev: `sqflite_common_ffi`, `flutter_lints`.
- No state-management package. Screens use `setState`; `ValueNotifier` only for theme (`ThemeController`).
- Storage: SQLite via `sqflite`, **schema version 21** (`DatabaseService.schemaVersion`). `createSchema` and `upgradeSchema` must produce identical schemas.
- Native Android: `MainActivity.kt` exposes the `org.amirmb.wakeflow/alarm` method channel (alarm-stream audio). Sounds live in `res/raw`.

## 3. Implemented (vs. `prop.md` roadmap)
| Roadmap phase | State |
|---|---|
| 0–2 Environment, UI, Wake Check | Done |
| 3 Day Modes | Done (see known issue #1) |
| 4 Categories | Done + add/remove/reorder/enable, daily max time |
| 5 Routine Engine | Done (see §4) |
| 6–7 Timeline, Pause/Resume | Done, timer derived from stored data, survives app restart |
| 8 Checkpoints | Done, mandatory review gate + distillation |
| 9 Local storage | Done, SQLite (not SharedPreferences) |
| 10 Notifications | Done, wake reminder, block start/end, checkpoint, break-end alarm |
| 11 Statistics | Done, daily/weekly + daily history |
| 12 Polish | Partly: dark theme, empty states done; accessibility not reviewed |
| 13 Desktop | **Not started** |
| 14 Sync | **Not started** (intentionally) |

### Built beyond `prop.md`
- **Distillation** at a checkpoint: unfinished blocks above a keep-threshold become `partial`, the rest are discarded and re-planned; progress report screen.
- **Fixed commitments**: weekly or single-date events the planner schedules around; weekly schedule view.
- **Breaks**: short break between blocks, long break after a category finishes.
- **Credits & rewards**: 10% of timer time becomes credit; spend on "Movie time" (`kRewards`, one entry).
- **Category notes**: checkable notes per category, tick persistence across days (configurable), user-defined order (drag handle, new notes go last), add/reorder from the in-block sheet.
- **Day timeline screen** (v0.14.12) and **category timeline bar** (percentages edited as a normalized bar).
- **Import/Export backup** (JSON).
- **Logical day**: a day resets at a configurable time (default 04:00), and an unfinished routine carries over.
- **Routine target** on the Wake screen: by target end time or by duration.
- Configurable per-event alert styles and sounds.

## 4. Architecture map (`lib/`)
- `models/`: plain data + `toMap/fromMap`. `Block` (status incl. extra `partial`), `Category`, `AppSettings`, `Commitment`, `CheckpointReport`, `ProgressReport`, `Reward`, `TimelineEntry`, `DayMode`.
- `services/routine_engine.dart` (630 lines), **the core.** Pure static functions, no I/O:
  `calculateUsableMinutes`, `allocateTime` (weighted water-filling + largest-remainder rounding; min/max per category; emergency compression), `splitIntoBlocks`, `placeOnTimeline` / `generateRoutine` (around commitments + buffers), `distill`, `recalculateFromCheckpoint`.
- `services/database_service.dart` (901 lines): all persistence, migrations, settings row.
- Pure helpers (easy to test): `day_mode_calculator`, `day_timeline`, `checkpoint_gate`, `break_state`, `credit_service`, `active_day`, `day_key`.
- `notification_service.dart`, `alarm_sound.dart`, `backup_service.dart`, `stats_service.dart`, `history_service.dart`.
- `screens/` + `widgets/`: UI. Largest: `today_screen` (1345), `settings_screen` (1069), `day_timeline_screen` (558), `home_screen` (547).

Design rules already followed: state that can be derived is **derived, not stored** (break state, checkpoint due, elapsed time); engine takes inputs and returns blocks; DB is the only persistence layer.

## 5. Known issues / debt
1. **Target wake time is hardcoded** (`DayModeCalculator.targetWakeHour = 8`, used in `wake_screen.dart`). The code comment says it will move to Settings. Wake-reminder time is already configurable; day mode should follow it or get its own setting.
2. **Large screens, no state layer.** `today_screen`, `settings_screen`, `database_service` are big and ~100 `setState` calls exist. Fine for now; must be split before Desktop (Phase 13). Prefer a plain `ChangeNotifier` over adding a package.
3. **Tests:** the project zip shared for review had no `test/` folder (`sqflite_common_ffi` is in dev_dependencies, the v0.5.1 commit mentions engine tests). Confirm engine tests exist and pass; the 10 test cases in `prop.md` §27 should map to real tests.
4. Android: both `SCHEDULE_EXACT_ALARM` and `USE_EXACT_ALARM` are declared. `USE_EXACT_ALARM` is restricted by Play policy; fine for personal use, review before any store release.
5. Housekeeping: `pubspec.yaml` description is still the Flutter template text; make sure `android/.gradle/` and `android/local.properties` are git-ignored.
6. Scope has grown well past the MVP in `prop.md`; each new feature adds maintenance cost.

## 6. Suggested next steps (in order)
1. Make the target wake time a Setting; feed it to `DayModeCalculator`.
2. Verify/restore engine tests; add cases for distill, commitments, credits.
3. Extract Today-screen logic into a small `ChangeNotifier` and shrink `today_screen`.
4. Only then: new features, then Desktop.

## 7. Working rules (for AI assistants)
- Minimal, targeted changes. No rewrites, no over-engineering, no new dependency without a stated reason.
- Explain the plan and list the files to change **before** editing; one feature at a time.
- Do not touch completed history; only recalculate the future.
- Any schema change: bump `schemaVersion`, update both `createSchema` and `upgradeSchema`, keep old installs working.
- After each change: give manual test steps, the git commit message in the `vX.Y.Z (short description)` style, and a tag when appropriate.
- Not building now: AI planner, cloud/login/sync, social features.

## 8. Git
Branches: `main`, `dev`, `storage`, `Union-Alpha` (experimental intro animation, v0.12.13-14, not merged), **`ling-3.0` = current (HEAD, v0.14.12)**.
Commit style: `vMAJOR.MINOR.PATCH (what changed)`.
