import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_scope.dart';
import '../../core/network/models/chat_message.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/widgets/aura_mark.dart';
import 'chapter_writer.dart';
import 'chat_entry.dart';
import 'craft_tools_sheet.dart';
import 'diff_review_sheet.dart';
import 'writer_chat_controller.dart';
import 'writing_profile_sheet.dart';

/// The writing assistant: a conversation that can also write long chapters,
/// research a topic for the story, and run any craft tool on a passage.
class WriterChatScreen extends StatefulWidget {
  /// Ticks when the tab is shown again, so projects and chapters made elsewhere appear.
  final ValueNotifier<int>? visitSignal;

  const WriterChatScreen({super.key, this.visitSignal});

  @override
  State<WriterChatScreen> createState() => _WriterChatScreenState();
}

class _WriterChatScreenState extends State<WriterChatScreen> {
  late final WriterChatController _controller;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  ChatMode _mode = ChatMode.chat;
  int _words = 1500;
  bool _continueChapter = true;
  bool _deepResearch = true;

  static const _wordOptions = [800, 1500, 3000, 5000];

  @override
  void initState() {
    super.initState();
    final scope = AppScope.of(context);
    _controller = WriterChatController(
      repository: scope.projectRepository,
      lore: scope.loreRepository,
      service: scope.writerService,
      chapterWriter: scope.chapterWriter,
      storage: scope.configStorage,
    )..addListener(_onChanged);
    _controller.load();
    widget.visitSignal?.addListener(_reload);
  }

  void _reload() {
    if (!_controller.generating) _controller.load();
  }

  int _lastCount = 0;

