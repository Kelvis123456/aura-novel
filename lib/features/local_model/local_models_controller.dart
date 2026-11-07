import 'package:flutter/foundation.dart';

import '../../core/network/local_llm_client.dart';
import 'local_model_catalog.dart';
import 'local_model_manager.dart';

/// State of the model list in the settings: which are downloaded, the progress
/// of the ones downloading, and the actions on them.
class LocalModelsController extends ChangeNotifier {
  final LocalModelManager _manager;
  final LocalLlmClient _client;

  LocalModelsController({required LocalModelManager manager, required LocalLlmClient client})
      : _manager = manager,
        _client = client;

  final Set<String> installed = {};

  /// 0 to 1 for models being downloaded.
  final Map<String, double> progress = {};
  final Map<String, String> errors = {};
  final Map<String, DownloadCancel> _cancels = {};
  final Map<String, int> partial = {};
  bool _disposed = false;

  bool isDownloading(String id) => _cancels.containsKey(id);

  Future<void> refresh() async {
    for (final m in LocalModelCatalog.models) {
      if (await _manager.isInstalled(m)) {
        installed.add(m.id);
      } else {
        installed.remove(m.id);
        final bytes = await _manager.partialBytes(m);
        if (bytes > 0) partial[m.id] = bytes;
      }
    }
    _notify();
  }

  Future<void> download(LocalModelInfo model) async {
    if (isDownloading(model.id)) return;
    final cancel = DownloadCancel();
    _cancels[model.id] = cancel;
    errors.remove(model.id);
    progress[model.id] = (partial[model.id] ?? 0) / model.sizeBytes;
    _notify();
    var lastNotify = 0;
    try {
      await _manager.download(
        model,
        cancel: cancel,
        onProgress: (received, total) {
          progress[model.id] = total == 0 ? 0 : received / total;
          // Every percent is enough for a progress bar.
          final step = (progress[model.id]! * 100).floor();
          if (step != lastNotify) {
            lastNotify = step;
            _notify();
          }
        },
      );
      installed.add(model.id);
      partial.remove(model.id);
    } on ModelDownloadException catch (e) {
      errors[model.id] = e.message;
      partial[model.id] = await _manager.partialBytes(model);
    } finally {
      _cancels.remove(model.id);
      progress.remove(model.id);
      _notify();
    }
  }

  void cancel(LocalModelInfo model) => _cancels[model.id]?.cancel();

  Future<void> delete(LocalModelInfo model) async {
    await _client.unload();
    await _manager.delete(model);
    installed.remove(model.id);
    partial.remove(model.id);
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final c in _cancels.values) {
      c.cancel();
    }
    super.dispose();
  }
}
