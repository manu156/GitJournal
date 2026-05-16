/*
 * SPDX-FileCopyrightText: 2019-2021 Vishesh Handa <me@vhanda.in>
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import 'package:flutter/material.dart';
import 'package:gitjournal/analytics/analytics.dart';
import 'package:gitjournal/app_router.dart';
import 'package:gitjournal/core/folder/filtered_notes_folder.dart';
import 'package:gitjournal/core/folder/notes_folder.dart';
import 'package:gitjournal/core/folder/notes_folder_fs.dart';
import 'package:gitjournal/core/folder/sorted_notes_folder.dart';
import 'package:gitjournal/core/folder/sorting_mode.dart';
import 'package:gitjournal/core/markdown/md_yaml_doc_codec.dart';
import 'package:gitjournal/core/note.dart';
import 'package:gitjournal/editors/common_types.dart';
import 'package:gitjournal/editors/note_editor.dart';
import 'package:gitjournal/folder_views/common.dart';
import 'package:gitjournal/folder_views/folder_view_configuration_dialog.dart';
import 'package:gitjournal/folder_views/standard_view.dart';
import 'package:gitjournal/l10n.dart';
import 'package:gitjournal/repository.dart';
import 'package:gitjournal/settings/settings.dart';
import 'package:gitjournal/utils/utils.dart';
import 'package:gitjournal/widgets/app_bar_menu_button.dart';
import 'package:gitjournal/widgets/app_drawer.dart';
import 'package:gitjournal/widgets/folder_selection_dialog.dart';
import 'package:gitjournal/widgets/note_delete_dialog.dart';
import 'package:gitjournal/widgets/note_search_delegate.dart';
import 'package:gitjournal/widgets/sorting_mode_selection_dialog.dart';
import 'package:gitjournal/widgets/sync_button.dart';
import 'package:gitjournal/sync_attempt.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../widgets/git_conflict_resolution_sheet.dart';

enum DropDownChoices {
  SortingOptions,
}

enum NoteSelectedExtraActions {
  MoveToFolder,
}

class FolderView extends StatefulWidget {
  final NotesFolder notesFolder;
  final Map<String, dynamic> newNoteExtraProps;

  const FolderView({
    required this.notesFolder,
    this.newNoteExtraProps = const {},
  });

  @override
  _FolderViewState createState() => _FolderViewState();
}

class _FolderViewState extends State<FolderView> {
  SortedNotesFolder? _sortedNotesFolder;
  SortedNotesFolder? _pinnedNotesFolder;
  FolderViewType _viewType = FolderViewType.Card;

  var _headerType = StandardViewHeader.TitleGenerated;
  bool _showSummary = true;

  var _selectedNotes = <Note>[];
  bool get inSelectionMode => _selectedNotes.isNotEmpty;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    _viewType = FolderViewType.Card;
    _showSummary = widget.notesFolder.config.showNoteSummary;
    _headerType = widget.notesFolder.config.viewHeader;

    var otherNotesFolder = SortedNotesFolder(
      folder: await FilteredNotesFolder.load(
        widget.notesFolder,
        title: context.loc.widgetsFolderViewPinned,
        filter: (Note note) async => !note.pinned,
      ),
      sortingMode: widget.notesFolder.config.sortingMode,
    );

    var pinnedFolder = SortedNotesFolder(
      folder: await FilteredNotesFolder.load(
        widget.notesFolder,
        title: context.loc.widgetsFolderViewPinned,
        filter: (Note note) async => note.pinned,
      ),
      sortingMode: widget.notesFolder.config.sortingMode,
    );

    setState(() {
      _sortedNotesFolder = otherNotesFolder;
      _pinnedNotesFolder = pinnedFolder;
    });
  }

  @override
  void dispose() {
    _sortedNotesFolder?.dispose();
    _pinnedNotesFolder?.dispose();

    super.dispose();
  }

  @override
  void didUpdateWidget(FolderView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.notesFolder != widget.notesFolder) {
      _init();
    }
  }

  Widget _buildBody(BuildContext context) {
    if (_sortedNotesFolder == null) {
      return Container();
    }
    var title = widget.notesFolder.publicName(context);
    if (inSelectionMode) {
      title = NumberFormat.compact().format(_selectedNotes.length);
    }

    var folderView = buildFolderView(
      viewType: _viewType,
      folder: _sortedNotesFolder!,
      emptyText: context.loc.screensFolderViewEmpty,
      header: _headerType,
      showSummary: _showSummary,
      noteTapped: _noteTapped,
      noteLongPressed: _noteLongPress,
      isNoteSelected: (n) => _selectedNotes.contains(n),
    );

    Widget pinnedFolderView = const SizedBox();
    if (_pinnedNotesFolder != null) {
      pinnedFolderView = buildFolderView(
        viewType: _viewType,
        folder: _pinnedNotesFolder!,
        emptyText: null,
        header: _headerType,
        showSummary: _showSummary,
        noteTapped: _noteTapped,
        noteLongPressed: _noteLongPress,
        isNoteSelected: (n) => _selectedNotes.contains(n),
      );
    }

    var settings = context.watch<Settings>();
    final showButtomMenuBar = false;

    // So the FAB doesn't hide parts of the last entry
    folderView = SliverPadding(
      sliver: folderView,
      padding: const EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 80.0),
    );

    var backButton = IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: _resetSelection,
    );

    var havePinnedNotes =
        _pinnedNotesFolder != null ? !_pinnedNotesFolder!.isEmpty : false;

    var view = CustomScrollView(
      slivers: [
        SliverAppBar(
          floating: false,
          snap: false,
          pinned: true,
          backgroundColor: Theme.of(context).colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          toolbarHeight: 64,
          titleSpacing: 16,
          title: Container(
            height: 56,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Row(
              children: [
                const SizedBox(width: 8),
                if (inSelectionMode)
                  backButton
                else
                  GJAppBarMenuButton(),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      logEvent(Event.SearchButtonPressed);
                      showSearch(
                        context: context,
                        delegate: NoteSearchDelegate(
                          _sortedNotesFolder!.notes,
                          _viewType,
                        ),
                      );
                    },
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
                if (inSelectionMode)
                  ..._buildInSelectionNoteActions()
                else ...[
                  SyncButton(),
                  _buildExtraActions(),
                ],
                const SizedBox(width: 8),
              ],
            ),
          ),
          automaticallyImplyLeading: false,
        ),
        if (context.watch<GitJournalRepo>().syncStatus == SyncStatus.Conflict)
          _ConflictBanner(),
        if (havePinnedNotes)
          _SliverHeader(text: context.loc.widgetsFolderViewPinned),
        if (havePinnedNotes) pinnedFolderView,
        if (havePinnedNotes)
          _SliverHeader(text: context.loc.widgetsFolderViewOthers),
        folderView,
      ],
    );

    if (settings.remoteSyncFrequency == RemoteSyncFrequency.Manual) {
      return Scrollbar(child: view);
    }
    return RefreshIndicator(
      onRefresh: () => syncRepo(context),
      child: Scrollbar(child: view),
    );
  }

  void _noteLongPress(Note note) {
    var i = _selectedNotes.indexOf(note);
    if (i != -1) {
      setState(() {
        _selectedNotes.removeAt(i);
      });
    } else {
      setState(() {
        _selectedNotes.add(note);
      });
    }
  }

  void _noteTapped(Note note) {
    if (!inSelectionMode) {
      openNoteEditor(context, note, widget.notesFolder);
      return;
    }

    var i = _selectedNotes.indexOf(note);
    if (i != -1) {
      setState(() {
        _selectedNotes.removeAt(i);
      });
    } else {
      setState(() {
        _selectedNotes.add(note);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    var createButton = FloatingActionButton(
      key: const ValueKey("FAB"),
      onPressed: () =>
          _newPost(widget.notesFolder.config.defaultEditor.toEditorType()),
      child: const Icon(Icons.add),
    );

    return Scaffold(
      body: Builder(builder: _buildBody),
      extendBody: true,
      drawer: AppDrawer(),
      floatingActionButton: createButton,
    );
  }

  Future<void> _newPost(EditorType editorType) async {
    var settings = context.read<Settings>();
    var rootFolder = context.read<NotesFolderFS>();

    var folder = widget.notesFolder;
    var fsFolder = folder.fsFolder as NotesFolderFS;
    var isVirtualFolder = folder.name != folder.fsFolder!.name;

    if (isVirtualFolder) {
      fsFolder = getFolderForEditor(settings, rootFolder, editorType);
    }

    if (editorType == EditorType.Journal) {
      if (settings.journalEditordefaultNewNoteFolderSpec.isNotEmpty) {
        var spec = settings.journalEditordefaultNewNoteFolderSpec;
        fsFolder = rootFolder.getFolderWithSpec(spec) ?? rootFolder;

        if (!isVirtualFolder) {
          showSnackbar(
            context,
            context.loc.settingsEditorsJournalDefaultFolderSelect(spec),
          );
        }
      }

      if (settings.journalEditorSingleNote) {
        var note = await getTodayJournalEntry(fsFolder.rootFolder);
        if (note != null) {
          return openNoteEditor(
            context,
            note,
            fsFolder,
            editMode: true,
          );
        }
      }
    }

    var routeType =
        SettingsEditorType.fromEditorType(editorType).toInternalString();

    var extraProps = Map<String, dynamic>.from(widget.newNoteExtraProps);
    if (settings.customMetaData.isNotEmpty) {
      var map = MarkdownYAMLCodec.parseYamlText(settings.customMetaData);
      map.forEach((key, val) {
        extraProps[key] = val;
      });
    }
    var route = newNoteRoute(
      NoteEditor.newNote(
        fsFolder,
        widget.notesFolder,
        editorType,
        newNoteExtraProps: extraProps,
        existingText: "",
        existingImages: const [],
      ),
      AppRoute.NewNotePrefix + routeType,
    );
    await Navigator.push(context, route);
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
  }

  Future<void> _sortButtonPressed() async {
    if (_sortedNotesFolder == null) {
      return;
    }
    var newSortingMode = await showDialog<SortingMode>(
      context: context,
      builder: (BuildContext context) =>
          SortingModeSelectionDialog(_sortedNotesFolder!.sortingMode),
    );

    if (newSortingMode != null) {
      var folderConfig = _sortedNotesFolder!.config;
      folderConfig.sortingField = newSortingMode.field;
      folderConfig.sortingOrder = newSortingMode.order;
      folderConfig.save();

      setState(() {
        _sortedNotesFolder!.changeSortingMode(newSortingMode);
      });
    }
  }


  Widget _buildExtraActions() {
    return PopupMenuButton<DropDownChoices>(
      key: const ValueKey("PopupMenu"),
      icon: const Icon(Icons.more_vert),
      onSelected: (DropDownChoices choice) {
        switch (choice) {
          case DropDownChoices.SortingOptions:
            _sortButtonPressed();
            break;
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<DropDownChoices>>[
        PopupMenuItem<DropDownChoices>(
          key: const ValueKey("SortingOptions"),
          value: DropDownChoices.SortingOptions,
          child: Text(context.loc.widgetsFolderViewSortingOptions),
        ),
      ],
    );
  }

  List<Widget> _buildInSelectionNoteActions() {
    var extraActions = PopupMenuButton<NoteSelectedExtraActions>(
      key: const ValueKey("PopupMenu"),
      onSelected: (NoteSelectedExtraActions choice) {
        switch (choice) {
          case NoteSelectedExtraActions.MoveToFolder:
            _moveSelectedNotesToFolder();
            break;
        }
      },
      itemBuilder: (BuildContext context) =>
          <PopupMenuEntry<NoteSelectedExtraActions>>[
        PopupMenuItem<NoteSelectedExtraActions>(
          value: NoteSelectedExtraActions.MoveToFolder,
          child: Text(context.loc.widgetsFolderViewActionsMoveToFolder),
        ),
      ],
    );

    return <Widget>[
      if (_selectedNotes.length == 1)
        IconButton(
          icon: const Icon(Icons.share),
          onPressed: () async {
            await shareNote(_selectedNotes.first);
            _resetSelection();
          },
        ),
      IconButton(
        icon: const Icon(Icons.delete),
        onPressed: _deleteSelectedNotes,
      ),
      extraActions,
    ];
  }

  Future<void> _deleteSelectedNotes() async {
    var settings = context.read<Settings>();
    var shouldDelete = true;
    if (settings.confirmDelete) {
      shouldDelete = (await showDialog(
            context: context,
            builder: (context) => NoteDeleteDialog(num: _selectedNotes.length),
          )) ==
          true;
    }
    if (shouldDelete == true) {
      var repo = context.read<GitJournalRepo>();
      repo.removeNotes(_selectedNotes);
    }

    _resetSelection();
  }

  Future<void> _moveSelectedNotesToFolder() async {
    var destFolder = await showDialog<NotesFolderFS>(
      context: context,
      builder: (context) => FolderSelectionDialog(),
    );
    if (destFolder != null) {
      try {
        var repo = context.read<GitJournalRepo>();
        await repo.moveNotes(_selectedNotes, destFolder);
      } catch (ex) {
        showErrorSnackbar(context, ex);
      }
    }

    _resetSelection();
  }

  void _resetSelection() {
    setState(() {
      _selectedNotes = [];
    });
  }
}

class _SliverHeader extends StatelessWidget {
  final String text;
  const _SliverHeader({required this.text});

  @override
  Widget build(BuildContext context) {
    var textTheme = Theme.of(context).textTheme;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 4.0),
        child: Text(text, style: textTheme.titleSmall),
      ),
    );
  }
}

Future<void> syncRepo(BuildContext context) async {
  try {
    var container = context.read<GitJournalRepo>();
    await container.syncNotes();
  } catch (e) {
    showErrorSnackbar(context, e);
  }
}

class _ConflictBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: cs.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Merge Conflict Detected',
                    style: theme.textTheme.titleSmall!.copyWith(
                      color: cs.onErrorContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Some notes have conflicting changes from another device. Resolve them to continue syncing.',
              style: theme.textTheme.bodySmall!.copyWith(
                color: cs.onErrorContainer,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => showGitConflictResolution(context),
                icon: const Icon(Icons.auto_fix_high, size: 18),
                label: const Text('Resolve Conflicts'),
                style: FilledButton.styleFrom(
                  backgroundColor: cs.error,
                  foregroundColor: cs.onError,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
