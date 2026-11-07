import 'package:aura_novel/features/lore/models/character_model.dart';
import 'package:aura_novel/features/lore/relationship_graph.dart';
import 'package:flutter_test/flutter_test.dart';

CharacterModel c(String id, [List<String> to = const []]) =>
    CharacterModel(id: id, name: id, relationships: [for (final t in to) CharacterRelationship(characterId: t, description: 'x')]);

void main() {
  test('sin personajes no hay posiciones, con uno va al centro', () {
    expect(GraphLayout.compute([]), isEmpty);
    expect(GraphLayout.compute([c('a')])['a']!.dx, 500);
  });

  test('es determinista y todos quedan dentro del lienzo', () {
    final cast = [c('a', ['b']), c('b', ['c']), c('c'), c('d', ['a']), c('e')];
    final one = GraphLayout.compute(cast);
    final two = GraphLayout.compute(cast);
    expect(one, two);
    for (final p in one.values) {
      expect(p.dx, inInclusiveRange(60, 940));
      expect(p.dy, inInclusiveRange(60, 940));
    }
  });

  test('los vinculados quedan más cerca que los que no lo están', () {
    final cast = [c('a', ['b']), c('b'), c('x'), c('y'), c('z')];
    final p = GraphLayout.compute(cast);
    expect((p['a']! - p['b']!).distance, lessThan((p['a']! - p['z']!).distance));
  });

  test('una relación con un id que no existe se ignora', () {
    expect(() => GraphLayout.compute([c('a', ['fantasma']), c('b')]), returnsNormally);
  });
}
