import 'package:aura_novel/features/lore/models/character_model.dart';
import 'package:aura_novel/features/lore/models/lore_item_model.dart';
import 'package:aura_novel/features/projects/models/project_model.dart';
import 'package:aura_novel/features/projects/models/timeline_event_model.dart';
import 'package:aura_novel/features/projects/wiki_export_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final project = ProjectModel(id: 'p', title: 'El Faro <1>', synopsis: 'Una novela.', createdAt: DateTime(2026), updatedAt: DateTime(2026));
  const chapters = [
    ChapterModel(id: 'c1', projectId: 'p', title: 'Uno', order: 0),
    ChapterModel(id: 'c2', projectId: 'p', title: 'Dos', order: 1),
  ];
  const mara = CharacterModel(
    id: 'mara',
    name: 'Mara',
    appearance: 'Alta',
    secretsLimits: 'ES LA HEREDERA',
    relationships: [CharacterRelationship(characterId: 'tomas', description: 'hermano')],
  );
  const tomas = CharacterModel(id: 'tomas', name: 'Tomás', visibleFromChapter: 2);
  const torre = LoreItemModel(id: 'torre', name: 'La Torre', category: LoreCategory.location, shortDescription: 'Al norte');

  Map<String, String> build({int? upTo, List<TimelineEvent> events = const []}) => WikiExportService.buildFiles(
        project: project,
        chapters: chapters,
        characters: const [mara, tomas],
        loreItems: const [torre],
        events: events,
        upToChapter: upTo,
      );

  test('nunca publica secretos ni límites del personaje', () {
    final files = build();
    expect(files.values.any((c) => c.contains('ES LA HEREDERA')), isFalse);
  });

  test('escapa HTML en títulos y textos', () {
    final files = build();
    expect(files['index.html'], contains('El Faro &lt;1&gt;'));
    expect(files['index.html'], isNot(contains('<1>')));
  });

  test('upToChapter oculta fichas futuras y las relaciones hacia ellas', () {
    final files = build(upTo: 1);
    expect(files.keys.any((k) => k.contains('tomas')), isFalse);
    final maraPage = files.entries.firstWhere((e) => e.key.contains('mara')).value;
    expect(maraPage, isNot(contains('hermano')));
    expect(files['index.html'], isNot(contains('Tomás')));
  });

  test('sin límite publica todo y enlaza las relaciones', () {
    final files = build();
    final maraPage = files.entries.firstWhere((e) => e.key.contains('mara')).value;
    expect(maraPage, contains('hermano'));
    expect(maraPage, contains('personaje-2-tomas.html'));
    expect(files['index.html'], contains('La Torre'));
  });

  test('los eventos sin capítulo solo salen al publicar todo el libro', () {
    const free = TimelineEvent(id: 'e1', projectId: 'p', title: 'Libre');
    const linked = TimelineEvent(id: 'e2', projectId: 'p', chapterId: 'c2', title: 'Enlazado');

    final partial = build(upTo: 1, events: const [free, linked]);
    expect(partial.containsKey('linea-de-tiempo.html'), isFalse);

    final mid = build(upTo: 2, events: const [free, linked])['linea-de-tiempo.html']!;
    expect(mid, contains('Enlazado'));
    expect(mid, isNot(contains('Libre')));

    final all = build(events: const [free, linked])['linea-de-tiempo.html']!;
    expect(all, contains('Libre'));
  });

  test('una wiki vacía igual genera index y estilos', () {
    final files = WikiExportService.buildFiles(
      project: project,
      chapters: const [],
      characters: const [],
      loreItems: const [],
      events: const [],
    );
    expect(files.keys, containsAll(['index.html', 'style.css']));
  });
}
