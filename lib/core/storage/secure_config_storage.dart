import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Immutable snapshot of the user-configured API endpoint and their default
/// generation parameters.
class ApiEndpointConfig {
  final String baseUrl;
  final String apiKey;
  final String modelId;
  final double temperature;
  final int maxTokens;
  final double frequencyPenalty;
  final double presencePenalty;

  /// Character budget for the lore block and, separately, for the earlier-
  /// chapter recaps sent with each generation (about 4 characters per token).
  /// Small models need it low; large-window ones can take much more.
  final int contextChars;

  /// Model used for research notes. Empty means the writing model. A model with
  /// web search (a Perplexity or OpenRouter online model) makes the notes better.
  final String researchModelId;

  /// `remote` (an OpenAI-compatible server) or `local` (a model inside the phone).
  final String provider;

  /// Id of the downloaded model to use when [provider] is `local`.
  final String localModelId;

  static const defaultContextChars = 3000;

  const ApiEndpointConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.modelId,
    this.temperature = 0.9,
    this.maxTokens = 4096,
    this.frequencyPenalty = 0.3,
    this.presencePenalty = 0.2,
    this.contextChars = defaultContextChars,
    this.researchModelId = '',
    this.provider = 'remote',
    this.localModelId = '',
  });

  bool get isLocal => provider == 'local';

  bool get isComplete => isLocal
      ? localModelId.trim().isNotEmpty
      : baseUrl.trim().isNotEmpty && apiKey.trim().isNotEmpty && modelId.trim().isNotEmpty;

  ApiEndpointConfig copyWith({
    String? baseUrl,
    String? apiKey,
    String? modelId,
    double? temperature,
    int? maxTokens,
    double? frequencyPenalty,
    double? presencePenalty,
    int? contextChars,
    String? researchModelId,
    String? provider,
    String? localModelId,
  }) {
    return ApiEndpointConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      modelId: modelId ?? this.modelId,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      frequencyPenalty: frequencyPenalty ?? this.frequencyPenalty,
      presencePenalty: presencePenalty ?? this.presencePenalty,
      contextChars: contextChars ?? this.contextChars,
      researchModelId: researchModelId ?? this.researchModelId,
      provider: provider ?? this.provider,
      localModelId: localModelId ?? this.localModelId,
    );
  }
}

/// Persists the user's custom endpoint (baseUrl, apiKey, modelId) using the
/// platform Keychain (iOS/macOS) or Keystore-backed EncryptedSharedPreferences
/// (Android) via `flutter_secure_storage`. All three values live behind the
/// same OS-level encryption — the key is the most sensitive, but baseUrl and
/// modelId are treated as sensitive too since they can reveal a private
/// self-hosted endpoint.
class SecureConfigStorage {
  static const _keyBaseUrl = 'aura.api.base_url';
  static const _keyApiKey = 'aura.api.key';
  static const _keyModelId = 'aura.api.model_id';
  static const _keyTemperature = 'aura.api.temperature';
  static const _keyMaxTokens = 'aura.api.max_tokens';
  static const _keyFrequencyPenalty = 'aura.api.frequency_penalty';
  static const _keyPresencePenalty = 'aura.api.presence_penalty';
  static const _keyContextChars = 'aura.api.context_chars';
  static const _keyResearchModel = 'aura.api.research_model';
  static const _keyProvider = 'aura.api.provider';
  static const _keyLocalModel = 'aura.api.local_model';

  final FlutterSecureStorage _storage;

  SecureConfigStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  Future<void> save(ApiEndpointConfig config) async {
    await Future.wait([
      _storage.write(key: _keyBaseUrl, value: config.baseUrl.trim()),
      _storage.write(key: _keyApiKey, value: config.apiKey.trim()),
      _storage.write(key: _keyModelId, value: config.modelId.trim()),
      _storage.write(key: _keyTemperature, value: config.temperature.toString()),
      _storage.write(key: _keyMaxTokens, value: config.maxTokens.toString()),
      _storage.write(key: _keyFrequencyPenalty, value: config.frequencyPenalty.toString()),
      _storage.write(key: _keyPresencePenalty, value: config.presencePenalty.toString()),
      _storage.write(key: _keyContextChars, value: config.contextChars.toString()),
      _storage.write(key: _keyResearchModel, value: config.researchModelId.trim()),
      _storage.write(key: _keyProvider, value: config.provider),
      _storage.write(key: _keyLocalModel, value: config.localModelId.trim()),
    ]);
  }

  Future<ApiEndpointConfig?> load() async {
    final values = await Future.wait([
      _storage.read(key: _keyBaseUrl),
      _storage.read(key: _keyApiKey),
      _storage.read(key: _keyModelId),
      _storage.read(key: _keyTemperature),
      _storage.read(key: _keyMaxTokens),
      _storage.read(key: _keyFrequencyPenalty),
      _storage.read(key: _keyPresencePenalty),
      _storage.read(key: _keyContextChars),
      _storage.read(key: _keyResearchModel),
      _storage.read(key: _keyProvider),
      _storage.read(key: _keyLocalModel),
    ]);

    final baseUrl = values[0];
    final apiKey = values[1];
    final modelId = values[2];

    final provider = values[9] == 'local' ? 'local' : 'remote';
    final localModelId = values[10] ?? '';
    // A local setup needs no server fields: an install that only chose a local model still has a config.
    if (provider == 'remote' && (baseUrl == null || apiKey == null || modelId == null)) return null;
    if (provider == 'local' && localModelId.isEmpty) return null;

    return ApiEndpointConfig(
      baseUrl: baseUrl ?? '',
      apiKey: apiKey ?? '',
      modelId: modelId ?? '',
      temperature: double.tryParse(values[3] ?? '') ?? 0.9,
      // 800 was the old default, too short for scenes of prose: installs that saved it get the new one.
      maxTokens: _migratedMaxTokens(int.tryParse(values[4] ?? '')),
      frequencyPenalty: double.tryParse(values[5] ?? '') ?? 0.3,
      presencePenalty: double.tryParse(values[6] ?? '') ?? 0.2,
      // Installs that saved their config before this setting existed have no value.
      contextChars: int.tryParse(values[7] ?? '') ?? ApiEndpointConfig.defaultContextChars,
      researchModelId: values[8] ?? '',
      provider: provider,
      localModelId: localModelId,
    );
  }

  static int _migratedMaxTokens(int? stored) => (stored == null || stored == 800) ? 4096 : stored;

  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _keyBaseUrl),
      _storage.delete(key: _keyApiKey),
      _storage.delete(key: _keyModelId),
      _storage.delete(key: _keyTemperature),
      _storage.delete(key: _keyMaxTokens),
      _storage.delete(key: _keyFrequencyPenalty),
      _storage.delete(key: _keyPresencePenalty),
      _storage.delete(key: _keyContextChars),
      _storage.delete(key: _keyResearchModel),
      _storage.delete(key: _keyProvider),
      _storage.delete(key: _keyLocalModel),
    ]);
  }
}
