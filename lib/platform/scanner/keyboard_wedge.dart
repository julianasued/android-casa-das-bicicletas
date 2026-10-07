/// Captura do leitor configurado em modo teclado.
///
/// O leitor do M10 opera de dois jeitos, e os dois aparecem em campo: emitindo
/// um broadcast — que o canal nativo escuta — ou emulando um teclado, digitando
/// o código e um Enter. O segundo modo não passa por canal nenhum: chega como
/// tecla pressionada.
///
/// Este widget cobre esse caso sem obrigar o operador a tocar num campo de
/// texto: ele acumula os caracteres que chegam e entrega o código no Enter.
/// Digitação humana também passaria por aqui, o que é aceitável — a tela do
/// leitor aceita as duas coisas de propósito.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/entities/barcode_read.dart';

class KeyboardWedgeListener extends StatefulWidget {
  const KeyboardWedgeListener({
    required this.onRead,
    required this.child,
    this.enabled = true,
    super.key,
  });

  final ValueChanged<BarcodeRead> onRead;
  final Widget child;
  final bool enabled;

  @override
  State<KeyboardWedgeListener> createState() => _KeyboardWedgeListenerState();
}

class _KeyboardWedgeListenerState extends State<KeyboardWedgeListener> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'leitor em modo teclado');
  final StringBuffer _buffer = StringBuffer();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!widget.enabled || event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final code = _buffer.toString().trim();
      _buffer.clear();
      if (code.isEmpty) return KeyEventResult.handled;

      widget.onRead(
        BarcodeRead(
          code: code,
          readAt: DateTime.now(),
          source: BarcodeSource.keyboardWedge,
        ),
      );
      return KeyEventResult.handled;
    }

    final character = event.character;
    if (character != null && character.isNotEmpty && character != '\n') {
      _buffer.write(character);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.enabled,
      onKeyEvent: _onKey,
      child: widget.child,
    );
  }
}
