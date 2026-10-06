import 'package:flutter/material.dart';

import 'models/story_node_model.dart';

/// Renders a chapter's branching history as an indented tree: each node's
/// children (nodes whose `parentNodeId` points at it) are drawn nested one
/// level deeper. Tapping a node selects it (for loading into the editor);
/// the branch icon starts a new named fork from that exact point.
class BranchTreeViewer extends StatelessWidget {
  final List<StoryNodeModel> nodes;
  final String? selectedNodeId;
  final Color accent;
  final ValueChanged<StoryNodeModel> onSelectNode;
  final ValueChanged<StoryNodeModel> onBranchFromNode;

  const BranchTreeViewer({
    super.key,
    required this.nodes,
    required this.accent,
    required this.onSelectNode,
    required this.onBranchFromNode,
    this.selectedNodeId,
  });

  Map<String?, List<StoryNodeModel>> _groupByParent() {
    final map = <String?, List<StoryNodeModel>>{};
    for (final node in nodes) {
      map.putIfAbsent(node.parentNodeId, () => []).add(node);
    }
    for (final children in map.values) {
      children.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Este capítulo aún no tiene versiones guardadas.\nÁbrelo en el editor y pulsa "Guardar versión".',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ),
      );
    }

    final byParent = _groupByParent();
    final roots = byParent[null] ?? const [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final root in roots) ..._buildBranch(root, byParent, 0),
      ],
    );
  }

  List<Widget> _buildBranch(StoryNodeModel node, Map<String?, List<StoryNodeModel>> byParent, int depth) {
    final children = byParent[node.id] ?? const [];
    return [
      _NodeTile(
        node: node,
        depth: depth,
        accent: accent,
        selected: node.id == selectedNodeId,
        onTap: () => onSelectNode(node),
        onBranch: () => onBranchFromNode(node),
      ),
      for (final child in children) ..._buildBranch(child, byParent, depth + 1),
    ];
  }
}

class _NodeTile extends StatelessWidget {
  final StoryNodeModel node;
  final int depth;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onBranch;

  const _NodeTile({
    required this.node,
    required this.depth,
    required this.accent,
    required this.selected,
    required this.onTap,
    required this.onBranch,
  });

  @override
  Widget build(BuildContext context) {
    final label = node.isBranch ? node.branchName.trim() : 'Versión';
    final preview = node.content.trim().isEmpty ? '(vacío)' : node.content.trim();
    final snippet = preview.length > 90 ? '${preview.substring(0, 90)}…' : preview;

    return Padding(
      padding: EdgeInsets.only(left: depth * 20.0, bottom: 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: selected ? accent.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? accent : Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                Icon(node.isRoot ? Icons.fiber_manual_record : Icons.call_split, size: 14, color: accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: selected ? accent : Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        snippet,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.call_split, size: 16, color: Colors.white38),
                  tooltip: 'Crear rama desde aquí',
                  onPressed: onBranch,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
