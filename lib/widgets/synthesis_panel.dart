import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/note_node.dart';
import 'connections_painter.dart';

class SemanticCluster {
  final List<NoteNode> nodes;
  final String label;
  final String summary;

  SemanticCluster({
    required this.nodes,
    required this.label,
    required this.summary,
  });
}

class SynthesisPanel extends StatefulWidget {
  final List<NoteNode> notes;
  final List<ConnectionEdge> edges;
  final VoidCallback onClose;
  final Function(NoteNode)? onNodeTap;
  final Function(List<NoteNode>)? onClusterTap;

  const SynthesisPanel({
    super.key,
    required this.notes,
    required this.edges,
    required this.onClose,
    this.onNodeTap,
    this.onClusterTap,
  });

  @override
  State<SynthesisPanel> createState() => _SynthesisPanelState();
}

class _SynthesisPanelState extends State<SynthesisPanel> {
  List<SemanticCluster> _cachedClusters = [];
  int _lastNotesLength = 0;
  int _lastEdgesLength = 0;
  String _notesContentHash = '';

  @override
  void initState() {
    super.initState();
    _updateClusters();
  }

  @override
  void didUpdateWidget(covariant SynthesisPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_shouldRegenerate(oldWidget)) _updateClusters();
  }

  bool _shouldRegenerate(SynthesisPanel oldWidget) {
    if (widget.notes.length != _lastNotesLength ||
        widget.edges.length != _lastEdgesLength) { return true; }
    return _calculateHash(widget.notes) != _notesContentHash;
  }

  String _calculateHash(List<NoteNode> notes) {
    final buf = StringBuffer();
    for (final n in notes) {
      buf.write(n.id);
      buf.write(n.content);
    }
    return buf.toString();
  }

  void _updateClusters() {
    _cachedClusters = _generateClusters();
    _lastNotesLength = widget.notes.length;
    _lastEdgesLength = widget.edges.length;
    _notesContentHash = _calculateHash(widget.notes);
  }

  List<SemanticCluster> _generateClusters() {
    if (widget.notes.isEmpty) return [];

    final Map<String, String> parent = {
      for (var n in widget.notes) n.id: n.id
    };

    String find(String i) {
      if (parent[i] == i) return i;
      parent[i] = find(parent[i]!);
      return parent[i]!;
    }

    void union(String i, String j) {
      final ri = find(i), rj = find(j);
      if (ri != rj) parent[ri] = rj;
    }

    for (final edge in widget.edges) {
      if (parent.containsKey(edge.sourceId) &&
          parent.containsKey(edge.targetId)) {
        union(edge.sourceId, edge.targetId);
      }
    }

    final Map<String, List<NoteNode>> grouped = {};
    for (final note in widget.notes) {
      grouped.putIfAbsent(find(note.id), () => []).add(note);
    }

    final clusters = <SemanticCluster>[];
    for (final entry in grouped.entries) {
      if (entry.value.length < 2) continue;
      clusters.add(SemanticCluster(
        nodes: entry.value,
        label: _extractClusterLabel(entry.value),
        summary: _generateClusterSummary(entry.value),
      ));
    }
    return clusters;
  }

  String _extractClusterLabel(List<NoteNode> clusterNotes) {
    final Map<String, int> freq = {};
    const stopWords = {
      'and', 'the', 'this', 'that', 'for', 'with', 'about', 'from', 'into',
      'under', 'your', 'their', 'them', 'these', 'those', 'recipe',
      'cooking', 'guide', 'manual', 'management', 'learning', 'study',
      'notes', 'ideas', 'note', 'thought'
    };
    for (final note in clusterNotes) {
      final text = '${note.title} ${note.content}'.toLowerCase();
      final words =
          text.replaceAll(RegExp(r'[^\w\s\-]'), ' ').split(RegExp(r'\s+'));
      for (final w in words) {
        if (w.length > 2 && !stopWords.contains(w)) {
          freq[w] = (freq[w] ?? 0) + 1;
        }
      }
    }
    if (freq.isEmpty) return 'General Notes';
    final sorted = freq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = <String>[];
    for (int i = 0; i < sorted.length && i < 2; i++) {
      final t = sorted[i].key;
      top.add(t[0].toUpperCase() + t.substring(1));
    }
    return '${top.join(' & ')} Cluster';
  }

  String _generateClusterSummary(List<NoteNode> clusterNotes) {
    final sentences = <String>[];
    for (final note in clusterNotes) {
      final plainText = _extractPlain(note.content);
      sentences.addAll(plainText
          .split(RegExp(r'(?<=[.!?])\s+'))
          .where((s) => s.trim().isNotEmpty));
    }
    if (sentences.isEmpty) return 'No summary available.';

    final summary = <String>[];
    final used = <String>{};
    for (final note in clusterNotes) {
      final split = _extractPlain(note.content)
          .split(RegExp(r'(?<=[.!?])\s+'))
          .where((s) => s.trim().isNotEmpty)
          .toList();
      if (split.isNotEmpty) {
        final s = split.first.trim();
        if (s.length > 15 && !used.contains(s)) {
          summary.add(s);
          used.add(s);
        }
      }
      if (summary.length >= 3) break;
    }
    for (final s in sentences) {
      final c = s.trim();
      if (c.length > 20 && !used.contains(c)) {
        summary.add(c);
        used.add(c);
      }
      if (summary.length >= 3) break;
    }
    return summary.join(' ');
  }

  String _extractPlain(String content) {
    if (!content.startsWith('[')) return content;
    try {
      final List deltas = jsonDecode(content) as List;
      final buf = StringBuffer();
      for (final op in deltas) {
        if (op is Map && op.containsKey('insert')) {
          buf.write(op['insert'] as String);
        }
      }
      return buf.toString();
    } catch (_) {
      return content;
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF111115);
    const surface = Color(0xFF1A1A22);
    const border = Color(0xFF2A2A35);
    const accent = Color(0xFF6366F1);
    const accentSoft = Color(0xFF818CF8);

    final clusters = _cachedClusters;

    return Container(
      width: 380,
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          left: BorderSide(color: border, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 40,
            offset: const Offset(-10, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ───────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: border, width: 1)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.auto_graph_rounded,
                      size: 16, color: accentSoft),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Semantic Synthesis',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        'Local associative analysis',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.35),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                _SidebarCloseBtn(onTap: widget.onClose),
              ],
            ),
          ),

          // ── Stats row ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                _StatChip(
                  label: '${widget.notes.length}',
                  subtitle: 'nodes',
                  color: accentSoft,
                ),
                const SizedBox(width: 8),
                _StatChip(
                  label: '${widget.edges.length}',
                  subtitle: 'edges',
                  color: const Color(0xFF34D399),
                ),
                const SizedBox(width: 8),
                _StatChip(
                  label: '${clusters.length}',
                  subtitle: 'clusters',
                  color: const Color(0xFFF472B6),
                ),
              ],
            ),
          ),

          // ── Cluster list ─────────────────────────────────────────────────
          Expanded(
            child: clusters.isEmpty
                ? _buildEmptyState(accent, accentSoft)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                    itemCount: clusters.length,
                    itemBuilder: (context, index) {
                      final cluster = clusters[index];
                      return _ClusterCard(
                        cluster: cluster,
                        index: index,
                        surface: surface,
                        border: border,
                        accent: accent,
                        accentSoft: accentSoft,
                        onClusterTap: widget.onClusterTap,
                        onNodeTap: widget.onNodeTap,
                      );
                    },
                  ),
          ),
        ],
      ),
    )
        .animate()
        .slideX(begin: 1.0, end: 0.0, curve: Curves.easeOutCubic, duration: 320.ms);
  }

  Widget _buildEmptyState(Color accent, Color accentSoft) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.hub_outlined, size: 28, color: accentSoft),
            ),
            const SizedBox(height: 16),
            Text(
              'No Clusters Yet',
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add notes about related topics and connections will form automatically.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.3),
                height: 1.55,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Cluster card ─────────────────────────────────────────────────────────────

