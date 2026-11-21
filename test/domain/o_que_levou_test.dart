/// O que o cliente levou, na notinha (21/11/2026).
///
/// Quem paga a notinha depois quer saber o que foi levado. O vendedor
/// descreve, se quiser, com o teclado do sistema; a descrição vai com a venda
/// (também pela fila offline), sai no comprovante de retirada e aparece nas
/// notinhas do cliente.
library;

import 'package:casa_das_bicicletas/core/money.dart';
import 'package:casa_das_bicicletas/data/remote/mappers.dart';
import 'package:casa_das_bicicletas/data/repositories/sale_repository_impl.dart';
import 'package:casa_das_bicicletas/domain/entities/customer.dart';
import 'package:casa_das_bicicletas/domain/entities/payment_method.dart';
import 'package:casa_das_bicicletas/domain/entities/product.dart';
import 'package:casa_das_bicicletas/domain/entities/seller.dart';
import 'package:casa_das_bicicletas/domain/entities/terminal_identity.dart';
import 'package:casa_das_bicicletas/domain/rules/offline_document.dart';
import 'package:casa_das_bicicletas/domain/rules/sale_draft.dart';
import 'package:casa_das_bicicletas/platform/printer/document_layout.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const _pecas = ProductCategory(id: 1, code: 'PECAS', name: 'Peças');
const _levou = '2 câmaras aro 26 e 1 remendo — João (oficina)';

SaleDraft _notinha({String note = ''}) => SaleDraft(paymentMethod: PaymentMethod.notinha)
  ..customer = const Customer(id: 7, name: 'Oficina do Zé')
  ..addManual(category: _pecas, price: const Money.fromCents(4500))
  ..note = note;

void main() {
  final repositorio = SaleRepositoryImpl(buildTestDependencies().apiClient);

  group('envio', () {
    test('a notinha leva o que foi descrito, sem espaços nas pontas', () {
      final corpo = repositorio.payloadFor(_notinha(note: '  $_levou  '));

      expect(corpo['note'], _levou);
    });

    test('sem descrição, o campo nem vai', () {
      expect(repositorio.payloadFor(_notinha()).containsKey('note'), isFalse);
      expect(repositorio.payloadFor(_notinha(note: '   ')).containsKey('note'), isFalse);
    });

    test('trocou para outra forma: a descrição fica guardada, mas não vai', () {
      final draft = _notinha(note: _levou)..paymentMethod = PaymentMethod.pix;

      expect(repositorio.payloadFor(draft).containsKey('note'), isFalse);
      expect(draft.note, _levou, reason: 'voltar para notinha é comum');

      draft.paymentMethod = PaymentMethod.notinha;
      expect(repositorio.payloadFor(draft)['note'], _levou);
    });

    test('descartar a venda apaga a descrição', () {
      final draft = _notinha(note: _levou)..clear();

      expect(draft.note, isEmpty);
    });
  });

  group('papel', () {
    const layout = DocumentLayout();

    String papelDa(Map<String, Object?> json) =>
        renderCommandsAsText(layout.build(printedDocumentFromJson(json)));

    test('o comprovante de retirada mostra o que levou, inteiro e na largura', () {
      final papel = papelDa({
        ...documentJson(reference: 'DOC2-L1-7F3A9C2B'),
        'payment_method': 'NOTINHA',
        'sale_note': _levou,
      });

      expect(papel, contains('O que levou:'));
      final linhas = papel.split('\n');
      final inicio = linhas.indexOf('O que levou:');
      final descricao = linhas.skip(inicio + 1).take(2).join(' ');
      expect(descricao, _levou);
      for (final linha in linhas) {
        expect(linha.length, lessThanOrEqualTo(paperColumns), reason: linha);
      }
    });

    test('sem descrição, nada a mais no papel', () {
      final papel = papelDa(documentJson(reference: 'DOC2-L1-7F3A9C2B'));

      expect(papel, isNot(contains('O que levou')));
    });

    test('sem internet: o comprovante feito no M10 também leva a descrição', () {
      final documento = offlineDocument1(
        draft: _notinha(note: _levou),
        identity: TerminalIdentity(
          storeCode: 'L1',
          storeName: 'Casa das Bicicletas Centro',
          terminalName: 'M10 1',
          learnedAt: DateTime.utc(2026, 11, 1),
        ),
        seller: const Seller(id: 12, name: 'Felipe'),
        storeCode: 'L1',
      );

      expect(documento.saleNote, _levou);
      expect(renderCommandsAsText(layout.build(documento)), contains('O que levou:'));
    });
  });

  test('a notinha do cliente traz o que levou', () {
    final notinha = receivableFromJson(const {
      'id': 3,
      'sale_id': 40,
      'original_amount': '45.00',
      'paid_amount': '0.00',
      'pending_amount': '45.00',
      'status': 'ABERTA',
      'created_at': '2026-11-21T10:00:00-03:00',
      'sale_note': _levou,
    });

    expect(notinha.saleNote, _levou);
    expect(
      receivableFromJson(const {
        'id': 4,
        'original_amount': '10.00',
        'pending_amount': '10.00',
        'created_at': '2026-11-01T10:00:00-03:00',
      }).saleNote,
      isEmpty,
      reason: 'servidor antigo, sem o campo',
    );
  });
}
