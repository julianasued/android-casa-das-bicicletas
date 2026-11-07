/// O modo offline na tela: a faixa que aparece em todas as telas e a ação de
/// ligar e desligar pelo vendedor.
library;

import 'package:flutter/material.dart';

import '../../app/dependencies.dart';
import '../../platform/connectivity/offline_mode.dart';
import 'brand.dart';
import 'feedback.dart';

/// Põe a faixa do modo offline acima de qualquer tela, enquanto ele durar.
///
/// Fica no `builder` do `MaterialApp`, e não em cada página: o vendedor
/// precisa saber em qualquer tela que o que faz agora fica no aparelho.
class FaixaDoModoOffline extends StatelessWidget {
  const FaixaDoModoOffline({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final modo = context.deps.offlineMode;
    if (modo == null) return child;

    return ListenableBuilder(
      listenable: modo,
      builder: (context, _) {
        if (!modo.isOffline) return child;
        return Column(
          children: [
            _Faixa(modo: modo),
            Expanded(
              // A faixa já ocupou a área da barra de status.
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: child,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Faixa extends StatelessWidget {
  const _Faixa({required this.modo});

  final OfflineMode modo;

  @override
  Widget build(BuildContext context) {
    final manual = modo.isManual;
    final texto = manual
        ? 'MODO OFFLINE (ligado por você) — as vendas ficam guardadas no '
            'aparelho até você voltar ao online.'
        : 'MODO OFFLINE — sem conexão com o servidor. As vendas ficam '
            'guardadas no aparelho; o app volta sozinho quando a internet voltar.';

    return Material(
      key: const Key('faixa-modo-offline'),
      color: Marca.amarelo,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          child: Row(
            children: [
              const Icon(Icons.cloud_off, color: Marca.tinta, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  texto,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Marca.tinta,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (modo.isProbing)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 18),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Marca.tinta,
                    ),
                  ),
                )
              else
                TextButton(
                  key: const Key('botao-da-faixa-offline'),
                  style: TextButton.styleFrom(
                    foregroundColor: Marca.tinta,
                    textStyle: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  onPressed: () => manual ? modo.leaveManual() : modo.retryNow(),
                  child: Text(manual ? 'VOLTAR AO ONLINE' : 'TENTAR RECONECTAR'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Liga ou desliga o modo offline pelo vendedor, conforme o estado atual.
///
/// Ligar pergunta antes: a partir dali nada sobe para o servidor, nem quando a
/// internet voltar, até o vendedor desligar — e isso precisa estar claro.
Future<void> alternarModoOffline(BuildContext context) async {
  final modo = context.deps.offlineMode;
  if (modo == null) return;

  if (modo.isManual) {
    final voltou = await modo.leaveManual();
    if (!context.mounted) return;
    showMessage(
      context,
      voltou
          ? 'De volta ao online. As vendas guardadas estão sendo enviadas.'
          : 'Ainda sem conexão com o servidor. O app volta sozinho quando a '
              'internet voltar.',
    );
    return;
  }

  final confirmar = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Usar modo offline?'),
      content: const Text(
        'O app para de tentar o servidor: vendas, PIN e busca usam só o que '
        'está no aparelho, sem espera. As vendas ficam guardadas e só são '
        'enviadas quando você tocar em "Voltar ao online".',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('confirmar-modo-offline'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Usar modo offline'),
        ),
      ],
    ),
  );
  if (confirmar ?? false) await modo.enterManual();
}

/// Item de menu que liga/desliga o modo offline.
class ItemDoModoOffline extends StatelessWidget {
  const ItemDoModoOffline({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final modo = context.deps.offlineMode;
    if (modo == null) return const SizedBox.shrink();

    final manual = modo.isManual;
    return ListTile(
      key: const Key('item-modo-offline'),
      leading: Icon(manual ? Icons.cloud_done : Icons.cloud_off),
      title: Text(manual ? 'Voltar ao online' : 'Usar modo offline'),
      subtitle: Text(
        manual
            ? 'Volta a falar com o servidor e envia as vendas guardadas'
            : 'Para internet instável: vende só pelo aparelho, sem espera',
      ),
      onTap: onTap,
    );
  }
}