class _ClusterCard extends StatefulWidget {
  final SemanticCluster cluster;
  final int index;
  final Color surface;
  final Color border;
  final Color accent;
  final Color accentSoft;
  final Function(List<NoteNode>)? onClusterTap;
  final Function(NoteNode)? onNodeTap;

  const _ClusterCard({
    required this.cluster,
    required this.index,
    required this.surface,
    required this.border,
    required this.accent,
    required this.accentSoft,
    this.onClusterTap,
    this.onNodeTap,
  });

  @override
  State<_ClusterCard> createState() => _ClusterCardState();
}

class _ClusterCardState extends State<_ClusterCard> {
  bool _expanded = true;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: widget.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _hovered
              ? widget.accent.withValues(alpha: 0.35)
              : widget.border,
          width: 1,
        ),
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cluster header ──────────────────────────────────────────
            GestureDetector(
              onTap: () {
                setState(() => _expanded = !_expanded);
                widget.onClusterTap?.call(widget.cluster.nodes);
              },
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: widget.accentSoft,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: widget.accentSoft.withValues(alpha: 0.5),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.cluster.label,
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.9),
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: widget.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${widget.cluster.nodes.length}',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: widget.accentSoft,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ],
                ),
              ),
            ),

            if (_expanded) ...[
              // ── Summary ─────────────────────────────────────────────
              if (widget.cluster.summary.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: widget.border.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      widget.cluster.summary,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: Colors.white.withValues(alpha: 0.45),
                        height: 1.55,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),

              // ── Node chips ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: widget.cluster.nodes.map((node) {
                    final label = node.content.startsWith('[')
                        ? 'Note'
                        : node.content
                            .replaceAll('\n', ' ')
                            .trim()
                            .substring(0,
                                node.content.length > 22 ? 22 : node.content.length)
                            .trim();
                    return _NodeChip(
                      label: label.isEmpty ? 'Empty' : '$label…',
                      accentSoft: widget.accentSoft,
                      accent: widget.accent,
                      onTap: () => widget.onNodeTap?.call(node),
                    );
                  }).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(delay: (widget.index * 80).ms, duration: 280.ms)
        .slideY(begin: 0.06, end: 0);
  }
}

