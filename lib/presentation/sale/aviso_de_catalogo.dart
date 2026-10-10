/// Faixa que diz de quando é o catálogo que a tela está mostrando (RF34).
///
/// Aparece **só sem rede**, porque é só aí que o preço vem do cache local: com
/// rede, a busca responde do servidor e não há idade a avisar.
///
/// Recebe data e estado de conexão prontos, em vez de ir buscá-los: é o que
/// permite testar as três situações sem subir banco nem canal de plataforma.
library;

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../domain/rules/cache_do_catalogo.dart';
import '../shared/brand.dart';

class AvisoDeCatalogoEmCache extends StatelessWidget {
  const AvisoDeCatalogoEmCache({
    required this.atualizadoEm,
    required this.online,
    this.agora,
    super.key,
  });

  /// Última vez que o catálogo desta loja foi alimentado; `null` sem catálogo.
  final DateTime? atualizadoEm;
  final bool online;

  /// Referência de "hoje" — injetável para o teste.
  final DateTime? agora;

  @override
  Widget build(BuildContext context) {
    if (online) return const SizedBox.shrink();

    final estado = estadoDoCatalogoLocal(atualizadoEm, agora: agora);
    // Sem catálogo guardado não há idade a comentar, e a lista vazia da busca
    // já explica a situação por si.
    if (estado == EstadoDoCatalogoLocal.ausente) return const SizedBox.shrink();

    final data = formatDate(atualizadoEm!);
    final velho = estado == EstadoDoCatalogoLocal.velho;
    final dias = diasDeCatalogo(atualizadoEm!, agora: agora);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: velho ? const Color(0xFFFFF4D6) : const Color(0xFFF1F3F9),
      child: Row(
        children: [
          Icon(
            velho ? Icons.warning_amber_rounded : Icons.cloud_off,
            size: 18,
            color: velho ? const Color(0xFF7A5B00) : Marca.azul,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              velho
                  ? 'Catálogo de $data — $dias dias sem atualizar. '
                      'Confira o preço antes de fechar.'
                  : 'Sem rede: catálogo de $data.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: velho ? FontWeight.w700 : FontWeight.w600,
                color: velho ? const Color(0xFF7A5B00) : Marca.azul,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
