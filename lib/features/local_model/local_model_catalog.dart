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

/// The models offered in the app. All are GGUF files (Qwen3 and Gemma 3) with
/// the refusal behaviour removed ("abliterated"), so what they write depends on
/// the prompt and not on built-in refusals.
class LocalModelCatalog {
  static const models = [
    LocalModelInfo(
      id: 'qwen3-4b-2507-abliterated-q4',
      name: 'Qwen3 4B sin negativas',
      description: 'El más equilibrado: casi el doble de rápido que un 8B y mantiene bien el hilo en escenas largas. No piensa en voz alta, así que todo lo que sale es texto de la novela.',
      url: 'https://huggingface.co/mradermacher/Huihui-Qwen3-4B-Instruct-2507-abliterated-GGUF/resolve/main/Huihui-Qwen3-4B-Instruct-2507-abliterated.Q4_K_M.gguf',
      fileName: 'Huihui-Qwen3-4B-Instruct-2507-abliterated.Q4_K_M.gguf',
      sizeBytes: 2497281312,
      ramGb: 4.0,
    ),
    LocalModelInfo(
      id: 'gemma3-4b-abliterated-q4',
      name: 'Gemma 3 4B sin negativas',
      description: 'Prosa y diálogo muy naturales en español. Pide un teléfono con 8 GB de RAM o más y va despacio.',
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
