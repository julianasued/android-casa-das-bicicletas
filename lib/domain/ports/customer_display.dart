/// Porta do display do cliente — a segunda tela de 2,4" do M10.
///
/// A abstração existe **antes** da implementação de propósito. A documentação
/// oficial da Elgin não publica módulo algum para este display: a lista de
/// módulos tem impressora, scanner (só do SmartPOS), SAT, balança, TEF, Pix e
/// etiqueta. Há um `display-v02.00.00-release.aar` no repositório oficial de
/// exemplos, sem exemplo de uso e sem API descrita.
///
/// Declarar a porta agora custa pouco e resolve duas coisas: o resto do
/// aplicativo já pode ser escrito contra ela (com `FakeCustomerDisplay`), e no
/// dia em que a API aparecer só a implementação muda. O que **não** se faz é
/// inventar comandos para preencher o vazio.
library;

import '../../core/result.dart';

/// O que o aparelho responde sobre a existência do display.
class CustomerDisplayStatus {
  const CustomerDisplayStatus({
    required this.available,
    required this.hasSecondaryDisplay,
    this.detail = '',
    this.secondaryDisplays = const <String>[],
  });

  const CustomerDisplayStatus.unavailable(this.detail)
      : available = false,
        hasSecondaryDisplay = false,
        secondaryDisplays = const <String>[];

  /// Existe caminho **implementado** para escrever no display.
  final bool available;

  /// O Android enxerga uma tela secundária neste aparelho.
  ///
  /// É a pergunta que decide o caminho: se enxerga, dá para usar `Presentation`
  /// do próprio Android; se não, o controle é proprietário e depende do SDK da
  /// Elgin.
  final bool hasSecondaryDisplay;

  /// Nome e id de cada tela secundária, para diagnóstico no aparelho.
  final List<String> secondaryDisplays;

  final String detail;
}

abstract interface class CustomerDisplay {
  /// Levanta o que o aparelho responde. Não escreve nada.
  Future<Result<CustomerDisplayStatus>> probe();

  /// Mostra linhas de texto ao cliente.
  Future<Result<void>> show(List<String> lines);

  /// Limpa o display.
  Future<Result<void>> clear();
}

/// Display de mentira, para o aplicativo e o POC rodarem fora do M10.
class FakeCustomerDisplay implements CustomerDisplay {
  final List<List<String>> shown = <List<String>>[];
  bool cleared = false;

  @override
  Future<Result<CustomerDisplayStatus>> probe() async => const Ok(
        CustomerDisplayStatus(
          available: true,
          hasSecondaryDisplay: false,
          detail: 'Display simulado (fora do terminal).',
        ),
      );

  @override
  Future<Result<void>> show(List<String> lines) async {
    shown.add(lines);
    return const Ok(null);
  }

  @override
  Future<Result<void>> clear() async {
    cleared = true;
    return const Ok(null);
  }
}
