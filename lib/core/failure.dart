/// Falhas que o aplicativo sabe nomear.
///
/// A lista não é genérica: ela cobre exatamente o que a especificação de
/// integração com o M10 Pro manda tratar (§11) e a tabela de erros da API
/// (§1.4). Cada caso tem um texto próprio porque o operador do balcão precisa
/// saber o que fazer — "erro" sozinho manda ele ligar para alguém.
library;

sealed class Failure {
  const Failure(this.message, {this.details});

  /// Texto pronto para a tela, em português e sem jargão de rede.
  final String message;

  /// Campo → erro, quando o servidor devolve validação por campo (§1.4).
  final Map<String, Object?>? details;

  @override
  String toString() => '$runtimeType: $message';
}

// ---------------------------------------------------------------------------
// Comunicação com a API (§1.4 e §11 — "API indisponível")
// ---------------------------------------------------------------------------

/// Não houve resposta: sem rede, DNS, timeout, servidor fora.
class NetworkFailure extends Failure {
  const NetworkFailure([
    super.message = 'Sem conexão com o servidor. A operação não foi enviada.',
  ]);
}

/// Resposta veio, mas com erro de negócio ou de validação.
class ApiFailure extends Failure {
  const ApiFailure({
    required this.code,
    required String message,
    required this.statusCode,
    Map<String, Object?>? details,
  }) : super(message, details: details);

  /// Código estável da tabela §1.4 (`VALIDATION_ERROR`, `CONFLICT`, ...).
  final String code;
  final int statusCode;

  bool get isValidation => code == 'VALIDATION_ERROR';
  bool get isConflict => statusCode == 409;
  bool get isInvalidTransition => code == 'INVALID_STATE_TRANSITION';
}

/// 401 — token ausente ou expirado. Leva de volta à tela de login do terminal.
class UnauthenticatedFailure extends Failure {
  const UnauthenticatedFailure([
    super.message = 'Sessão expirada. Autentique o terminal novamente.',
  ]);
}

/// 403 — perfil sem permissão (RF02/RNF02). "Terminal não autorizado" (§11).
class PermissionFailure extends Failure {
  const PermissionFailure([
    super.message = 'Operação não permitida para este perfil.',
  ]);
}

/// 404 — "venda inexistente" (§11) e afins.
class NotFoundFailure extends Failure {
  const NotFoundFailure([super.message = 'Registro não encontrado.']);
}

// ---------------------------------------------------------------------------
// Hardware do terminal (§11 da integração com o M10 Pro)
// ---------------------------------------------------------------------------

/// A impressora não respondeu, está fora ou o SDK não está no dispositivo.
class PrinterUnavailableFailure extends Failure {
  const PrinterUnavailableFailure([
    super.message = 'Impressora indisponível neste terminal.',
  ]);
}

/// Falta de papel — o caso mais comum do balcão, e o único com solução na hora.
class OutOfPaperFailure extends Failure {
  const OutOfPaperFailure([
    super.message = 'Sem papel. Reponha a bobina e reimprima o documento.',
  ]);
}

/// A impressora aceitou o comando e falhou no meio.
class PrintFailure extends Failure {
  const PrintFailure([
    super.message = 'Falha ao imprimir. Confira a impressora e reimprima.',
  ]);
}

/// O leitor não pôde ser iniciado ou devolveu leitura inválida.
class ScannerFailure extends Failure {
  const ScannerFailure([
    super.message = 'Falha na leitura do código de barras.',
  ]);
}

/// Falha ao ler/gravar no armazenamento seguro do terminal.
class SecureStoreFailure extends Failure {
  const SecureStoreFailure([
    super.message = 'Falha ao acessar o armazenamento seguro do terminal.',
  ]);
}

/// Estado local impede a operação: terminal sem configuração, sessão ausente.
class ConfigurationFailure extends Failure {
  const ConfigurationFailure(super.message);
}

/// Regra de negócio violada antes de chegar ao servidor (13.3, RF14).
class BusinessRuleFailure extends Failure {
  const BusinessRuleFailure(super.message);
}

/// O que não se previu. Existe para não engolir erro em silêncio.
class UnexpectedFailure extends Failure {
  const UnexpectedFailure(super.message, {this.cause});

  final Object? cause;
}
