import 'package:flutter/material.dart';
import 'package:gitjournal/utils/diff_helper.dart';

class CollapsibleDiffView extends StatefulWidget {
  final List<DiffLine> lines;
  final int contextLines;

  const CollapsibleDiffView({
    Key? key,
    required this.lines,
    this.contextLines = 5,
  }) : super(key: key);

  @override
  State<CollapsibleDiffView> createState() => _CollapsibleDiffViewState();
}

class _DiffChunk {
  final List<DiffLine> lines;
  final bool isChange;
  bool isExpanded;

  _DiffChunk(this.lines, this.isChange, {this.isExpanded = false});
}

class _CollapsibleDiffViewState extends State<CollapsibleDiffView> {
  late List<_DiffChunk> _chunks;

  @override
  void initState() {
    super.initState();
    _buildChunks();
  }

  @override
  void didUpdateWidget(CollapsibleDiffView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lines != widget.lines) {
      _buildChunks();
    }
  }

  void _buildChunks() {
    _chunks = [];
    if (widget.lines.isEmpty) return;

    // Identify which lines are part of a change or within contextLines of a change
    final isVisible = List<bool>.filled(widget.lines.length, false);

    for (int i = 0; i < widget.lines.length; i++) {
      if (widget.lines[i].type != DiffType.neutral) {
        // Mark this line and nearby lines as visible
        final start = (i - widget.contextLines).clamp(0, widget.lines.length);
        final end = (i + widget.contextLines).clamp(0, widget.lines.length - 1);
        for (int j = start; j <= end; j++) {
          isVisible[j] = true;
        }
      }
    }

    // If there are no changes at all, just show everything
    if (!isVisible.contains(true)) {
      _chunks.add(_DiffChunk(widget.lines, true, isExpanded: true));
      return;
    }

    // Group into chunks
    List<DiffLine> currentChunkLines = [];
    bool currentIsVisible = isVisible[0];

    for (int i = 0; i < widget.lines.length; i++) {
      if (isVisible[i] == currentIsVisible) {
        currentChunkLines.add(widget.lines[i]);
      } else {
        _chunks.add(_DiffChunk(currentChunkLines, currentIsVisible,
            isExpanded: currentIsVisible));
        currentChunkLines = [widget.lines[i]];
        currentIsVisible = isVisible[i];
      }
    }
    if (currentChunkLines.isNotEmpty) {
      _chunks.add(_DiffChunk(currentChunkLines, currentIsVisible,
          isExpanded: currentIsVisible));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_chunks.isEmpty) return const SizedBox();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _chunks.map((chunk) {
            if (chunk.isExpanded) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: chunk.lines.map((l) => _buildDiffLine(l, theme)).toList(),
              );
            } else {
              return InkWell(
                onTap: () {
                  setState(() {
                    int toExpand = chunk.lines.length < 20 ? chunk.lines.length : 20;
                    if (toExpand == chunk.lines.length) {
                      chunk.isExpanded = true;
                    } else {
                      int index = _chunks.indexOf(chunk);
                      final expandedLines = chunk.lines.take(toExpand).toList();
                      final remainingLines = chunk.lines.skip(toExpand).toList();
                      
                      _chunks.replaceRange(index, index + 1, [
                        _DiffChunk(expandedLines, chunk.isChange, isExpanded: true),
                        _DiffChunk(remainingLines, chunk.isChange, isExpanded: false),
                      ]);
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    border: Border(
                      bottom: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.3),
                      ),
                      top: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.unfold_more,
                        size: 16,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Expand ${chunk.lines.length < 20 ? chunk.lines.length : 20} lines (${chunk.lines.length} hidden)',
                        style: theme.textTheme.bodySmall!.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
          }).toList(),
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
