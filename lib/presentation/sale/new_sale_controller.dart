/// Estado da tela de nova venda.
///
/// A regra fica no `SaleDraft` (domínio); aqui mora só o que é de tela — o
/// texto da busca, a lista de resultados, se há requisição em curso. A
/// separação importa porque a Sprint 9 vai reaproveitar o `SaleDraft` na fila
/// local, e nada do que está neste arquivo faz sentido dentro do SQLite.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/failure.dart';
import '../../core/money.dart';
import '../../core/quantity.dart';
import '../../core/result.dart';
import '../../domain/entities/barcode_read.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/payment_method.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/receivable.dart';
import '../../domain/ports/barcode_scanner.dart';
import '../../domain/repositories/catalog_repository.dart';
import '../../domain/rules/sale_draft.dart';
import '../../domain/rules/sale_pricing.dart';
import '../../domain/usecases/create_sale.dart';

class NewSaleController extends ChangeNotifier {
  NewSaleController({
    required CatalogRepository catalog,
    required CreateSale createSale,
    required BarcodeScanner scanner,
  })  : _catalog = catalog,
        _createSale = createSale,
        _scanner = scanner {
    _listenScanner();
  }

  final CatalogRepository _catalog;
  final CreateSale _createSale;
  final BarcodeScanner _scanner;

  final SaleDraft draft = SaleDraft();

  List<Product> _results = const <Product>[];
  List<ProductCategory> _categories = const <ProductCategory>[];
  String? _categoryCode;
  bool _categoriesLoaded = false;
  String _query = '';
  Failure? _searchFailure;
  bool _searching = false;
  bool _submitting = false;
  String? _lastScannedCode;

  StreamSubscription<BarcodeRead>? _scannerSubscription;
  Timer? _debounce;

  List<Product> get results => _results;

  /// Categorias da RF04 (PEÇAS, PNEUS, ÓLEOS), como filtro da busca.
  List<ProductCategory> get categories => _categories;
  String? get categoryCode => _categoryCode;

  /// Já houve resposta do servidor — com ou sem categorias.
  bool get categoriesLoaded => _categoriesLoaded;

  Failure? get searchFailure => _searchFailure;
  bool get isSearching => _searching;
  bool get isSubmitting => _submitting;
  SaleTotals get totals => draft.totals;
  List<SaleDraftProblem> get problems => draft.problems;
  List<SaleDraftWarning> get warnings => draft.warnings;
  bool get canFinish => draft.canBeFinished && !_submitting;

  /// Último código lido — realimenta o operador de que o bipe funcionou.
  String? get lastScannedCode => _lastScannedCode;

  // -------------------------------------------------------------------------
  // Catálogo
  // -------------------------------------------------------------------------

