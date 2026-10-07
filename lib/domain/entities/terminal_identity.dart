/// O que o terminal sabe sobre si e sobre a loja.
///
/// Mora no domínio porque é o documento que depende dela, não o banco: quem
/// guarda é o cache, mas quem precisa é a regra que monta o cupom sem rede.
library;

/// Aprendido, e não configurado: vem do documento que o servidor já mandou ou
/// da rota da loja. Nada aqui é digitado pelo operador.
class TerminalIdentity {
  const TerminalIdentity({
    this.storeCode,
    this.storeName,
    this.storeDocument,
    this.storeAddress,
    this.terminalName,
    required this.learnedAt,
  });

  final String? storeCode;
  final String? storeName;
  final String? storeDocument;
  final String? storeAddress;
  final String? terminalName;
  final DateTime learnedAt;

  /// Dá para montar um documento com isto?
  ///
  /// O nome da loja é o mínimo: um cupom sem ele não identifica quem vendeu.
  /// Endereço e CNPJ saem em branco sem impedir a venda — o papel serve para
  /// retirada, e o §13.9 manda imprimir offline.
  bool get canPrintOffline => (storeName ?? '').isNotEmpty;
}
