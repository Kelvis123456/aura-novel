import 'package:aura_novel/features/lore/context_builder_service.dart';
import 'package:aura_novel/features/lore/lore_repository.dart';
import 'package:aura_novel/features/lore/models/character_model.dart';
import 'package:aura_novel/features/lore/models/lore_item_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// Only the two reads the service uses; the real repo never opens its DB
/// because nothing here touches `_database`.
class _FakeLoreRepository extends LoreRepository {
  final List<CharacterModel> characters;
  final List<LoreItemModel> loreItems;

  _FakeLoreRepository({this.characters = const [], this.loreItems = const []});

  @override
  Future<List<CharacterModel>> getAllCharacters() async => characters;

  @override
  Future<List<LoreItemModel>> getAllLoreItems() async => loreItems;
}

void main() {
  const mara = CharacterModel(id: 'c1', name: 'Mara', aliases: ['la Cuervo'], motivation: 'vengarse');
  const torre = LoreItemModel(
    id: 'l1',
    name: 'Torre Gris',
    category: LoreCategory.location,
    shortDescription: 'fortaleza en ruinas',
    tags: ['fortaleza'],
  );

  ContextBuilderService serviceWith({
    List<CharacterModel> characters = const [],
    List<LoreItemModel> loreItems = const [],
  }) =>
      ContextBuilderService(
        repository: _FakeLoreRepository(characters: characters, loreItems: loreItems),
      );

  test('devuelve null si no se menciona nada y no hay entradas forzadas', () async {
    final message = await serviceWith(characters: [mara], loreItems: [torre]).buildContextMessage('Llovía en el puerto.');
    expect(message, isNull);
  });

  test('detecta un personaje por nombre sin distinguir mayúsculas', () async {
    final message = await serviceWith(characters: [mara]).buildContextMessage('entonces MARA abrió la puerta');
    expect(message!.content, contains('Personaje activo: Mara'));
    expect(message.content, contains('vengarse'));
  });

  test('detecta por alias y por tag de lore', () async {
    final message = await serviceWith(characters: [mara], loreItems: [torre])
        .buildContextMessage('La Cuervo vio la fortaleza a lo lejos.');
    expect(message!.content, contains('Mara'));
    expect(message.content, contains('Torre Gris'));
  });

  test('no confunde una subcadena con el nombre (límite de palabra)', () async {
    final message = await serviceWith(characters: [mara]).buildContextMessage('Maravilloso amanecer.');
    expect(message, isNull);
  });

  test('forceInclude entra aunque el texto no lo mencione', () async {
    final pinned = mara.copyWith(forceInclude: true);
    final message = await serviceWith(characters: [pinned]).buildContextMessage('Nada relevante aquí.');
    expect(message!.content, contains('Mara'));
  });

  test('solo escanea las últimas N palabras', () async {
    final text = 'Mara ${List.filled(50, 'relleno').join(' ')}';
    final service = serviceWith(characters: [mara]);
    expect(await service.buildContextMessage(text, scanWindowWords: 10), isNull);
    expect(await service.buildContextMessage(text, scanWindowWords: 100), isNotNull);
  });

  test('las relaciones usan el nombre del otro personaje, no su id', () async {
    const tomas = CharacterModel(id: 'c2', name: 'Tomás');
    final linked = mara.copyWith(
      relationships: const [CharacterRelationship(characterId: 'c2', description: 'hermano menor')],
    );
    final message = await serviceWith(characters: [linked, tomas]).buildContextMessage('Mara respiró hondo.');
    expect(message!.content, contains('Tomás: hermano menor'));
  });
}
