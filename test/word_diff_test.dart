import 'package:aura_novel/features/writer/word_diff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('texto igual no tiene cambios', () {
    final h = WordDiff.compute('La casa era vieja.', 'La casa era vieja.');
    expect(h.where((x) => x.changed), isEmpty);
  });

  test('aceptar todo da el texto nuevo y rechazar todo el original', () {
    const a = 'La casa era antigua y misteriosa. Mara sintió un escalofrío.';
    const b = 'La casa olía a sal. Mara sintió un escalofrío en la nuca.';
    final h = WordDiff.compute(a, b);
    final n = h.where((x) => x.changed).length;
    expect(n, greaterThan(1));
    expect(WordDiff.merge(h, List.filled(n, true)), b);
    expect(WordDiff.merge(h, List.filled(n, false)), a);
  });

  test('se puede aceptar un cambio y rechazar otro', () {
    const a = 'uno dos tres cuatro cinco';
    const b = 'uno DOS tres cuatro CINCO';
    final h = WordDiff.compute(a, b);
    expect(h.where((x) => x.changed), hasLength(2));
    expect(WordDiff.merge(h, [true, false]), 'uno DOS tres cuatro cinco');
  });

  test('insertar y borrar al final', () {
    final h = WordDiff.compute('hola', 'hola mundo');
    expect(WordDiff.merge(h, [true]), 'hola mundo');
    expect(WordDiff.merge(h, [false]), 'hola');
    expect(WordDiff.compute('', 'algo').single.changed, isTrue);
  });
}
