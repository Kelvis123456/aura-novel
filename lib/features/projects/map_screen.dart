import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/app_scope.dart';
import '../lore/models/lore_item_model.dart';
import 'models/map_pin_model.dart';
import 'models/project_model.dart';
import 'project_repository.dart';

/// The project's map image with pins on it. Long-press to drop a pin, tap a
/// pin to see its note or remove it. The image is a file the author picks
/// (from Azgaar, Inkarnate, a drawing); the app doesn't draw maps itself.
class MapScreen extends StatefulWidget {
  final ProjectModel project;
  final Color accent;

  const MapScreen({super.key, required this.project, required this.accent});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late ProjectModel _project = widget.project;
  List<MapPin> _pins = [];
  List<LoreItemModel> _lore = [];
  bool _loaded = false;

  ProjectRepository get _repo => AppScope.of(context).projectRepository;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _load();
    }
  }

  Future<void> _load() async {
    final loreRepository = AppScope.of(context).loreRepository;
    final fresh = await _repo.getProject(_project.id);
    final pins = await _repo.getMapPins(_project.id);
    final lore = await loreRepository.getAllLoreItems();
    if (!mounted) return;
    setState(() {
      if (fresh != null) _project = fresh;
      _pins = pins;
      _lore = lore;
    });
  }

  File? get _imageFile {
    if (_project.mapPath.isEmpty) return null;
    final file = File(_project.mapPath);
    return file.existsSync() ? file : null;
  }

  Future<void> _pickImage() async {
    final repo = _repo;
    final picked = await FilePicker.platform.pickFiles(type: FileType.image);
    final source = picked?.files.single.path;
    if (source == null) return;

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'maps'))..createSync(recursive: true);
    // New name each time: Flutter caches decoded images by path.
    final target = p.join(dir.path, '${_project.id}-${DateTime.now().millisecondsSinceEpoch}${p.extension(source)}');
    await File(source).copy(target);

    final old = _project.mapPath;
    await repo.setProjectMapPath(_project.id, target);
    final updated = await repo.getProject(_project.id);
    // Only delete files this screen put in maps/: a restored backup can carry any path.
    if (old.isNotEmpty && old != target && p.isWithin(dir.path, old)) {
      try {
        File(old).deleteSync();
      } on FileSystemException {
        // Already gone: nothing to clean.
      }
    }
    if (mounted && updated != null) setState(() => _project = updated);
  }

  Future<void> _addPin(Offset fraction) async {
    final label = TextEditingController();
    String? loreId;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A0B12),
          title: const Text('Nuevo pin', style: TextStyle(color: Colors.white, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: label, autofocus: true, decoration: const InputDecoration(labelText: 'Nombre')),
              if (_lore.isNotEmpty)
                DropdownButtonFormField<String?>(
                  initialValue: loreId,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF1A0B12),
                  decoration: const InputDecoration(labelText: 'Entrada de lore (opcional)'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Ninguna')),
                    for (final l in _lore) DropdownMenuItem<String?>(value: l.id, child: Text(l.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setDialogState(() {
                    loreId = v;
                    if (label.text.trim().isEmpty && v != null) {
                      label.text = _lore.firstWhere((l) => l.id == v).name;
                    }
                  }),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(backgroundColor: widget.accent),
              child: const Text('Poner'),
            ),
          ],
        ),
      ),
    );
    final text = label.text.trim();
    label.dispose();
    if (saved != true || text.isEmpty) return;
    await _repo.saveMapPin(MapPin(
      id: ProjectRepository.generateId(),
      projectId: _project.id,
      x: fraction.dx.clamp(0.0, 1.0),
      y: fraction.dy.clamp(0.0, 1.0),
      label: text,
      loreItemId: loreId,
    ));
    await _load();
  }

  Future<void> _showPin(MapPin pin) async {
    final lore = _lore.where((l) => l.id == pin.loreItemId).firstOrNull;
    final remove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A0B12),
        title: Text(pin.label, style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(
          lore == null
              ? 'Sin entrada de lore enlazada.'
              : '${lore.category.label}: ${lore.shortDescription.isEmpty ? lore.longDetails : lore.shortDescription}',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Quitar pin', style: TextStyle(color: Colors.redAccent)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cerrar', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
    if (remove == true) {
      await _repo.deleteMapPin(pin.id);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = _imageFile;
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Mapa · ${_project.title}', overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(icon: const Icon(Icons.image_outlined), tooltip: file == null ? 'Elegir imagen del mapa' : 'Cambiar imagen', onPressed: _pickImage),
        ],
      ),
      body: file == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _project.mapPath.isEmpty
                          ? 'Elige una imagen de tu mapa (de Azgaar, Inkarnate o un dibujo) y márcala con pines.'
                          : 'No encuentro la imagen del mapa en este dispositivo. Elígela de nuevo; los pines se conservan.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white54),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _pickImage,
                      style: FilledButton.styleFrom(backgroundColor: widget.accent),
                      child: const Text('Elegir imagen'),
                    ),
                  ],
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, box) => InteractiveViewer(
                constrained: false,
                minScale: 0.5,
                maxScale: 5,
                child: SizedBox(
                  width: box.maxWidth,
                  child: Stack(
                    children: [
                      Image.file(file, width: box.maxWidth, fit: BoxFit.fitWidth),
                      Positioned.fill(
                        child: LayoutBuilder(
                          builder: (context, area) => GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onLongPressStart: (d) => _addPin(Offset(d.localPosition.dx / area.maxWidth, d.localPosition.dy / area.maxHeight)),
                            child: Stack(
                              children: [
                                for (final pin in _pins)
                                  Positioned(
                                    left: pin.x * area.maxWidth - 14,
                                    top: pin.y * area.maxHeight - 28,
                                    child: GestureDetector(
                                      onTap: () => _showPin(pin),
                                      child: Tooltip(
                                        message: pin.label,
                                        child: Icon(Icons.location_on, size: 28, color: widget.accent),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
