import 'dart:async';
import 'package:flutter/material.dart';
import 'package:gitjournal/repository.dart';
import 'package:gitjournal/services/widget_service.dart';
import 'package:provider/provider.dart';

class WidgetUpdater extends StatefulWidget {
  final Widget child;

  const WidgetUpdater({Key? key, required this.child}) : super(key: key);

  @override
  _WidgetUpdaterState createState() => _WidgetUpdaterState();
}

class _WidgetUpdaterState extends State<WidgetUpdater> {
  Timer? _debounce;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Verify we have a repo
    try {
      final repo = Provider.of<GitJournalRepo>(context);
      _scheduleUpdate(repo);
    } catch (_) {
      // Repo might not be ready
    }
  }

  void _scheduleUpdate(GitJournalRepo repo) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        _updateWidget(repo);
      }
    });
  }

  Future<void> _updateWidget(GitJournalRepo repo) async {
    try {
      print("WidgetUpdater: Updating widget...");
      final allNotes = repo.rootFolder.getAllNotes().toList();
      print("WidgetUpdater: Found ${allNotes.length} notes");
      await WidgetService.updateWidgetData(allNotes);
    } catch (e) {
      debugPrint("Widget Update Failed: $e");
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
