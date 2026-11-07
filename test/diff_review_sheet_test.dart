import 'package:aura_novel/core/theme/aura_theme.dart';
import 'package:aura_novel/features/writer/diff_review_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _open(WidgetTester tester, {required bool readOnly, void Function(String?)? onResult}) async {
  await tester.pumpWidget(MaterialApp(
    theme: AuraTheme.dark,
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            final r = await showDiffReview(context, original: 'La casa era vieja.', updated: 'La casa olía a sal.', readOnly: readOnly);
            onResult?.call(r);
          },
          child: const Text('abrir'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('comparar versiones solo deja cerrar', (tester) async {
    await _open(tester, readOnly: true);
    expect(find.text('Comparar versiones'), findsOneWidget);
    expect(find.text('Cerrar'), findsOneWidget);
    expect(find.text('Aplicar'), findsNothing);
  });

  testWidgets('revisar cambios devuelve el texto aceptado', (tester) async {
    String? result;
    await _open(tester, readOnly: false, onResult: (r) => result = r);
    expect(find.text('Aplicar'), findsOneWidget);
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
    expect(result, 'La casa olía a sal.');
  });

  testWidgets('Ninguno devuelve el original', (tester) async {
    String? result;
    await _open(tester, readOnly: false, onResult: (r) => result = r);
    await tester.tap(find.text('Ninguno'));
    await tester.pump();
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
    expect(result, 'La casa era vieja.');
  });
}
