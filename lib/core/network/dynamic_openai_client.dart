import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import '../storage/secure_config_storage.dart';
import 'exceptions/api_exceptions.dart';
import 'models/chat_completion_request.dart';
import 'models/chat_completion_response.dart';

/// Generic client for any server implementing the OpenAI Chat Completions
/// spec (`POST {baseUrl}/chat/completions`). The endpoint, key and model are
/// resolved at call time from [SecureConfigStorage], so switching providers
/// only requires updating Settings — no code changes or app rebuild.
class DynamicOpenAIClient {
  final SecureConfigStorage _configStorage;
  final http.Client _httpClient;
  final Duration timeout;

  /// Waits before each retry of a request that failed before any response
  /// body was read (network error, timeout, 429, 5xx). One entry = one retry.
  final List<Duration> retryDelays;

  DynamicOpenAIClient({
    SecureConfigStorage? configStorage,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 60),
    this.retryDelays = const [Duration(seconds: 1), Duration(seconds: 3)],
  })  : _configStorage = configStorage ?? SecureConfigStorage(),
        _httpClient = httpClient ?? http.Client();

  Future<ApiEndpointConfig> _requireConfig() async {
    final config = await _configStorage.load();
    if (config == null || !config.isComplete) {
      throw const MissingConfigException();
    }
    return config;
  }

  Uri _completionsUri(String baseUrl) {
    final normalized = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$normalized/chat/completions');
  }

  Map<String, String> _headers(String apiKey) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      };

  /// Single-shot completion — waits for the full response body.
  Future<ChatCompletionResponse> send(ChatCompletionRequest request) async {
    final config = await _requireConfig();
    final body = jsonEncode(request.copyWith(stream: false).toJson());

    final response = await _withRetry(() async {
      final response = await _guardNetwork(
        () => _httpClient
            .post(_completionsUri(config.baseUrl), headers: _headers(config.apiKey), body: body)
            .timeout(timeout),
      );
      _throwIfError(response.statusCode, response.body, response.headers);
      return response;
    });

    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return ChatCompletionResponse.fromJson(json);
    } on FormatException {
      throw const MalformedResponseException();
    }
  }

  /// Streaming completion. Emits one [ChatCompletionChunk] per SSE `data:`
  /// event as it arrives, then completes the stream when the server sends
  /// `[DONE]`. Cancel by cancelling the returned stream's subscription.
  Stream<ChatCompletionChunk> stream(ChatCompletionRequest request) async* {
    final config = await _requireConfig();
    final body = jsonEncode(request.copyWith(stream: true).toJson());

    // Retries only cover opening the connection; once the first byte of the
    // body is read, a failure is surfaced so the editor keeps what arrived.
    final response = await _withRetry(() async {
      final streamedRequest = http.Request('POST', _completionsUri(config.baseUrl))
        ..headers.addAll(_headers(config.apiKey))
        ..body = body;
      final response = await _guardNetwork(() => _httpClient.send(streamedRequest).timeout(timeout));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final errorBody = await response.stream.bytesToString();
        _throwIfError(response.statusCode, errorBody, response.headers);
      }
      return response;
    });

    final lines = response.stream.transform(utf8.decoder).transform(const LineSplitter());

    try {
      await for (final rawLine in lines.timeout(timeout)) {
        final line = rawLine.trim();
        if (line.isEmpty || !line.startsWith('data:')) continue;

        final payload = line.substring(5).trim();
        if (payload == '[DONE]') {
          yield ChatCompletionChunk.done();
          return;
        }

        try {
          final json = jsonDecode(payload) as Map<String, dynamic>;
          yield ChatCompletionChunk.fromJson(json);
        } on FormatException {
          // Skip malformed keep-alive/comment lines rather than aborting
          // an otherwise healthy stream.
          continue;
        }
      }
    } on TimeoutException {
      throw const RequestTimeoutException();
    } on SocketException {
      throw const NetworkUnavailableException();
    } on http.ClientException {
      throw const NetworkUnavailableException();
    }
  }

  Future<T> _guardNetwork<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on TimeoutException {
      throw const RequestTimeoutException();
    } on SocketException {
      throw const NetworkUnavailableException();
    } on http.ClientException {
      throw const NetworkUnavailableException();
    }
  }

  Future<T> _withRetry<T>(Future<T> Function() attempt) async {
    for (var i = 0;; i++) {
      try {
        return await attempt();
      } on ApiClientException catch (e) {
        if (i >= retryDelays.length || !_isRetryable(e)) rethrow;
        final serverDelay = e is ServerErrorException ? e.retryAfter : null;
        await Future<void>.delayed(serverDelay ?? retryDelays[i]);
      }
    }
  }

  bool _isRetryable(ApiClientException e) => switch (e) {
        NetworkUnavailableException() || RequestTimeoutException() => true,
        ServerErrorException(:final statusCode) => statusCode == 429 || statusCode >= 500,
        _ => false,
      };

  void _throwIfError(int statusCode, String body, Map<String, String> headers) {
    if (statusCode >= 200 && statusCode < 300) return;

    String? serverMessage;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        serverMessage = error is Map<String, dynamic>
            ? error['message'] as String?
            : error?.toString();
      }
    } catch (_) {
      // Body wasn't JSON; fall back to the raw status code.
    }

    if (statusCode == 401 || statusCode == 403) {
      throw UnauthorizedException(serverMessage: serverMessage);
    }
    throw ServerErrorException(statusCode, serverMessage: serverMessage, retryAfter: _retryAfter(headers));
  }

  /// `Retry-After` in seconds, capped so a bad header can't stall the editor.
  Duration? _retryAfter(Map<String, String> headers) {
    final seconds = int.tryParse(headers['retry-after'] ?? '');
    if (seconds == null || seconds < 0) return null;
    return Duration(seconds: seconds.clamp(0, 10));
  }

  void dispose() => _httpClient.close();
}
