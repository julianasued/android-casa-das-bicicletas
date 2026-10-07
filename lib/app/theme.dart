/// Tema do aplicativo, dimensionado para o balcão.
///
/// O M10 Pro é um terminal de 5", operado em pé, com o cliente esperando e às
/// vezes com a mão suja de graxa. Daí as duas escolhas que fogem do padrão do
/// Material: alvo de toque grande (48 lógicos no mínimo) e texto maior que o
/// usual. Um botão pequeno aqui custa uma venda lançada errada.
library;

import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  /// Verde da identidade da loja.
  static const Color seed = Color(0xFF1B5E20);

  /// Altura mínima confortável para toque com o dedo, em pé.
  static const double touchTarget = 56;

  static ThemeData build() {
    final scheme = ColorScheme.fromSeed(seedColor: seed);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        centerTitle: false,
        elevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(touchTarget),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(touchTarget),
          textStyle: const TextStyle(fontSize: 16),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      ),
      listTileTheme: const ListTileThemeData(
        minVerticalPadding: 12,
        titleTextStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Estilo do valor total — o número que o cliente confere de longe.
  static TextStyle totalStyle(BuildContext context) =>
      Theme.of(context).textTheme.headlineMedium!.copyWith(
            fontWeight: FontWeight.bold,
            fontFeatures: const [FontFeature.tabularFigures()],
          );

  /// Números alinhados em coluna — preço não pode dançar de linha para linha.
  static TextStyle monetaryStyle(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium!.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          );
}
