/// Raiz do aplicativo: tema, rotas e o grafo de dependências.
library;

import 'package:flutter/material.dart';

import '../domain/entities/seller.dart';
import '../domain/usecases/create_sale.dart';
import '../presentation/bootstrap/bootstrap_page.dart';
import '../presentation/home/home_page.dart';
import '../presentation/printer/printer_page.dart';
import '../presentation/sale/new_sale_page.dart';
import '../presentation/sale/sale_finished_page.dart';
import '../presentation/scanner/scanner_page.dart';
import '../presentation/seller/seller_selection_page.dart';
import '../presentation/setup/setup_page.dart';
import '../presentation/terminal/terminal_login_page.dart';
import 'dependencies.dart';
import 'routes.dart';
import 'theme.dart';

class CasaDasBicicletasApp extends StatelessWidget {
  const CasaDasBicicletasApp({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return DependenciesScope(
      dependencies: dependencies,
      child: MaterialApp(
        title: 'Casa das Bicicletas',
        theme: AppTheme.build(),
        debugShowCheckedModeBanner: false,
        initialRoute: AppRoutes.bootstrap,
        onGenerateRoute: _onGenerateRoute,
      ),
    );
  }

  /// Rotas resolvidas à mão porque duas delas recebem argumento tipado — a
  /// lista de vendedores e o desfecho da venda. Um mapa de rotas obrigaria a
  /// converter esses argumentos de `Object?` dentro de cada tela.
  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    final page = switch (settings.name) {
      AppRoutes.bootstrap => const BootstrapPage(),
      AppRoutes.setup => const SetupPage(),
      AppRoutes.terminalLogin => const TerminalLoginPage(),
      AppRoutes.sellerSelection => SellerSelectionPage(
          sellers: settings.arguments is List<Seller>
              ? settings.arguments! as List<Seller>
              : null,
        ),
      AppRoutes.home => const HomePage(),
      AppRoutes.newSale => const NewSalePage(),
      AppRoutes.saleFinished when settings.arguments is SaleFinished =>
        SaleFinishedPage(finished: settings.arguments! as SaleFinished),
      AppRoutes.scanner => const ScannerPage(),
      AppRoutes.printerDiagnostics => const PrinterDiagnosticsPage(),
      _ => null,
    };

    if (page == null) return null;
    return MaterialPageRoute<void>(builder: (_) => page, settings: settings);
  }
}