  void _onChanged() {
    setState(() {});
    // Follow the text while it streams, and when a new message arrives.
    if (_controller.generating || _controller.entries.length != _lastCount) {
      _lastCount = _controller.entries.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
  }

  @override
  void dispose() {
    widget.visitSignal?.removeListener(_reload);
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    _controller.send(text, _mode, words: _words, continueChapter: _continueChapter, deepResearch: _deepResearch);
  }

  Future<void> _tools() async {
    final c = _controller;
    final lastAnswer = c.entries.lastWhere((e) => e.role == ChatRole.assistant, orElse: () => ChatEntry(id: '', role: ChatRole.assistant, content: '', createdAt: DateTime.now())).content;
    final request = await showCraftTools(context, defaultMaterial: lastAnswer);
    if (request != null) await c.runTool(request.moduleId, request.material, note: request.note);
  }

  Future<void> _profile() async {
    final updated = await WritingProfileSheet.show(context, _controller.profile);
    if (updated != null) await _controller.saveProfile(updated);
  }

  Future<void> _insert(ChatEntry entry) async {
    final messenger = ScaffoldMessenger.of(context);
    if (_controller.project == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Crea o elige un proyecto primero.')));
      return;
    }
    String? title;
    if (_controller.chapter == null) {
      final field = TextEditingController();
      title = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Nuevo capítulo'),
          content: TextField(controller: field, autofocus: true, decoration: const InputDecoration(labelText: 'Título del capítulo')),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.of(dialogContext).pop(field.text), child: const Text('Crear y añadir')),
          ],
        ),
      );
      field.dispose();
      if (title == null || title.trim().isEmpty) return;
    }
    final chapter = await _controller.insert(entry, newChapterTitle: title);
    messenger.showSnackBar(SnackBar(content: Text('Añadido a «${chapter.title}». Lo ves en Proyectos, como una versión nueva.')));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.aura;
    final ctl = _controller;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: const Text('Asistente'),
        actions: [
          IconButton(icon: const Icon(Icons.auto_fix_high_outlined), tooltip: 'Herramientas de oficio', onPressed: ctl.generating ? null : _tools),
          IconButton(icon: const Icon(Icons.tune), tooltip: 'Cómo escribe este proyecto', onPressed: ctl.project == null ? null : _profile),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            color: c.surface,
            onSelected: (v) => v == 'clear' ? ctl.clear() : null,
            itemBuilder: (_) => const [PopupMenuItem(value: 'clear', child: Text('Borrar la conversación'))],
          ),
        ],
      ),
      body: Column(
        children: [
          _targetBar(c),
          Expanded(child: ctl.entries.isEmpty ? _empty(c) : _messages(c)),
          if (ctl.error != null) _errorBar(c),
          _composer(c),
        ],
      ),
    );
  }

  Widget _targetBar(AuraColors c) {
    final ctl = _controller;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                isExpanded: true,
                value: ctl.project?.id,
                dropdownColor: c.surface,
                style: TextStyle(color: c.text, fontSize: 14),
                hint: Text('Sin proyecto', style: TextStyle(color: c.textDim)),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Sin proyecto')),
                  for (final p in ctl.projects) DropdownMenuItem<String?>(value: p.id, child: Text(p.title, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: ctl.generating ? null : ctl.selectProject,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                isExpanded: true,
                value: ctl.chapter?.id,
                dropdownColor: c.surface,
                style: TextStyle(color: c.text, fontSize: 14),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Capítulo nuevo')),
                  for (final ch in ctl.chapters) DropdownMenuItem<String?>(value: ch.id, child: Text(ch.title, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: ctl.generating || ctl.project == null ? null : ctl.selectChapter,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(AuraColors c) {
    final ideas = [
      (ChatMode.chapter, 'Escribe el capítulo 1: una mujer llega a un faro abandonado y descubre que alguien lo ha mantenido encendido.'),
      (ChatMode.chat, 'Ayúdame a plantear una novela: dame tres premisas distintas y dime cuál tiene más recorrido.'),
      (ChatMode.research, 'Cómo funciona realmente un faro de lente Fresnel y quién lo mantenía en el siglo XIX.'),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      children: [
        const Center(child: AuraMark(size: 64)),
        const SizedBox(height: 20),
        Text('Pídele lo que quieras escribir', textAlign: TextAlign.center, style: TextStyle(fontFamily: AuraFonts.manuscript, fontSize: 26, color: c.text)),
        const SizedBox(height: 8),
        Text(
          'Capítulos enteros, escenas, ideas, críticas o investigación para tu historia. Sin límites de contenido por parte de la app.',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.textDim, fontSize: 14),
        ),
        const SizedBox(height: 28),
        for (final (mode, text) in ideas)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: c.surface,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() {
                  _mode = mode;
                  _input.text = text;
                }),
                child: Padding(padding: const EdgeInsets.all(16), child: Text(text, style: TextStyle(color: c.text, fontSize: 14))),
              ),
            ),
          ),
      ],
    );
  }

  Widget _messages(AuraColors c) {
    final entries = _controller.entries;
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[i];
        final isLast = i == entries.length - 1;
        return e.role == ChatRole.user ? _userBubble(c, e) : _answer(c, e, isLast);
      },
    );
  }

  Widget _userBubble(AuraColors c, ChatEntry e) {
    final label = switch (e.kind) {
      'chapter' => 'Capítulo',
      'research' => 'Investigación',
      'tool' => 'Herramienta',
      _ => null,
    };
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(top: 16, left: 48),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: c.surfaceHigh, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (label != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(label.toUpperCase(), style: TextStyle(color: c.accentText, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
              ),
            Text(e.content.length > 700 ? '${e.content.substring(0, 700)}…' : e.content, style: TextStyle(color: c.text, fontSize: 14, height: 1.4)),
          ],
        ),
      ),
    );
  }

  Widget _answer(AuraColors c, ChatEntry e, bool isLast) {
    final ctl = _controller;
    final streaming = ctl.generating && isLast;
    final prose = e.kind == 'chapter' || e.kind == 'tool';
    final words = ChapterWriter.countWords(e.content);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            e.content.isEmpty ? '…' : e.content,
            style: prose
                ? TextStyle(fontFamily: AuraFonts.manuscript, fontSize: 18, height: 1.65, color: c.text)
                : TextStyle(fontSize: 15, height: 1.5, color: c.text),
          ),
          if (streaming && ctl.progress != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('${ctl.progress} · $words palabras', style: TextStyle(color: c.accentText, fontSize: 12)),
            ),
          if (!streaming && e.content.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 0,
              children: [
                if (prose || words > 150)
                  Text('$words palabras', style: TextStyle(color: c.textFaint, fontSize: 12, height: 2.4)),
                _action(c, Icons.copy_outlined, 'Copiar', () {
                  Clipboard.setData(ClipboardData(text: e.content));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copiado.')));
                }),
                if (prose || words > 150) _action(c, Icons.note_add_outlined, 'Añadir al capítulo', () => _insert(e)),
                if (ctl.originalOf(e) != null)
                  _action(c, Icons.compare_arrows, 'Ver cambios', () async {
                    final merged = await showDiffReview(context, original: ctl.originalOf(e)!, updated: e.content);
                    if (merged != null && merged != e.content) await ctl.replaceContent(e, merged);
                  }),
                if (e.kind == 'research') _action(c, Icons.bookmark_add_outlined, 'Guardar en Mundo', () async {
                  await ctl.saveResearch(e);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Guardado como ficha de investigación.')));
                }),
                if (isLast) _action(c, Icons.refresh, 'Otra vez', ctl.regenerate),
              ],
            ),
            if (isLast && e.kind != 'research')
              Wrap(
                spacing: 8,
                children: [
                  for (final q in const ['Más largo', 'Más crudo', 'Más suave', 'Continúa'])
                    ActionChip(
                      label: Text(q, style: TextStyle(color: c.text, fontSize: 12)),
                      backgroundColor: c.surface,
                      side: BorderSide(color: c.line),
                      onPressed: () => ctl.send(_quick(q), ChatMode.chat),
                    ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  static String _quick(String q) => switch (q) {
        'Más largo' => 'Escribe esto de nuevo, bastante más largo y desarrollado: dramatiza más, no resumas.',
        'Más crudo' => 'Reescribe esto más crudo y directo, sin suavizar nada.',
        'Más suave' => 'Reescribe esto más contenido y sugerente.',
        _ => 'Continúa desde donde lo dejaste, con la misma voz.',
      };

  Widget _action(AuraColors c, IconData icon, String label, VoidCallback onTap) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: c.textDim),
      label: Text(label, style: TextStyle(color: c.textDim, fontSize: 12)),
      style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6)),
    );
  }

  Widget _errorBar(AuraColors c) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: c.danger.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.danger.withValues(alpha: 0.4))),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: c.danger),
          const SizedBox(width: 10),
          Expanded(child: Text(_controller.error!, style: TextStyle(color: c.danger, fontSize: 13))),
          if (_controller.entries.isNotEmpty && _controller.entries.last.role == ChatRole.user)
            TextButton(onPressed: _controller.generating ? null : _controller.regenerate, child: const Text('Reintentar')),
        ],
      ),
    );
  }

  Widget _composer(AuraColors c) {
    final ctl = _controller;
    final hint = switch (_mode) {
      ChatMode.chat => 'Escribe, pregunta o pide lo que sea…',
      ChatMode.chapter => 'Qué pasa en este capítulo…',
      ChatMode.research => 'Qué quieres investigar para tu historia…',
    };
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(color: c.bg, border: Border(top: BorderSide(color: c.line))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (mode, label) in const [(ChatMode.chat, 'Charlar'), (ChatMode.chapter, 'Escribir'), (ChatMode.research, 'Investigar')])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(label, style: TextStyle(color: c.text)),
                        selected: _mode == mode,
                        onSelected: (_) => setState(() => _mode = mode),
                        selectedColor: c.accent.withValues(alpha: 0.2),
                        showCheckmark: false,
                        side: BorderSide(color: _mode == mode ? c.accent : c.line),
                      ),
                    ),
                  if (_mode == ChatMode.research) ...[
                    Container(width: 1, height: 20, color: c.line, margin: const EdgeInsets.only(right: 8)),
                    FilterChip(
                      label: Text('Profunda', style: TextStyle(color: c.text)),
                      tooltip: 'Varias consultas y una síntesis. Tarda más y gasta más llamadas.',
                      selected: _deepResearch,
                      onSelected: (v) => setState(() => _deepResearch = v),
                      showCheckmark: false,
                      selectedColor: c.surfaceHigh,
                      side: BorderSide(color: c.line),
                    ),
                  ],
                  if (_mode == ChatMode.chapter) ...[
                    Container(width: 1, height: 20, color: c.line, margin: const EdgeInsets.only(right: 8)),
                    for (final w in _wordOptions)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text('$w', style: TextStyle(color: c.text)),
                          selected: _words == w,
                          onSelected: (_) => setState(() => _words = w),
                          selectedColor: c.surfaceHigh,
                          showCheckmark: false,
                          side: BorderSide(color: c.line),
                        ),
                      ),
                    Text('palabras', style: TextStyle(color: c.textDim, fontSize: 12)),
                    if (ctl.chapter != null) ...[
                      const SizedBox(width: 8),
                      FilterChip(
                        label: Text('Seguir el texto', style: TextStyle(color: c.text)),
                        selected: _continueChapter,
                        onSelected: (v) => setState(() => _continueChapter = v),
                        showCheckmark: false,
                        selectedColor: c.surfaceHigh,
                        side: BorderSide(color: c.line),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 6,
                    textInputAction: TextInputAction.newline,
                    style: TextStyle(color: c.text),
                    decoration: InputDecoration(hintText: hint, border: InputBorder.none),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: c.accent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: ctl.generating ? ctl.stop : _send,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Icon(ctl.generating ? Icons.stop_rounded : Icons.arrow_upward_rounded, color: c.onAccent, size: 22),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
