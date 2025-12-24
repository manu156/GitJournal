import 'dart:convert';
import 'package:gitjournal/core/note.dart';
import 'package:home_widget/home_widget.dart';

class WidgetService {
  static const String androidWidgetName = 'GitJournalWidgetProvider';

  static Future<void> updateWidgetData(List<Note> allNotes) async {
    // Sort by modified desc
    final sortedNotes = List<Note>.from(allNotes);
    sortedNotes.sort((a, b) => b.modified.compareTo(a.modified));

    // Take top 20
    final topNotes = sortedNotes.take(20).toList();

    final notesData = topNotes.map((note) {
      // Truncate body for preview
      var bodyPreview = note.body.trim();
      if (bodyPreview.length > 100) {
        bodyPreview = bodyPreview.substring(0, 100) + '...';
      }
      
      return {
        'title': note.title ?? 'Untitled',
        'body': bodyPreview,
        'date': note.modified.toIso8601String(),
        'path': note.filePath,
      };
    }).toList();

    final jsonString = jsonEncode(notesData);
    print("WidgetService: Saving $jsonString");

    await HomeWidget.saveWidgetData<String>('notes_data', jsonString);
    await HomeWidget.updateWidget(
      qualifiedAndroidName: 'io.gitjournal.gitjournal.GitJournalWidgetProvider',
    );
  }
}
