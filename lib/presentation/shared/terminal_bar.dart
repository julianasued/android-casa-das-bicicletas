/// Faixa de identificação do terminal.
///
/// Mostra, o tempo todo, três coisas que decidem se a operação está certa:
/// quem está vendendo, em que loja, e se há rede. O vendedor é o responsável
/// pela venda (RF06) e o M10 é compartilhado — descobrir no fim do dia que as
/// vendas saíram no nome de quem usou o aparelho antes é o erro que esta faixa
/// existe para evitar.
library;

import 'package:flutter/material.dart';

import '../../data/session/session_manager.dart';
import '../../platform/connectivity/connectivity_channel.dart';

class TerminalBar extends StatelessWidget {
  const TerminalBar({
    required this.session,
    required this.connectivity,
    this.onChangeSeller,
    super.key,
  });

  final SessionManager session;
  final ConnectivityChannel connectivity;
  final VoidCallback? onChangeSeller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: Listenable.merge([session, connectivity]),
      builder: (context, _) {
        final seller = session.seller;
        final online = connectivity.isOnline;

        return Material(
          color: scheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(online ? Icons.cloud_done : Icons.cloud_off,
                    size: 20, color: online ? scheme.primary : scheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        seller?.name ?? 'Nenhum vendedor selecionado',
                        style: Theme.of(context).textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _subtitle(session, online),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (onChangeSeller != null)
                  TextButton(
                    onPressed: onChangeSeller,
                    child: const Text('Trocar'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _subtitle(SessionManager session, bool online) {
    final store = session.storeCode ?? 'Loja ${session.storeId ?? '?'}';
    final rede = online ? 'conectado' : 'sem rede';
    return '$store · $rede';
  }
}
