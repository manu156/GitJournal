/*
 * SPDX-FileCopyrightText: 2019-2021 Vishesh Handa <me@vhanda.in>
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import 'dart:convert';

import 'package:dart_git/dart_git.dart';
import 'package:dart_git/diff_commit.dart';
import 'package:dart_git/plumbing/git_hash.dart';
import 'package:dart_git/plumbing/objects/blob.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gitjournal/repository.dart';
import 'package:provider/provider.dart';

import 'package:gitjournal/utils/diff_helper.dart';

class FileDiff {
  final String path;
  final List<DiffLine> lines;
  final bool isNew;
  final bool isDeleted;

  FileDiff({
    required this.path,
    required this.lines,
    this.isNew = false,
    this.isDeleted = false,
  });
}

class CommitDiffData {
  final String message;
  final String hash;
  final List<FileDiff> fileDiffs;

  CommitDiffData({
    required this.message,
    required this.hash,
    required this.fileDiffs,
  });
}

// Shows a bottom sheet with the diff of a commit.
void showGitCommitDiff(BuildContext context, String commitHash) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => _GitCommitDiffSheet(commitHash: commitHash),
  );
}

class _GitCommitDiffSheet extends StatefulWidget {
  final String commitHash;
  const _GitCommitDiffSheet({required this.commitHash});

  @override
  State<_GitCommitDiffSheet> createState() => _GitCommitDiffSheetState();
}

class _GitCommitDiffSheetState extends State<_GitCommitDiffSheet> {
  CommitDiffData? _diffData;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<GitJournalRepo>();
    try {
      final data = await compute(_calculateDiff, {
        'repoPath': repo.repoPath,
        'hash': widget.commitHash,
      });
      if (mounted) {
        setState(() {
          _diffData = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) {
        return Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Commit Details',
                          style: theme.textTheme.labelLarge!.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_diffData != null)
                          Text(
                            _diffData!.message,
                            style: theme.textTheme.titleMedium!.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            const Divider(),

            // Content
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text('Error: $_error'))
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: _diffData!.fileDiffs.length,
                          itemBuilder: (ctx, i) =>
                              _FileDiffWidget(diff: _diffData!.fileDiffs[i]),
                        ),
            ),
          ],
        );
      },
    );
  }
}

class _FileDiffWidget extends StatelessWidget {
  final FileDiff diff;
  const _FileDiffWidget({required this.diff});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // File Header
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  diff.isNew
                      ? Icons.add_circle_outline
                      : diff.isDeleted
                          ? Icons.remove_circle_outline
                          : Icons.edit_note,
                  size: 18,
                  color: diff.isNew
                      ? Colors.green
                      : diff.isDeleted
                          ? Colors.red
                          : cs.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    diff.path,
                    style: theme.textTheme.bodyMedium!.copyWith(
                      fontFamily: 'Roboto Mono',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Lines
          if (diff.lines.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: diff.lines.map((l) => _buildLine(l, theme)).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLine(DiffLine line, ThemeData theme) {
    final cs = theme.colorScheme;
    Color? bgColor;
    Color? textColor;
    String prefix = ' ';

    if (line.type == DiffType.added) {
      bgColor = Colors.green.withValues(alpha: 0.15);
      textColor = Colors.green[700];
      prefix = '+';
    } else if (line.type == DiffType.removed) {
      bgColor = Colors.red.withValues(alpha: 0.15);
      textColor = Colors.red[700];
      prefix = '-';
    }

    return Container(
      width: double.infinity,
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: Text(
        '$prefix ${line.content}',
        style: theme.textTheme.bodySmall!.copyWith(
          fontFamily: 'Roboto Mono',
          color: textColor ?? cs.onSurface,
          fontSize: 12,
        ),
      ),
    );
  }
}

// BACKGROUND TASK
CommitDiffData _calculateDiff(Map<String, dynamic> params) {
  final repoPath = params['repoPath'] as String;
  final hashStr = params['hash'] as String;

  final repo = GitRepository.load(repoPath);
  final toCommit = repo.objStorage.readCommit(GitHash(hashStr));
  final parentHash = toCommit.parents.isNotEmpty ? toCommit.parents.first : null;

  CommitBlobChanges changes;
  if (parentHash != null) {
    final fromCommit = repo.objStorage.readCommit(parentHash);
    changes = diffCommits(
      fromCommit: fromCommit,
      toCommit: toCommit,
      objStore: repo.objStorage,
    );
  } else {
    // Initial commit - everything is an addition
    final tree = repo.objStorage.readTree(toCommit.treeHash);
    final add = <Change>[];
    for (var entry in tree.entries) {
      add.add(Change(from: null, to: ChangeEntry(entry.name, tree, entry)));
    }
    changes = CommitBlobChanges(add: add, remove: [], modify: []);
  }

  final fileDiffs = <FileDiff>[];

  for (var change in changes.merged()) {
    final lines = <DiffLine>[];
    String? oldContent;
    String? newContent;

    if (change.from != null) {
      final obj = repo.objStorage.read(change.from!.hash);
      if (obj is GitBlob) {
        try {
          oldContent = utf8.decode(obj.blobData);
        } catch (_) {}
      }
    }
    if (change.to != null) {
      final obj = repo.objStorage.read(change.to!.hash);
      if (obj is GitBlob) {
        try {
          newContent = utf8.decode(obj.blobData);
        } catch (_) {}
      }
    }

    // Simple Line Diff using diff_match_patch
    if (oldContent != null || newContent != null) {
      if (change.add) {
        final newLines = newContent?.split('\n') ?? [];
        for (var l in newLines) {
          if (l.isNotEmpty) lines.add(DiffLine(l, DiffType.added));
        }
      } else if (change.delete) {
        final oldLines = oldContent?.split('\n') ?? [];
        for (var l in oldLines) {
          if (l.isNotEmpty) lines.add(DiffLine(l, DiffType.removed));
        }
      } else {
        lines.addAll(LineDiffHelper.calculateDiff(oldContent ?? '', newContent ?? ''));
      }
    }

    fileDiffs.add(FileDiff(
      path: change.path,
      lines: lines,
      isNew: change.add,
      isDeleted: change.delete,
    ));
  }

  repo.close();
  return CommitDiffData(
    message: toCommit.message,
    hash: hashStr,
    fileDiffs: fileDiffs,
  );
}
