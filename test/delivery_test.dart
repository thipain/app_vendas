import 'package:app_vendas/core/contato.dart';
import 'package:app_vendas/core/permissoes.dart';
import 'package:app_vendas/models/comanda.dart';
import 'package:app_vendas/models/config_loja.dart';
import 'package:app_vendas/models/pedido.dart';
import 'package:app_vendas/models/usuario.dart';
import 'package:app_vendas/models/venda.dart';
import 'package:flutter_test/flutter_test.dart';

Pedido _pedido({
  String forma = FormaPagamento.dinheiro,
  double? trocoPara,
  double taxa = 7,
  bool pixConfirmado = false,
}) => Pedido(
  id: 'abcdef123',
  status: Pedido.novo,
  clienteNome: 'Maria',
  endereco: 'Rua A, 10',
  bairro: 'Centro',
  formaPagamento: forma,
  trocoPara: trocoPara,
  taxaEntrega: taxa,
  pixConfirmado: pixConfirmado,
  criadoEm: DateTime(2026, 11, 11),
  itens: [
    ItemComanda(
      produtoId: 'p1',
      nome: 'Cerveja',
      quantidade: 6,
      precoUnitario: 5.5,
      adicionadoEm: DateTime(2026, 11, 11),
    ),
  ],
);

void main() {
  group('Pedido', () {
    test('total soma produtos e taxa de entrega', () {
      final p = _pedido();
      expect(p.subtotal, 33);
      expect(p.total, 40);
      expect(p.codigo, 'ABCDEF');
      expect(p.enderecoCompleto, 'Rua A, 10 - Centro');
    });

    test('troco só em dinheiro e quando a nota é maior', () {
      expect(_pedido(trocoPara: 50).troco, 10);
      expect(_pedido(trocoPara: 40).troco, 0);
      expect(_pedido().troco, 0);
      expect(_pedido(forma: FormaPagamento.pix, trocoPara: 50).troco, 0);
      expect(
        _pedido(trocoPara: 50).instrucaoPagamento,
        contains('levar troco de R\$ 10,00'),
      );
    });

    test('instrução de pagamento para o entregador', () {
      expect(
        _pedido(forma: FormaPagamento.credito).instrucaoPagamento,
        'LEVAR MAQUININHA — Crédito',
      );
      expect(
        _pedido(forma: FormaPagamento.pix).instrucaoPagamento,
        contains('não confirmado'),
      );
      expect(
        _pedido(
          forma: FormaPagamento.pix,
          pixConfirmado: true,
        ).instrucaoPagamento,
        contains('não cobrar'),
      );
    });

    test('troco não é gravado para outras formas', () {
      final d = DadosPedido(
        clienteNome: 'Maria',
        telefone: '11999990000',
        endereco: 'Rua A',
        formaPagamento: FormaPagamento.pix,
        trocoPara: 50,
      );
      expect(d.toMap()['trocoPara'], isNull);
    });
  });

  group('Entregador', () {
    const motoboy = Usuario(
      nome: 'João',
      email: 'joao@x.com',
      papel: Usuario.papelEntregador,
      permissoes: {Permissao.estoque},
    );
    const admin = Usuario(
      nome: 'Ana',
      email: 'ana@x.com',
      papel: Usuario.papelAdmin,
    );

    test('só acessa entregas, ponto e perfil', () {
      expect(motoboy.pode(Permissao.entregas), isTrue);
      expect(motoboy.pode(Permissao.meuPonto), isTrue);
      expect(motoboy.pode(Permissao.perfil), isTrue);
      expect(motoboy.pode(Permissao.vendas), isFalse);
      expect(motoboy.pode(Permissao.retiradas), isFalse);
      expect(motoboy.pode(Permissao.estoque), isFalse);
      expect(motoboy.pode(Permissao.delivery), isFalse);
    });

    test('admin vê o painel do delivery, não a tela do motoboy', () {
      expect(admin.pode(Permissao.delivery), isTrue);
      expect(admin.pode(Permissao.entregas), isFalse);
    });
  });

  test('telefone para o WhatsApp', () {
    expect(telefoneInternacional('(11) 99999-0000'), '5511999990000');
    expect(telefoneInternacional('+55 11 3333-4444'), '551133334444');
    expect(telefoneInternacional('9999-0000'), isNull);
  });

  test('venda de delivery soma a taxa no total', () {
    final v = Venda(
      itens: const [
        ItemVenda(
          produtoId: 'p1',
          nome: 'Cerveja',
          quantidade: 2,
          precoUnitario: 10,
        ),
      ],
      formaPagamento: FormaPagamento.pix,
      taxaEntrega: 5,
      pedidoId: 'x',
      data: DateTime(2026),
    );
    expect(v.total, 25);
    expect(v.toMap()['taxaEntrega'], 5);
  });

  test('configuração lê as formas aceitas no delivery', () {
    final c = ConfigLoja.fromMap({
      'taxaEntrega': 6.5,
      'chavePix': 'loja@pix.com',
      'formasDelivery': ['Crédito', 'Pix'],
    });
    expect(c.taxaEntrega, 6.5);
    expect(c.formasDelivery, [FormaPagamento.pix, FormaPagamento.credito]);
    expect(const ConfigLoja().formasDelivery, hasLength(4));
  });
}
