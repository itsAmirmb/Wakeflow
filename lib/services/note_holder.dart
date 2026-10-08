import '../models/block.dart';

/// Notes are shown on one block per category at a time, not on all of them.
///
/// The holder is the category's first block that is still to be done
/// (pending, running or paused), so the notes start on the first block and
/// move to the next one as soon as the current one is finished. When every
/// block of the category is finished, the notes stay on its last block so
/// they remain reachable.
///
/// Returns category id -> id of the block that holds its notes.
Map<String, String> noteHolderBlocks(List<Block> blocks) {
  bool unfinished(Block b) =>
      b.status == BlockStatus.pending ||
      b.status == BlockStatus.active ||
      b.status == BlockStatus.paused;

  final holders = <String, String>{};
  for (final block in blocks) {
    if (unfinished(block)) holders.putIfAbsent(block.categoryId, () => block.id);
  }
  final last = <String, String>{};
  for (final block in blocks) {
    last[block.categoryId] = block.id;
  }
  for (final entry in last.entries) {
    holders.putIfAbsent(entry.key, () => entry.value);
  }
  return holders;
}
