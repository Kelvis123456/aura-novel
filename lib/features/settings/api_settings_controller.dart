import 'package:flutter/foundation.dart';

import '../../core/network/dynamic_openai_client.dart';
import '../../core/network/exceptions/api_exceptions.dart';
import '../../core/network/models/chat_completion_request.dart';
import '../../core/network/models/chat_message.dart';
import '../../core/storage/secure_config_storage.dart';

/// Result of the last "Probar Conexión" attempt, driving the status badge.
enum ConnectionStatus {
  unconfigured,
  savedUntested,
  testing,
  connected,
  unauthorized,
  timeout,
  networkError,
  serverError,
  invalidForm,
}

extension ConnectionStatusLabel on ConnectionStatus {
  String get label => switch (this) {
        ConnectionStatus.unconfigured => 'Sin configurar',
        ConnectionStatus.savedUntested => 'Guardado (sin probar)',
        ConnectionStatus.testing => 'Probando…',
        ConnectionStatus.connected => 'Conectado',
        ConnectionStatus.unauthorized => 'Error de autenticación (401)',
        ConnectionStatus.timeout => 'Timeout',
        ConnectionStatus.networkError => 'Error de red',
        ConnectionStatus.serverError => 'Error del servidor',
        ConnectionStatus.invalidForm => 'Revisa los campos',
      };
}

/// Per-field validation errors, keyed by field name. Empty map == valid.
class ApiSettingsFormErrors {
  final Map<String, String> byField;
  const ApiSettingsFormErrors(this.byField);
  const ApiSettingsFormErrors.empty() : byField = const {};

  String? operator [](String field) => byField[field];
  bool get isValid => byField.isEmpty;
}

/// Business logic for [ApiSettingsScreen]: loads/saves the endpoint config
/// via [SecureConfigStorage] and drives connection tests through
/// [DynamicOpenAIClient]. Extends [ChangeNotifier] so the screen can rebuild
/// with `ListenableBuilder` / `AnimatedBuilder` without pulling in a state
/// management package — swap for Riverpod/BLoC by re-wrapping this same
/// logic if the rest of the app already standardizes on one.
class ApiSettingsController extends ChangeNotifier {
  final SecureConfigStorage _storage;
  final DynamicOpenAIClient _client;

  ApiSettingsController({
    SecureConfigStorage? storage,
    DynamicOpenAIClient? client,
  })  : _storage = storage ?? SecureConfigStorage(),
        _client = client ?? DynamicOpenAIClient();

  bool isLoading = true;
  bool isSaving = false;
  bool obscureApiKey = true;

  String baseUrl = '';
  String apiKey = '';
  String modelId = '';
  double temperature = 0.9;
  int maxTokens = 800;
  double frequencyPenalty = 0.3;
  double presencePenalty = 0.2;

  ConnectionStatus status = ConnectionStatus.unconfigured;
  String? statusDetail;
  ApiSettingsFormErrors formErrors = const ApiSettingsFormErrors.empty();

  Future<void> load() async {
    isLoading = true;
    notifyListeners();

    final config = await _storage.load();
    if (config != null) {
      baseUrl = config.baseUrl;
      apiKey = config.apiKey;
      modelId = config.modelId;
      temperature = config.temperature;
      maxTokens = config.maxTokens;
      frequencyPenalty = config.frequencyPenalty;
      presencePenalty = config.presencePenalty;
      status = ConnectionStatus.savedUntested;
    } else {
      // First run: pre-fill with Google's Gemini free tier (via its
      // OpenAI-compatible endpoint) so the user only has to paste their
      // API key — unlike OpenRouter's rotating ":free" catalog, this tier
      // is stable and doesn't depend on a local machine staying online.
      // Key: aistudio.google.com/apikey (free).
      baseUrl = 'https://generativelanguage.googleapis.com/v1beta/openai';
      modelId = 'gemini-2.0-flash';
      status = ConnectionStatus.unconfigured;
    }

    isLoading = false;
    notifyListeners();
  }

