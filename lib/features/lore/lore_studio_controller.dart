import 'package:flutter/material.dart';

import 'lore_repository.dart';
import 'models/character_model.dart';
import 'models/lore_item_model.dart';

/// Loads, filters and mutates characters/lore items for [LoreStudioScreen].
/// Both tabs share the same search query; the lore tab additionally filters
/// by [LoreCategory].
class LoreStudioController extends ChangeNotifier {
  final LoreRepository repository;
  final bool _ownsRepository;

  /// [repository] is normally the shared instance from [AppScope] — pass
  /// none to let this controller open (and own) its own database, e.g. in
  /// isolated tests.
  LoreStudioController({LoreRepository? repository})
      : repository = repository ?? LoreRepository(),
        _ownsRepository = repository == null;

  bool isLoading = true;
  List<CharacterModel> characters = [];
  List<LoreItemModel> loreItems = [];

  String searchQuery = '';
  LoreCategory? categoryFilter;

  Future<void> load() async {
    isLoading = true;
    notifyListeners();
    characters = await repository.getAllCharacters();
    loreItems = await repository.getAllLoreItems();
    isLoading = false;
    notifyListeners();
  }

  List<CharacterModel> get filteredCharacters {
    final q = searchQuery.trim().toLowerCase();
    if (q.isEmpty) return characters;
    return characters
        .where((c) => c.name.toLowerCase().contains(q) || c.aliases.any((a) => a.toLowerCase().contains(q)))
        .toList();
  }

  List<LoreItemModel> get filteredLoreItems {
    var items = loreItems;
    if (categoryFilter != null) {
      items = items.where((l) => l.category == categoryFilter).toList();
    }
    final q = searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      items = items
          .where((l) =>
              l.name.toLowerCase().contains(q) ||
              l.shortDescription.toLowerCase().contains(q) ||
              l.tags.any((t) => t.toLowerCase().contains(q)))
          .toList();
    }
    return items;
  }

  void updateSearchQuery(String value) {
    searchQuery = value;
    notifyListeners();
  }

  void updateCategoryFilter(LoreCategory? category) {
    categoryFilter = category;
    notifyListeners();
  }

  Future<void> saveCharacter(CharacterModel character) async {
    await repository.saveCharacter(character);
    await load();
  }

  Future<void> deleteCharacter(String id) async {
    await repository.deleteCharacter(id);
    await load();
  }

  Future<void> toggleCharacterForceInclude(CharacterModel character) async {
    await repository.saveCharacter(character.copyWith(forceInclude: !character.forceInclude));
    await load();
  }

  Future<void> saveLoreItem(LoreItemModel item) async {
    await repository.saveLoreItem(item);
    await load();
  }

  Future<void> deleteLoreItem(String id) async {
    await repository.deleteLoreItem(id);
    await load();
  }

  Future<void> toggleLoreItemForceInclude(LoreItemModel item) async {
    await repository.saveLoreItem(item.copyWith(forceInclude: !item.forceInclude));
    await load();
  }

  @override
  void dispose() {
    if (_ownsRepository) repository.close();
    super.dispose();
  }
}
