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

  static const defaultContextChars = 3000;

  const ApiEndpointConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.modelId,
    this.temperature = 0.9,
    this.maxTokens = 800,
    this.frequencyPenalty = 0.3,
    this.presencePenalty = 0.2,
    this.contextChars = defaultContextChars,
  });

  bool get isComplete =>
      baseUrl.trim().isNotEmpty && apiKey.trim().isNotEmpty && modelId.trim().isNotEmpty;

  ApiEndpointConfig copyWith({
    String? baseUrl,
    String? apiKey,
    String? modelId,
    double? temperature,
    int? maxTokens,
    double? frequencyPenalty,
    double? presencePenalty,
    int? contextChars,
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
    ]);

    final baseUrl = values[0];
    final apiKey = values[1];
    final modelId = values[2];

    if (baseUrl == null || apiKey == null || modelId == null) return null;

    return ApiEndpointConfig(
      baseUrl: baseUrl,
      apiKey: apiKey,
      modelId: modelId,
      temperature: double.tryParse(values[3] ?? '') ?? 0.9,
      maxTokens: int.tryParse(values[4] ?? '') ?? 800,
      frequencyPenalty: double.tryParse(values[5] ?? '') ?? 0.3,
      presencePenalty: double.tryParse(values[6] ?? '') ?? 0.2,
      // Installs that saved their config before this setting existed have no value.
      contextChars: int.tryParse(values[7] ?? '') ?? ApiEndpointConfig.defaultContextChars,
    );
  }

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
    ]);
  }
}
