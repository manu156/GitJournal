import 'package:diff_match_patch/diff_match_patch.dart';

enum DiffType { added, removed, neutral }

class DiffLine {
  final String content;
  final DiffType type;

  DiffLine(this.content, this.type);
}

class LineDiffHelper {
  static List<DiffLine> calculateDiff(String oldText, String newText) {
    final dmp = DiffMatchPatch();
    final diffs = dmp.diff(oldText, newText, true);
    dmp.diffCleanupSemantic(diffs);

    final List<DiffLine> lines = [];

    for (var diff in diffs) {
      final diffLines = diff.text.split('\n');
      // If the text ends with a newline, split() creates an empty string at the end.
      // We usually want to ignore it unless it's the only character.
      if (diffLines.isNotEmpty && diffLines.last.isEmpty) {
        diffLines.removeLast();
      }

      for (var line in diffLines) {
        switch (diff.operation) {
          case DIFF_INSERT:
            lines.add(DiffLine(line, DiffType.added));
            break;
          case DIFF_DELETE:
            lines.add(DiffLine(line, DiffType.removed));
            break;
          case DIFF_EQUAL:
            lines.add(DiffLine(line, DiffType.neutral));
            break;
        }
      }
    }

    return lines;
  }
}
