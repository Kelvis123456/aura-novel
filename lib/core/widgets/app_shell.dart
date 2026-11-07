import 'package:flutter/material.dart';

import '../../features/editor/editor_screen.dart';
import '../../features/lore/lore_studio_screen.dart';
import '../../features/projects/project_manager_screen.dart';
import '../../features/writer/writer_chat_screen.dart';
import '../theme/aura_theme.dart';

/// Root of the app: three tabs instead of a side drawer. Each tab keeps its
/// state when you switch (IndexedStack), so a half-written scene in Escribir
/// is still there after a look at Mundo.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  final _visits = ValueNotifier<int>(0);

  @override
  void dispose() {
    _visits.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.aura;
    return Scaffold(
      backgroundColor: c.bg,
      body: IndexedStack(
        index: _index,
        children: [
          EditorScreen(visitSignal: _visits),
          const WriterChatScreen(),
          const LoreStudioScreen(showAllProjects: true),
          const ProjectManagerScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: c.bg,
          indicatorColor: c.accent.withValues(alpha: 0.18),
          surfaceTintColor: Colors.transparent,
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(color: states.contains(WidgetState.selected) ? c.accentText : c.textDim),
          ),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: states.contains(WidgetState.selected) ? c.text : c.textDim,
            ),
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) {
              setState(() => _index = i);
              if (i == 0) _visits.value++;
            },
            destinations: const [
              NavigationDestination(icon: Icon(Icons.edit_outlined), selectedIcon: Icon(Icons.edit), label: 'Escribir'),
              NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'Asistente'),
              NavigationDestination(icon: Icon(Icons.public_outlined), selectedIcon: Icon(Icons.public), label: 'Mundo'),
              NavigationDestination(icon: Icon(Icons.library_books_outlined), selectedIcon: Icon(Icons.library_books), label: 'Proyectos'),
            ],
          ),
        ),
      ),
    );
  }
}
