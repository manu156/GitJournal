/*
 * SPDX-FileCopyrightText: 2019-2021 Vishesh Handa <me@vhanda.in>
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import 'package:dart_git/dart_git.dart';
import 'package:dart_git/plumbing/commit_iterator.dart';
import 'package:dart_git/plumbing/git_hash.dart';
import 'package:dart_git/plumbing/reference.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gitjournal/folder_views/folder_view.dart';
import 'package:gitjournal/repository.dart';
import 'package:gitjournal/sync_attempt.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'git_commit_diff_sheet.dart';

/// Shows a bottom sheet with sync controls + commit history.
void showGitSyncBottomSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => const _GitSyncSheet(),
  );
}

// Runs in an Isolate via compute()
List<_CommitData> _loadCommitHistory(String repoPath) {
  try {
    final repo = GitRepository.load(repoPath);
    final headHash = repo.headHash();

    // Try to find the remote tracking branch hash
    GitHash? remoteHash;
    try {
      final branchName = repo.currentBranch();
      final brConfig = repo.config.branch(branchName);
      if (brConfig != null && brConfig.remote != null && brConfig.merge != null) {
        final remoteRefName = ReferenceName.remote(
          brConfig.remote!,
          brConfig.merge!.branchName()!,
        );
        remoteHash = repo.resolveReferenceName(remoteRefName)?.hash;
      }
    } catch (_) {
      // No remote or detached head
    }

    bool syncedReached = false;
    // If there's no remote, nothing is "synced" in the git sense
    if (remoteHash == null) syncedReached = false;

    final commits = commitIteratorBFS(
      objStorage: repo.objStorage,
      from: headHash,
    )
        .take(50)
        .map((c) {
          // If this commit IS the remote hash, then this and all older are synced
          if (remoteHash != null && c.hash == remoteHash) {
            syncedReached = true;
          }

          return _CommitData(
            fullHash: c.hash.toString(),
            shortHash: c.hash.toString().substring(0, 7),
            message: c.message.trim().split('\n').first,
            author: c.author.name,
            date: c.author.date,
            isSynced: syncedReached,
          );
        })
        .toList();

    repo.close();
    return commits;
  } catch (e) {
    return [];
  }
}

class _CommitData {
  final String fullHash;
  final String shortHash;
  final String message;
  final String author;
  final DateTime date;
  final bool isSynced;

  const _CommitData({
    required this.fullHash,
    required this.shortHash,
    required this.message,
    required this.author,
    required this.date,
    required this.isSynced,
  });
}

class _GitSyncSheet extends StatefulWidget {
  const _GitSyncSheet();

  @override
  State<_GitSyncSheet> createState() => _GitSyncSheetState();
}

class _GitSyncSheetState extends State<_GitSyncSheet> {
  List<_CommitData>? _commits;
  bool _loadingCommits = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final repo = context.read<GitJournalRepo>();
    final commits = await compute(_loadCommitHistory, repo.repoPath);
    if (mounted) {
      setState(() {
        _commits = commits;
        _loadingCommits = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final repo = context.watch<GitJournalRepo>();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollController) {
        return Column(
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Title row
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 16, 0),
              child: Row(
                children: [
                  Icon(Icons.cloud_outlined,
                      color: colorScheme.primary, size: 22),
                  const SizedBox(width: 12),
                  Text(
                    'Git Sync',
                    style: theme.textTheme.titleLarge!.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    color: colorScheme.onSurfaceVariant,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Sync action card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _SyncActionCard(repo: repo),
            ),

            const SizedBox(height: 20),

            // History section header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Icon(Icons.history,
                      size: 18, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(
                    'Commit History',
                    style: theme.textTheme.labelLarge!.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Commit list
            Expanded(
              child: _loadingCommits
                  ? const Center(child: CircularProgressIndicator())
                  : _commits == null || _commits!.isEmpty
                      ? Center(
                          child: Text(
                            'No commits found',
                            style: TextStyle(
                                color: colorScheme.onSurfaceVariant),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          padding:
                              const EdgeInsets.fromLTRB(16, 0, 16, 32),
                          itemCount: _commits!.length,
                          itemBuilder: (ctx, i) =>
                              _CommitTile(data: _commits![i], isLast: i == _commits!.length - 1),
                        ),
            ),
          ],
        );
      },
    );
  }
}

class _SyncActionCard extends StatelessWidget {
  final GitJournalRepo repo;
  const _SyncActionCard({required this.repo});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final status = repo.syncStatus;
    final isSyncing = status == SyncStatus.Pulling ||
        status == SyncStatus.Pushing ||
        status == SyncStatus.Merging;

    late final String label;
    late final IconData icon;
    late final Color color;

    switch (status) {
      case SyncStatus.Pulling:
        label = 'Pulling changes…';
        icon = Icons.cloud_download_outlined;
        color = cs.primary;
        break;
      case SyncStatus.Pushing:
        label = 'Pushing changes…';
        icon = Icons.cloud_upload_outlined;
        color = cs.primary;
        break;
      case SyncStatus.Merging:
        label = 'Merging…';
        icon = Icons.merge_outlined;
        color = cs.primary;
        break;
      case SyncStatus.Error:
        label = 'Sync failed — tap to retry';
        icon = Icons.cloud_off_outlined;
        color = cs.error;
        break;
      case SyncStatus.Done:
        if (repo.numChanges > 0) {
          label =
              '${repo.numChanges} local change${repo.numChanges == 1 ? '' : 's'} — tap to push';
          icon = Icons.cloud_upload_outlined;
          color = cs.primary;
        } else {
          label = 'Everything is synced';
          icon = Icons.cloud_done_outlined;
          color = cs.tertiary;
        }
        break;
      default:
        label = 'Tap to sync with remote';
        icon = Icons.sync_outlined;
        color = cs.primary;
    }

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: isSyncing ? null : () => syncRepo(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              isSyncing
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: cs.primary),
                    )
                  : Icon(icon, color: color, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium!
                      .copyWith(color: cs.onSurface),
                ),
              ),
              if (!isSyncing)
                Icon(Icons.chevron_right,
                    color: cs.onSurfaceVariant, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommitTile extends StatelessWidget {
  final _CommitData data;
  final bool isLast;

  const _CommitTile({required this.data, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return InkWell(
      onTap: () => showGitCommitDiff(context, data.fullHash),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 16),
          // Timeline track
          SizedBox(
            width: 28,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: data.isSynced ? cs.tertiary : cs.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: cs.surfaceContainerLow,
                      width: 2,
                    ),
                  ),
                ),
                if (!isLast)
                  Container(
                    width: 2,
                    height: 52,
                    color: cs.outlineVariant,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Commit content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          data.message,
                          style: theme.textTheme.bodyMedium!.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        data.isSynced
                            ? Icons.cloud_done_outlined
                            : Icons.phone_android_outlined,
                        size: 16,
                        color: data.isSynced
                            ? cs.tertiary
                            : cs.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: data.isSynced
                              ? cs.tertiaryContainer
                              : cs.primaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          data.shortHash,
                          style: theme.textTheme.labelSmall!.copyWith(
                            fontFamily: 'Roboto Mono',
                            color: data.isSynced
                                ? cs.onTertiaryContainer
                                : cs.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${data.author} · ${timeago.format(data.date)}',
                          style: theme.textTheme.labelSmall!
                              .copyWith(color: cs.onSurfaceVariant),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
