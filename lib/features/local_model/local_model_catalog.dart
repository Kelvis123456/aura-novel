/// A model the app can download and run on the phone.
class LocalModelInfo {
  final String id;
  final String name;
  final String description;
  final String url;
  final String fileName;

  /// Download size, as published. Used for the progress bar and a sanity check.
  final int sizeBytes;

  /// Rough RAM the model needs while running, in GB.
  final double ramGb;

  const LocalModelInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.url,
    required this.fileName,
    required this.sizeBytes,
    required this.ramGb,
  });

  String get sizeLabel => sizeBytes >= 1000000000 ? '${(sizeBytes / 1e9).toStringAsFixed(1)} GB' : '${(sizeBytes / 1e6).round()} MB';
}

/// The models offered in the app. All are GGUF files of Gemma 3 with the
/// refusal behaviour removed ("abliterated"), so what they write depends on the
/// prompt and not on built-in refusals.
class LocalModelCatalog {
  static const models = [
    LocalModelInfo(
      id: 'gemma3-4b-abliterated-q4',
      name: 'Gemma 3 4B sin negativas',
      description: 'El que mejor escribe en español de los dos. Pide un teléfono con 8 GB de RAM o más y va despacio.',
      url: 'https://huggingface.co/mlabonne/gemma-3-4b-it-abliterated-v2-GGUF/resolve/main/gemma-3-4b-it-abliterated-v2.q4_k_m.gguf',
      fileName: 'gemma-3-4b-it-abliterated-v2.q4_k_m.gguf',
      sizeBytes: 2490000000,
      ramGb: 4.0,
    ),
    LocalModelInfo(
      id: 'gemma3-1b-abliterated-q4',
      name: 'Gemma 3 1B sin negativas',
      description: 'Pequeño y rápido, para borradores y escenas cortas. Escribe peor y se pierde en textos largos.',
      url: 'https://huggingface.co/bartowski/huihui-ai_gemma-3-1b-it-abliterated-GGUF/resolve/main/huihui-ai_gemma-3-1b-it-abliterated-Q4_K_M.gguf',
      fileName: 'huihui-ai_gemma-3-1b-it-abliterated-Q4_K_M.gguf',
      sizeBytes: 806000000,
      ramGb: 1.5,
    ),
  ];

  static LocalModelInfo? byId(String id) {
    for (final m in models) {
      if (m.id == id) return m;
    }
    return null;
  }
}