  /// Busca com atraso curto: cada tecla digitada não vira uma requisição.
  void searchDebounced(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => search(query));
  }

  Future<void> search(String query) async {
    _query = query;
    _searching = true;
    _searchFailure = null;
    notifyListeners();

    final result = await _catalog.searchProducts(
      query: query,
      categoryCode: _categoryCode,
    );

    _searching = false;
    switch (result) {
      case Ok(:final value):
        _results = value;
      case Err(:final failure):
        _searchFailure = failure;
        _results = const <Product>[];
    }
    notifyListeners();
  }

  /// Carrega as categorias para os filtros da tela.
  ///
  /// Falhar aqui não tira a venda do ar: sem categorias o operador continua
  /// buscando por nome, SKU ou bipe, que é o caminho principal. Por isso o erro
  /// não vai para `_searchFailure`, que ocuparia a lista de produtos.
  Future<void> loadCategories() async {
    final result = await _catalog.listCategories();
    if (result case Ok(:final value)) {
      _categories = value;
    }
    // Marcado mesmo na falha: sem isto a tela de venda gira para sempre num
    // terminal sem rede, e girar indefinidamente é pior que dizer o que houve.
    _categoriesLoaded = true;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Lançamento: primeiro o valor, depois a categoria (§6 do fluxo)
  // -------------------------------------------------------------------------

  String _digitado = '';
  int _quantidade = 1;

  /// Centavos digitados, como texto — nunca `double`.
  ///
  /// O buffer guarda os dígitos na ordem em que foram tocados e só vira
  /// `Money` na hora de lançar. É o que mantém "12" significando R$ 0,12 e
  /// "1200" significando R$ 12,00 sem passar por ponto flutuante em momento
  /// algum (§6 — "não usar float").
  String get digitado => _digitado;

  int get quantidade => _quantidade;

  Money get valorDigitado =>
      Money.fromCents(int.tryParse(_digitado.isEmpty ? '0' : _digitado) ?? 0);

  /// Só dá para escolher a categoria depois de haver valor — é a ordem da
  /// referência, e o que impede lançar linha de zero real.
  bool get podeLancar => valorDigitado.isPositive;

  void digitar(String digito) {
    // Teto de sete dígitos: R$ 99.999,99 já é muito acima de qualquer venda
    // de balcão, e sem limite o número sai da tela.
    if (_digitado.length + digito.length > 7) return;
    _digitado = (_digitado + digito).replaceFirst(RegExp(r'^0+(?=\d)'), '');
    notifyListeners();
  }

  void apagarDigito() {
    if (_digitado.isEmpty) return;
    _digitado = _digitado.substring(0, _digitado.length - 1);
    notifyListeners();
  }

  void limparDigitado() {
    _digitado = '';
    _quantidade = 1;
    notifyListeners();
  }

  void mudarQuantidade(int delta) {
    _quantidade = (_quantidade + delta).clamp(1, 99);
    notifyListeners();
  }

  /// Última linha lançada, enquanto der para desfazer.
  ///
  /// Some sozinha depois de alguns segundos: passado isso, o vendedor já
  /// seguiu para o próximo item, e um "desfazer" que apaga algo lançado há um
  /// minuto é pior do que não ter desfazer nenhum.
  SaleDraftLine? _ultimaLinha;
  Timer? _janelaDeDesfazer;

  SaleDraftLine? get ultimaLinha => _ultimaLinha;

  /// Fecha o lançamento: o valor digitado vira uma linha daquela categoria.
  SaleDraftLine? lancarNaCategoria(ProductCategory category) {
    if (!podeLancar) return null;

    final linha = draft.addManual(
      category: category,
      price: valorDigitado,
      quantity: Quantity.units(_quantidade),
    );
    _digitado = '';
    _quantidade = 1;
    _ultimaLinha = linha;
    _janelaDeDesfazer?.cancel();
    _janelaDeDesfazer = Timer(const Duration(seconds: 8), () {
      _ultimaLinha = null;
      notifyListeners();
    });
    notifyListeners();
    return linha;
  }

  /// Desfaz o último lançamento.
  void desfazerUltimo() {
    final linha = _ultimaLinha;
    if (linha == null) return;
    _janelaDeDesfazer?.cancel();
    _ultimaLinha = null;
    draft.remove(linha.id);
    notifyListeners();
  }

  /// Filtra por categoria; o mesmo código tocado de novo limpa o filtro.
  Future<void> selectCategory(String? code) async {
    _categoryCode = _categoryCode == code ? null : code;
    notifyListeners();
    await search(_query);
  }

  void _listenScanner() {
    // O leitor também serve para montar a venda, não só para o caixa: bipar a
    // etiqueta do produto é mais rápido e mais confiável do que digitar o SKU.
    _scannerSubscription = _scanner.reads.listen(
      (read) => unawaited(addByBarcode(read.code)),
      onError: (Object _) {},
    );
    unawaited(_scanner.start());
  }

  /// Adiciona o produto cujo código de barras foi lido.
  Future<Failure?> addByBarcode(String code) async {
    _lastScannedCode = code;
    notifyListeners();

    final result = await _catalog.findByBarcode(code);

    return switch (result) {
      Err(:final failure) => failure,
      Ok(:final value) => _addFound(value, code),
    };
  }

  Failure? _addFound(Product? product, String code) {
    if (product == null) {
      return BusinessRuleFailure('Nenhum produto com o código "$code".');
    }
    add(product);
    return null;
  }

  // -------------------------------------------------------------------------
  // Carrinho
  // -------------------------------------------------------------------------

  void add(Product product) {
    draft.add(product);
    notifyListeners();
  }

  /// Lança a linha manual da V1: categoria e valor negociado.
  void addManual({
    required ProductCategory category,
    required Money price,
    Quantity quantity = const Quantity.units(1),
  }) {
    draft.addManual(category: category, price: price, quantity: quantity);
    notifyListeners();
  }

  void setQuantity(int lineId, Quantity quantity) {
    draft.setQuantity(lineId, quantity);
    notifyListeners();
  }

  void increment(int lineId) {
    final line = _lineFor(lineId);
    if (line == null) return;
    setQuantity(lineId, line.quantity + const Quantity.units(1));
  }

  void decrement(int lineId) {
    final line = _lineFor(lineId);
    if (line == null) return;
    setQuantity(lineId, line.quantity - const Quantity.units(1));
  }

  SaleDraftLine? _lineFor(int lineId) {
    for (final line in draft.lines) {
      if (line.id == lineId) return line;
    }
    return null;
  }

  void remove(int lineId) {
    draft.remove(lineId);
    notifyListeners();
  }

  void setPaymentMethod(PaymentMethod method) {
    draft.paymentMethod = method;
    // Trocar de notinha para outra forma não apaga o cliente: ele continua
    // sendo uma informação útil da venda, e voltar para notinha é comum.
    notifyListeners();
  }

  /// Pendências do cliente escolhido, como vieram da busca.
  ///
  /// `null` quando não há cliente ou não deu para consultar — que é diferente
  /// de lista vazia, e a tela precisa dessa diferença para não dizer "não deve
  /// nada" quando na verdade não perguntou.
  List<Receivable>? _customerReceivables;

  List<Receivable>? get customerReceivables => _customerReceivables;

  void setCustomer(Customer? customer, {List<Receivable>? receivables}) {
    draft.customer = customer;
    _customerReceivables = customer == null ? null : receivables;
    notifyListeners();
  }

  /// Desconto negociado, em percentual ou em reais; acima do teto o domínio
  /// recusa (13.3).
  void setDiscount(SaleDiscount discount) {
    draft.discount = discount;
    notifyListeners();
  }

  /// Zera a venda em montagem, sem sair da tela.
  ///
  /// Existe porque a Nova Venda virou a raiz do fluxo: descartar não pode mais
  /// ser `Navigator.pop()`, que ali fecharia o aplicativo.
  void discard() {
    draft.clear();
    draft.paymentMethod = PaymentMethod.dinheiro;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Finalização
  // -------------------------------------------------------------------------

  Future<Result<SaleFinished>> finish() async {
    if (_submitting) {
      return const Err(BusinessRuleFailure('A venda já está sendo enviada.'));
    }

    _submitting = true;
    notifyListeners();

    final result = await _createSale(draft);

    _submitting = false;
    notifyListeners();
    return result;
  }

  @override
  void dispose() {
    _janelaDeDesfazer?.cancel();
    _debounce?.cancel();
    unawaited(_scannerSubscription?.cancel());
    unawaited(_scanner.stop());
    super.dispose();
  }
}
