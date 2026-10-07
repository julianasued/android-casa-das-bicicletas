/// Armazenamento seguro do terminal (bloco PLATAFORMA do diagrama).
///
/// Guarda o token do terminal, o da sessão do vendedor e a configuração do
/// aparelho. Não é preferência de usuário: um token de terminal em texto claro
/// permite a qualquer aplicativo do aparelho vender no nome da loja, e o M10
/// fica no balcão, ao alcance de quem passa.
///
/// A interface é declarada aqui, na camada de dados, e implementada pelo canal
/// nativo — assim o repositório não conhece `MethodChannel` nenhum.
abstract interface class SecureStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);

  Future<void> clear();
}

/// Implementação em memória — usada nos testes e como reserva quando o canal
/// nativo não está disponível (aplicativo rodando fora do terminal).
class InMemorySecureStore implements SecureStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<void> clear() async => _values.clear();
}
