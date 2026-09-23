/// Confirmação de quem é o responsável, antes de começar a venda.
///
/// A sessão do vendedor dura o expediente inteiro, e a venda é atribuída a
/// quem estiver nela. Basta alguém sair do balcão sem trocar para a venda
/// seguinte — e a comissão dela (RF17) — sair no nome errado, e o conserto
/// depois é alteração de venda aprovada por gerente.
///
/// É uma pergunta, não uma etapa: um toque no botão grande segue em frente, e
/// a senha do terminal não volta a ser pedida.
library;

import 'package:flutter/material.dart';

import 'brand.dart';

/// O que se respondeu na confirmação.
enum ConfirmacaoDoVendedor {
  /// É esta pessoa — abrir a venda.
  confirmado,

  /// É outra — abrir a seleção de vendedor que já existe.
  trocar,
}

/// Pergunta se `vendedor` é quem vai realizar a venda.
///
/// Devolve `null` quando se desiste (toque fora do cartão): aí nada acontece,
/// nem venda nem troca, e a tela de origem continua como estava.
Future<ConfirmacaoDoVendedor?> confirmarVendedor(
  BuildContext context, {
  required String vendedor,
}) {
  return showDialog<ConfirmacaoDoVendedor>(
    context: context,
    builder: (context) => _CartaoDaConfirmacao(vendedor: vendedor),
  );
}

class _CartaoDaConfirmacao extends StatelessWidget {
  const _CartaoDaConfirmacao({required this.vendedor});

  final String vendedor;

  @override
  Widget build(BuildContext context) {
    final compacto = MediaQuery.sizeOf(context).width < 600;

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compacto ? 20 : 30,
            compacto ? 22 : 28,
            compacto ? 20 : 30,
            compacto ? 18 : 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'VENDEDOR',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.8,
                  color: Marca.tintaFraca,
                ),
              ),
              const SizedBox(height: 4),
              // O nome é o que se lê antes de decidir, então é o que domina.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  vendedor.toUpperCase(),
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: compacto ? 30 : 36,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    color: Marca.tinta,
                  ),
                ),
              ),
              SizedBox(height: compacto ? 12 : 16),
              Text(
                'É você quem vai realizar esta venda?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: compacto ? 16 : 18,
                  fontWeight: FontWeight.w600,
                  color: Marca.tintaFraca,
                ),
              ),
              SizedBox(height: compacto ? 18 : 24),
              // O sim é o caminho de quase toda venda: botão grande, cor da
              // ação, primeiro na ordem do polegar.
              SizedBox(
                height: 64,
                child: FilledButton(
                  onPressed: () => Navigator.of(context)
                      .pop(ConfirmacaoDoVendedor.confirmado),
                  style: FilledButton.styleFrom(
                    backgroundColor: Marca.laranja,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'SIM, CONTINUAR',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .6,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 56,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pop(ConfirmacaoDoVendedor.trocar),
                  icon: const Icon(Icons.switch_account,
                      size: 22, color: Marca.azul),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 56),
                    foregroundColor: Marca.azul,
                    side: const BorderSide(color: Marca.bordaCampo, width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'TROCAR VENDEDOR',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .4,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
