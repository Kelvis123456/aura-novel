/// Base type for every error this network layer can throw.
sealed class ApiClientException implements Exception {
  final String message;
  const ApiClientException(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// No `baseUrl` / `apiKey` / `modelId` configured yet.
class MissingConfigException extends ApiClientException {
  const MissingConfigException([
    super.message = 'Falta conectar un modelo. Configúralo en Ajustes de API (la rueda del editor).',
  ]);
}

/// DNS/socket failure, connection refused, no connectivity, etc.
class NetworkUnavailableException extends ApiClientException {
  const NetworkUnavailableException([
    super.message = 'No se pudo llegar al servidor. Revisa tu conexión y la URL del endpoint.',
  ]);
}

/// Request exceeded the configured timeout.
class RequestTimeoutException extends ApiClientException {
  const RequestTimeoutException([
    super.message = 'El servidor tardó demasiado en responder.',
  ]);
}

/// Server responded with a non-2xx status code.
class ServerErrorException extends ApiClientException {
  final int statusCode;
  final String? serverMessage;

  /// Server-requested wait before retrying (`Retry-After`), if it sent one.
  final Duration? retryAfter;

  ServerErrorException(this.statusCode, {this.serverMessage, this.retryAfter})
      : super(
          serverMessage != null && serverMessage.isNotEmpty
              ? 'Error del servidor ($statusCode): $serverMessage'
              : 'Error del servidor ($statusCode)',
        );
}

/// 401/403 — bad or missing API key.
class UnauthorizedException extends ServerErrorException {
  UnauthorizedException({String? serverMessage}) : super(401, serverMessage: serverMessage);
}

/// Response body could not be parsed as expected JSON / SSE.
class MalformedResponseException extends ApiClientException {
  const MalformedResponseException([
    super.message = 'El servidor devolvió una respuesta que la app no entiende.',
  ]);
}

/// Caller cancelled an in-flight streaming request.
class RequestCancelledException extends ApiClientException {
  const RequestCancelledException([super.message = 'Se canceló la petición.']);
}
