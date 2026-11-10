/// Motivo e confirmação do cancelamento da venda (09/11/2026).
///
/// O vendedor cancela a própria venda no M10, sem PIN, enquanto ela aguarda o
/// caixa. O motivo é obrigatório — é o que fica na venda e na auditoria —, e
/// por isso os dois mais comuns já vêm prontos, num toque; o resto se digita.
library;

import 'package:flutter/material.dart';

import '../../domain/entities/sale.dart';
import '../shared/brand.dart';

/// Os motivos de um toque. O último abre o campo para escrever.
const motivosProntos = ['Cliente desistiu', 'Venda errada'];
const outroMotivo = 'Outro motivo';

/// Pergunta o motivo e confirma. Devolve o motivo, ou `null` se desistiu.
Future<String?> pedirMotivoDoCancelamento(
  BuildContext context, {
  required Sale sale,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _CancelarVendaDialog(sale: sale),
  );
}

class _CancelarVendaDialog extends StatefulWidget {
  const _CancelarVendaDialog({required this.sale});

  final Sale sale;

  @override
  State<_CancelarVendaDialog> createState() => _CancelarVendaDialogState();
}

class _CancelarVendaDialogState extends State<_CancelarVendaDialog> {
  String? _escolhido;
  final _outro = TextEditingController();

  @override
  void dispose() {
    _outro.dispose();
    super.dispose();
  }

  /// O que vai para o servidor; `null` enquanto não há motivo que sirva.
  String? get _motivo {
    if (_escolhido == null) return null;
    if (_escolhido != outroMotivo) return _escolhido;
    final digitado = _outro.text.trim();
    // O servidor pede ao menos 3 letras: recusar aqui poupa a ida e volta.
    return digitado.length >= 3 ? digitado : null;
  }

  @override
  Widget build(BuildContext context) {
    final compacto = MediaQuery.sizeOf(context).width < 600;
    final motivo = _motivo;

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
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
                'CANCELAR A VENDA?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Marca.vermelhoTexto,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${widget.sale.barcode} · '
                '${widget.sale.totalAmount.toDisplayString()}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Marca.tinta,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Recolha o papel do cliente: depois de cancelada, a venda '
                'não é mais recebida no caixa.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Marca.tintaFraca),
              ),
              const SizedBox(height: 18),
              const Text(
                'MOTIVO',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                  color: Marca.tintaFraca,
                ),
              ),
              const SizedBox(height: 8),
              for (final opcao in [...motivosProntos, outroMotivo]) ...[
                _OpcaoDeMotivo(
                  key: Key('motivo-$opcao'),
                  texto: opcao,
                  escolhido: _escolhido == opcao,
                  onTap: () => setState(() => _escolhido = opcao),
                ),
                const SizedBox(height: 8),
              ],
              if (_escolhido == outroMotivo)
                TextField(
                  key: const Key('motivo-digitado'),
                  controller: _outro,
                  autofocus: true,
                  maxLength: 255,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Escreva o motivo',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              const SizedBox(height: 10),
              SizedBox(
                height: 64,
                child: FilledButton(
                  key: const Key('confirmar-cancelamento'),
                  onPressed: motivo == null
                      ? null
                      : () => Navigator.of(context).pop(motivo),
                  style: FilledButton.styleFrom(
                    backgroundColor: Marca.vermelho,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'SIM, CANCELAR',
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
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Marca.azul,
                    side: const BorderSide(color: Marca.bordaCampo, width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'VOLTAR',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
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

class _OpcaoDeMotivo extends StatelessWidget {
  const _OpcaoDeMotivo({
    required this.texto,
    required this.escolhido,
    required this.onTap,
    super.key,
  });

  final String texto;
  final bool escolhido;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(
          escolhido ? Icons.radio_button_checked : Icons.radio_button_off,
          color: escolhido ? Marca.vermelho : Marca.tintaFraca,
        ),
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          backgroundColor: escolhido ? const Color(0xFFFDECEC) : Colors.white,
          side: BorderSide(
            color: escolhido ? Marca.vermelho : Marca.bordaCampo,
            width: 2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        label: Text(
          texto,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Marca.tinta,
          ),
        ),
      ),
    );
  }
}
