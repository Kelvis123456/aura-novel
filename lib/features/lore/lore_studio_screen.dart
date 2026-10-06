import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import 'character_form_sheet.dart';
import 'lore_item_form_sheet.dart';
import 'lore_studio_controller.dart';
import 'models/character_model.dart';
import 'models/lore_item_model.dart';

/// Studio de Personajes y Lore: two tabs (Personajes / Lore y Mundo) backed
/// by [LoreStudioController], each with search, dark-glassmorphism cards,
/// and a "Forzar inclusión" switch consumed by [ContextBuilderService].
class LoreStudioScreen extends StatefulWidget {
  final Color accentColor;

  const LoreStudioScreen({super.key, this.accentColor = const Color(0xFFDC143C)});

  @override
  State<LoreStudioScreen> createState() => _LoreStudioScreenState();
}

class _LoreStudioScreenState extends State<LoreStudioScreen> with SingleTickerProviderStateMixin {
  late final LoreStudioController _controller;
  late final TabController _tabController;
  final _searchFieldController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final scope = AppScope.of(context);
    _controller = LoreStudioController(repository: scope.loreRepository)..addListener(_onControllerChanged);
    _tabController = TabController(length: 2, vsync: this);
    _controller.load();
  }

  void _onControllerChanged() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _tabController.dispose();
    _searchFieldController.dispose();
    super.dispose();
  }

  Future<void> _createOrEditCharacter({CharacterModel? existing}) async {
    final others = _controller.characters.where((c) => c.id != existing?.id).toList();
    final result = await CharacterFormSheet.show(
      context,
      existing: existing,
      otherCharacters: others,
      accent: widget.accentColor,
    );
    if (result != null) await _controller.saveCharacter(result);
  }

  Future<void> _createOrEditLoreItem({LoreItemModel? existing}) async {
    final result = await LoreItemFormSheet.show(context, existing: existing, accent: widget.accentColor);
    if (result != null) await _controller.saveLoreItem(result);
  }

  Future<bool> _confirmDelete(String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A0B12),
        title: Text('¿Eliminar "$title"?', style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: const Text(
          'Esta acción no se puede deshacer.',
          style: TextStyle(color: Colors.white60),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor;

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Studio de Personajes y Lore'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: accent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          tabs: const [
            Tab(text: 'Personajes'),
            Tab(text: 'Lore y Mundo'),
          ],
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.6),
            radius: 1.4,
            colors: [Color(0xFF1A0B12), Color(0xFF000000)],
          ),
        ),
        child: _controller.isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _buildSearchBar(accent),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildCharactersTab(accent),
                        _buildLoreTab(accent),
                      ],
                    ),
                  ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: accent,
        onPressed: () {
          if (_tabController.index == 0) {
            _createOrEditCharacter();
          } else {
            _createOrEditLoreItem();
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildSearchBar(Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: TextField(
          controller: _searchFieldController,
          onChanged: _controller.updateSearchQuery,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 20),
            hintText: 'Buscar personajes o lore…',
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            suffixIcon: _searchFieldController.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, color: Colors.white38, size: 18),
                    onPressed: () {
                      _searchFieldController.clear();
                      _controller.updateSearchQuery('');
                    },
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildCharactersTab(Color accent) {
    final characters = _controller.filteredCharacters;

    if (characters.isEmpty) {
      return _emptyState('Aún no hay personajes. Pulsa "+" para crear el primero.');
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 190,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: characters.length,
      itemBuilder: (context, index) {
        final character = characters[index];
        return _CharacterCard(
          character: character,
          accent: accent,
          onTap: () => _createOrEditCharacter(existing: character),
          onToggleForceInclude: () => _controller.toggleCharacterForceInclude(character),
          onDelete: () async {
            if (await _confirmDelete(character.name)) {
              await _controller.deleteCharacter(character.id);
            }
          },
        );
      },
    );
  }

  Widget _buildLoreTab(Color accent) {
    final items = _controller.filteredLoreItems;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _categoryChip(null, 'Todos', accent),
                for (final category in LoreCategory.values) _categoryChip(category, category.label, accent),
              ],
            ),
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? _emptyState('No hay elementos de lore en esta categoría.')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _LoreItemCard(
                      item: item,
                      accent: accent,
                      onTap: () => _createOrEditLoreItem(existing: item),
                      onToggleForceInclude: () => _controller.toggleLoreItemForceInclude(item),
                      onDelete: () async {
                        if (await _confirmDelete(item.name)) {
                          await _controller.deleteLoreItem(item.id);
                        }
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _categoryChip(LoreCategory? category, String label, Color accent) {
    final selected = _controller.categoryFilter == category;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => _controller.updateCategoryFilter(category),
        selectedColor: accent.withValues(alpha: 0.3),
        backgroundColor: Colors.white.withValues(alpha: 0.05),
        labelStyle: TextStyle(color: selected ? Colors.white : Colors.white60, fontSize: 12),
        side: BorderSide(color: selected ? accent : Colors.white24),
      ),
    );
  }

  Widget _emptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white38, fontSize: 13),
        ),
      ),
    );
  }
}

class _CharacterCard extends StatelessWidget {
  final CharacterModel character;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback onToggleForceInclude;
  final VoidCallback onDelete;

  const _CharacterCard({
    required this.character,
    required this.accent,
    required this.onTap,
    required this.onToggleForceInclude,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: accent.withValues(alpha: 0.2),
                child: Text(
                  character.name.isEmpty ? '?' : character.name[0].toUpperCase(),
                  style: TextStyle(color: accent, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  character.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 16, color: Colors.white38),
                onPressed: onDelete,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              ),
            ],
          ),
          if (character.aliases.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                character.aliases.join(', '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: Text(
              character.motivation.isEmpty ? 'Sin motivación definida.' : character.motivation,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.3),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Forzar en IA', style: TextStyle(color: Colors.white38, fontSize: 11)),
              Transform.scale(
                scale: 0.75,
                child: Switch(
                  value: character.forceInclude,
                  onChanged: (_) => onToggleForceInclude(),
                  activeThumbColor: accent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LoreItemCard extends StatelessWidget {
  final LoreItemModel item;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback onToggleForceInclude;
  final VoidCallback onDelete;

  const _LoreItemCard({
    required this.item,
    required this.accent,
    required this.onTap,
    required this.onToggleForceInclude,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _GlassCard(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          item.category.label,
                          style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.shortDescription.isEmpty ? 'Sin descripción.' : item.shortDescription,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  if (item.tags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        item.tags.map((t) => '#$t').join(' '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: accent.withValues(alpha: 0.8), fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
            Column(
              children: [
                Transform.scale(
                  scale: 0.75,
                  child: Switch(
                    value: item.forceInclude,
                    onChanged: (_) => onToggleForceInclude(),
                    activeThumbColor: accent,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 16, color: Colors.white38),
                  onPressed: onDelete,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  const _GlassCard({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: child,
        ),
      ),
    );
  }
}
