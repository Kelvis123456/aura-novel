import 'package:aura_novel/core/storage/secure_config_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const base = {
    'aura.api.base_url': 'https://api.test',
    'aura.api.key': 'k',
    'aura.api.model_id': 'm',
  };

  test('guarda y lee el tope de contexto', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final storage = SecureConfigStorage();

    await storage.save(
      const ApiEndpointConfig(baseUrl: 'https://api.test', apiKey: 'k', modelId: 'm', contextChars: 9000),
    );

    expect((await storage.load())!.contextChars, 9000);
  });

  test('una config guardada antes de este ajuste usa el valor por defecto', () async {
    FlutterSecureStorage.setMockInitialValues(base);

    expect((await SecureConfigStorage().load())!.contextChars, ApiEndpointConfig.defaultContextChars);
  });

  test('un valor corrupto también cae al valor por defecto', () async {
    FlutterSecureStorage.setMockInitialValues({...base, 'aura.api.context_chars': 'abc'});

    expect((await SecureConfigStorage().load())!.contextChars, ApiEndpointConfig.defaultContextChars);
  });
}