// ─── Node chip ────────────────────────────────────────────────────────────────

class _NodeChip extends StatefulWidget {
  final String label;
  final Color accentSoft;
  final Color accent;
  final VoidCallback onTap;

  const _NodeChip({
    required this.label,
    required this.accentSoft,
    required this.accent,
    required this.onTap,
  });

  @override
  State<_NodeChip> createState() => _NodeChipState();
}

class _NodeChipState extends State<_NodeChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _hovered
                ? widget.accent.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _hovered
                  ? widget.accentSoft.withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: _hovered
                      ? widget.accentSoft
                      : Colors.white.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: _hovered
                      ? widget.accentSoft
                      : Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Stat chip ────────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String label;
  final String subtitle;
  final Color color;

  const _StatChip({
    required this.label,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              fontSize: 10,
              color: color.withValues(alpha: 0.6),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Close button ─────────────────────────────────────────────────────────────

class _SidebarCloseBtn extends StatefulWidget {
  final VoidCallback onTap;
  const _SidebarCloseBtn({required this.onTap});

  @override
  State<_SidebarCloseBtn> createState() => _SidebarCloseBtnState();
}

class _SidebarCloseBtnState extends State<_SidebarCloseBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: _hovered
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.close_rounded,
            size: 16,
            color: Colors.white.withValues(alpha: _hovered ? 0.7 : 0.35),
          ),
        ),
      ),
    );
  }
}
