/*
 * SPDX-FileCopyrightText: 2019-2021 Vishesh Handa <me@vhanda.in>
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import 'dart:convert';
import 'package:dart_git/dart_git.dart';
import 'package:dart_git/plumbing/git_hash.dart';
import 'package:dart_git/plumbing/objects/blob.dart';
import 'package:flutter/material.dart';
import 'package:gitjournal/repository.dart';
import 'package:gitjournal/utils/diff_helper.dart';
import 'package:provider/provider.dart';

void showGitConflictResolution(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => const _ConflictResolutionSheet(),
  );
}

class _ConflictResolutionSheet extends StatelessWidget {
  const _ConflictResolutionSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final repo = context.watch<GitJournalRepo>();
    final conflicts = repo.conflicts;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
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
                          'Resolve Conflicts',
                          style: theme.textTheme.headlineSmall!.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${conflicts.length} files remaining',
                          style: theme.textTheme.bodyMedium!.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
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

            const SizedBox(height: 16),

            if (conflicts.isEmpty)
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
                      SizedBox(height: 16),
                      Text('All conflicts resolved!'),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: conflicts.length,
                  itemBuilder: (ctx, i) => _ConflictItem(conflict: conflicts[i]),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ConflictItem extends StatefulWidget {
  final ConflictInfo conflict;
  const _ConflictItem({required this.conflict});

  @override
  State<_ConflictItem> createState() => _ConflictItemState();
}

class _ConflictItemState extends State<_ConflictItem> {
  String? _localContent;
  String? _remoteContent;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadContents();
  }

  Future<void> _loadContents() async {
    final repo = context.read<GitJournalRepo>();
    try {
      final git = GitRepository.load(repo.repoPath);
      
      if (widget.conflict.localHash != null) {
        final obj = git.objStorage.read(GitHash(widget.conflict.localHash!));
        if (obj is GitBlob) _localContent = utf8.decode(obj.blobData);
      }
      if (widget.conflict.remoteHash != null) {
        final obj = git.objStorage.read(GitHash(widget.conflict.remoteHash!));
        if (obj is GitBlob) _remoteContent = utf8.decode(obj.blobData);
      }
      git.close();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.description_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.conflict.path,
                    style: theme.textTheme.titleSmall!.copyWith(
                      fontFamily: 'Roboto Mono',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else ...[
              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _resolve(true),
                      icon: Icon(Icons.phone_android, size: 18, color: cs.primary),
                      label: Text('Keep Local', style: TextStyle(color: cs.primary)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _resolve(false),
                      icon: Icon(Icons.cloud_outlined, size: 18, color: cs.tertiary),
                      label: Text('Keep Cloud', style: TextStyle(color: cs.tertiary)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Diff View Legend
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 12, height: 12,
                    color: Colors.red.withValues(alpha: 0.15),
                    child: Center(child: Text('-', style: TextStyle(color: Colors.red[700], fontSize: 10))),
                  ),
                  const SizedBox(width: 4),
                  Text('Local Content', style: theme.textTheme.bodySmall),
                  const SizedBox(width: 16),
                  Container(
                    width: 12, height: 12,
                    color: Colors.green.withValues(alpha: 0.15),
                    child: Center(child: Text('+', style: TextStyle(color: Colors.green[700], fontSize: 10))),
                  ),
                  const SizedBox(width: 4),
                  Text('Cloud Content', style: theme.textTheme.bodySmall),
                ],
              ),
              const SizedBox(height: 8),

              // Diff View
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: LineDiffHelper.calculateDiff(_localContent ?? '', _remoteContent ?? '')
                      .map((l) => _buildDiffLine(l, theme))
                      .toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDiffLine(DiffLine line, ThemeData theme) {
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

  void _resolve(bool keepLocal) {
    context.read<GitJournalRepo>().resolveConflict(widget.conflict, keepLocal);
  }
}
