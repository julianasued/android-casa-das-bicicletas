/// Configuração de ambiente do terminal.
///
/// A URL da API, a loja e o identificador do dispositivo não são constantes de
/// código: o mesmo APK é instalado nos terminais das duas lojas, e cada
/// aparelho tem seu `X-Device-Id` cadastrado no backend (`Terminal.
/// device_identifier`). O valor padrão vem de `--dart-define` na compilação e
/// pode ser ajustado na tela de configuração do terminal, que grava no
/// armazenamento seguro.
library;

class AppEnvironment {
  const AppEnvironment({
    required this.apiBaseUrl,
    required this.requestTimeout,
    required this.allowInsecureHttp,
  });

  /// Valores de compilação: `flutter build apk --dart-define=API_BASE_URL=...`.
  factory AppEnvironment.fromDefines() {
    const url = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://api.dominio.com.br/api/v1/',
    );
    const timeoutSeconds = int.fromEnvironment('API_TIMEOUT_SECONDS', defaultValue: 20);
    // RNF01 — HTTPS é obrigatório; a exceção existe só para o emulador apontando
    // para o Django local, e precisa ser pedida explicitamente na compilação.
    const insecure = bool.fromEnvironment('ALLOW_INSECURE_HTTP');

    return AppEnvironment(
      apiBaseUrl: url,
      requestTimeout: Duration(seconds: timeoutSeconds),
      allowInsecureHttp: insecure,
    );
  }

  final String apiBaseUrl;
  final Duration requestTimeout;
  final bool allowInsecureHttp;

  AppEnvironment copyWith({String? apiBaseUrl}) => AppEnvironment(
        apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
        requestTimeout: requestTimeout,
        allowInsecureHttp: allowInsecureHttp,
      );

  /// `true` quando a URL viola a RNF01 e a compilação não liberou exceção.
  bool violatesTransportSecurity(String url) =>
      !allowInsecureHttp && !url.toLowerCase().startsWith('https://');
}
