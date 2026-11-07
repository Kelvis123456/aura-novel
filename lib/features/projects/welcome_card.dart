import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/theme/aura_theme.dart';
import 'sample_project.dart';

/// First-run guide on the Escribir tab. Shown only while there are no projects, so it goes away
/// by itself once the author creates one (or loads the example).
class WelcomeCard extends StatefulWidget {
  final ValueNotifier<int> refresh;
  const WelcomeCard({super.key, required this.refresh});

  @override
  State<WelcomeCard> createState() => _WelcomeCardState();
}

class _WelcomeCardState extends State<WelcomeCard> {
  bool _empty = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.refresh.addListener(_load);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void dispose() {
    widget.refresh.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final projects = await AppScope.of(context).projectRepository.getAllProjects();
    if (mounted) setState(() => _empty = projects.isEmpty);
  }

  Future<void> _createExample() async {
    setState(() => _busy = true);
    final scope = AppScope.of(context);
    await SampleProject.create(scope.projectRepository, scope.loreRepository);
    if (!mounted) return;
    setState(() => _busy = false);
    widget.refresh.value++;
  }

  @override
  Widget build(BuildContext context) {
    if (!_empty) return const SizedBox.shrink();
    final c = context.aura;
    Widget step(String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: c.text, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(body, style: TextStyle(color: c.textDim, fontSize: 13, height: 1.4)),
            ],
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.line)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('EMPEZAR', style: TextStyle(color: c.textDim, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.1)),
            const SizedBox(height: 8),
            Text('Tu novela, tu IA', style: TextStyle(fontFamily: AuraFonts.manuscript, fontSize: 22, color: c.text)),
            const SizedBox(height: 12),
            step('1. Conecta un modelo', 'En Ajustes pones una dirección y una clave, o descargas un modelo que corre en el teléfono.'),
            step('2. Crea un proyecto', 'En la pestaña Proyectos. Cada novela tiene su perfil de escritura, sus personajes y su mundo.'),
            step('3. Pídele al asistente', 'Dile qué pasa en el capítulo y lo escribe escena a escena. Tú decides qué se queda.'),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _busy ? null : _createExample,
                child: Text(_busy ? 'Creando…' : 'Probar con un proyecto de ejemplo'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