  void toggleApiKeyVisibility() {
    obscureApiKey = !obscureApiKey;
    notifyListeners();
  }

  void updateBaseUrl(String value) {
    baseUrl = value;
    notifyListeners();
  }

  void updateApiKey(String value) {
    apiKey = value;
    notifyListeners();
  }

  void updateModelId(String value) {
    modelId = value;
    notifyListeners();
  }

  void updateTemperature(double value) {
    temperature = value;
    notifyListeners();
  }

  void updateMaxTokens(int value) {
    maxTokens = value;
    notifyListeners();
  }

  void updateFrequencyPenalty(double value) {
    frequencyPenalty = value;
    notifyListeners();
  }

  void updatePresencePenalty(double value) {
    presencePenalty = value;
    notifyListeners();
  }

  ApiSettingsFormErrors _validate() {
    final errors = <String, String>{};

    final trimmedUrl = baseUrl.trim();
    final uri = Uri.tryParse(trimmedUrl);
    if (trimmedUrl.isEmpty) {
      errors['baseUrl'] = 'La Base URL es obligatoria.';
    } else if (uri == null || !uri.isAbsolute || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      errors['baseUrl'] = 'Debe ser una URL absoluta (http:// o https://).';
    }

    if (apiKey.trim().isEmpty) {
      errors['apiKey'] = 'La API Key es obligatoria.';
    }

    if (modelId.trim().isEmpty) {
      errors['modelId'] = 'El Model ID es obligatorio.';
    }

    return ApiSettingsFormErrors(errors);
  }

  ApiEndpointConfig _currentConfig() => ApiEndpointConfig(
        baseUrl: baseUrl.trim(),
        apiKey: apiKey.trim(),
        modelId: modelId.trim(),
        temperature: temperature,
        maxTokens: maxTokens,
        frequencyPenalty: frequencyPenalty,
        presencePenalty: presencePenalty,
      );

  /// Returns true on success. On failure, [formErrors] is populated and the
  /// screen should surface it inline instead of via SnackBar.
  Future<bool> save() async {
    formErrors = _validate();
    if (!formErrors.isValid) {
      status = ConnectionStatus.invalidForm;
      notifyListeners();
      return false;
    }

    isSaving = true;
    notifyListeners();

    await _storage.save(_currentConfig());

    isSaving = false;
    status = ConnectionStatus.savedUntested;
    statusDetail = null;
    notifyListeners();
    return true;
  }

  /// Persists the current form, then fires a minimal completion request to
  /// confirm the endpoint/key/model actually work together.
  Future<void> testConnection() async {
    formErrors = _validate();
    if (!formErrors.isValid) {
      status = ConnectionStatus.invalidForm;
      notifyListeners();
      return;
    }

    await _storage.save(_currentConfig());

    status = ConnectionStatus.testing;
    statusDetail = null;
    notifyListeners();

    try {
      final response = await _client.send(
        ChatCompletionRequest(
          model: modelId.trim(),
          messages: [
            ChatMessage.user('Responde solo con "ok" para confirmar la conexión.'),
          ],
          temperature: 0,
          maxTokens: 10,
        ),
      );
      status = ConnectionStatus.connected;
      statusDetail = response.content.trim().isEmpty
          ? 'El servidor respondió sin contenido; revisa el Model ID.'
          : null;
    } on MissingConfigException {
      status = ConnectionStatus.unconfigured;
    } on UnauthorizedException catch (e) {
      status = ConnectionStatus.unauthorized;
      statusDetail = e.message;
    } on RequestTimeoutException catch (e) {
      status = ConnectionStatus.timeout;
      statusDetail = e.message;
    } on NetworkUnavailableException catch (e) {
      status = ConnectionStatus.networkError;
      statusDetail = e.message;
    } on ServerErrorException catch (e) {
      status = ConnectionStatus.serverError;
      statusDetail = e.message;
    } on ApiClientException catch (e) {
      status = ConnectionStatus.serverError;
      statusDetail = e.message;
    } finally {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _client.dispose();
    super.dispose();
  }
}
