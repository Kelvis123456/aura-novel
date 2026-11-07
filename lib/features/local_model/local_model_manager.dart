import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'local_model_catalog.dart';

class ModelDownloadException implements Exception {
  final String message;
  const ModelDownloadException(this.message);

  @override
  String toString() => message;
}

/// Lets the caller stop a download. The partial file stays, so the next
/// download of the same model resumes where this one stopped.
class DownloadCancel {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Keeps the downloaded model files in the app's private storage.
class LocalModelManager {
  final Directory? _dirOverride;
  final http.Client _http;

  /// [directory] is only for tests; the app uses its private support folder.
  LocalModelManager({Directory? directory, http.Client? httpClient})
      : _dirOverride = directory,
        _http = httpClient ?? http.Client();

  Future<Directory> _dir() async {
    final dir = _dirOverride ?? Directory(p.join((await getApplicationSupportDirectory()).path, 'models'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<File> fileFor(LocalModelInfo model) async => File(p.join((await _dir()).path, model.fileName));

  Future<bool> isInstalled(LocalModelInfo model) async => (await fileFor(model)).existsSync();

  /// Bytes already downloaded of a partial file, 0 when there is none.
  Future<int> partialBytes(LocalModelInfo model) async {
    final part = File('${(await fileFor(model)).path}.part');
    return part.existsSync() ? part.lengthSync() : 0;
  }

  /// Downloads [model], resuming a partial file when one exists. [onProgress]
  /// gets bytes received and the expected total. Throws [ModelDownloadException].
  Future<void> download(
    LocalModelInfo model, {
    void Function(int received, int total)? onProgress,
    DownloadCancel? cancel,
  }) async {
    final target = await fileFor(model);
    final part = File('${target.path}.part');
    var offset = part.existsSync() ? part.lengthSync() : 0;

    final request = http.Request('GET', Uri.parse(model.url));
    if (offset > 0) request.headers['Range'] = 'bytes=$offset-';

    final http.StreamedResponse response;
    try {
      response = await _http.send(request);
    } on SocketException {
      throw const ModelDownloadException('No hay conexión para descargar el modelo.');
    } on http.ClientException catch (e) {
      throw ModelDownloadException('No se pudo conectar para descargar el modelo: ${e.message}');
    }

    if (response.statusCode == 416 && offset > 0) {
      // The partial file is already the whole file.
      part.renameSync(target.path);
      return;
    }
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw ModelDownloadException('El servidor respondió ${response.statusCode} al descargar el modelo.');
    }
    // A server that ignores Range sends everything again.
    final resumed = response.statusCode == 206 && offset > 0;
    if (!resumed) offset = 0;

    final total = (response.contentLength ?? (model.sizeBytes - offset)) + offset;
    final sink = part.openWrite(mode: resumed ? FileMode.append : FileMode.write);
    var received = offset;
    try {
      await for (final chunk in response.stream) {
        if (cancel?.isCancelled ?? false) {
          await sink.flush();
          throw const ModelDownloadException('Descarga cancelada.');
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    // A cut connection can end the stream early without an error.
    if (received < model.sizeBytes * 0.97) {
      throw ModelDownloadException('La descarga quedó incompleta (${(received / 1e6).round()} de ${(model.sizeBytes / 1e6).round()} MB). Vuelve a intentarlo para continuar.');
    }
    part.renameSync(target.path);
  }

  Future<void> delete(LocalModelInfo model) async {
    final file = await fileFor(model);
    if (file.existsSync()) file.deleteSync();
    final part = File('${file.path}.part');
    if (part.existsSync()) part.deleteSync();
  }
}
