import 'package:diff_match_patch/diff_match_patch.dart';

void main() {
  final dmp = DiffMatchPatch();
  String text1 = "line 1\nline 2\nline 3\nline 4";
  String text2 = "line 1\nline 2 changed\nline 3\nline 4\nline 5";
  
  final a = dmp.diff_linesToChars(text1, text2);
  final lineText1 = a[0] as String;
  final lineText2 = a[1] as String;
  final lineArray = a[2] as List<String>;
  
  final diffs = dmp.diff_main(lineText1, lineText2, false);
  dmp.diff_charsToLines(diffs, lineArray);
  dmp.diff_cleanupSemantic(diffs);
  
  for (var diff in diffs) {
    print('\${diff.operation}: \${diff.text}');
  }
}
