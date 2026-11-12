import 'package:app_vendas/core/regra_exception.dart';
import 'package:app_vendas/data/loja_online_repository.dart';
import 'package:app_vendas/data/pedido_online_repository.dart';
import 'package:app_vendas/models/config_loja.dart';
import 'package:app_vendas/models/pedido_online.dart';
import 'package:app_vendas/models/produto.dart';
import 'package:flutter_test/flutter_test.dart';

const _cerveja = Produto(
  id: 'p1',
  nome: 'Cerveja Lata',
  categoria: 'Cervejas',
  preco: 5.5,
  custo: 3,
  estoque: 240,
);
const _gelo = Produto(
  id: 'p2',
  nome: 'Gelo',
  categoria: 'Conveniência',
  preco: 10,
  estoque: 0,
);
const _interno = Produto(
  id: 'p3',
  nome: 'Copo descartável',
  categoria: 'Conveniência',
  preco: 0.5,
  estoque: 50,
  naLojaOnline: false,
);
const _desativado = Produto(
  id: 'p4',
  nome: 'Vinho antigo',
  preco: 30,
  estoque: 3,
  ativo: false,
);

PedidoOnline _pedido(List<ItemPedidoOnline> itens) => PedidoOnline(
  id: 'abc123xyz',
  status: PedidoOnline.aguardando,
  clienteNome: 'Maria',
  endereco: 'Rua A, 10',
  formaPagamento: 'Pix',
  taxaEntrega: 7,
  criadoEm: DateTime(2026, 11, 12),
  itens: itens,
);

void main() {
  group('link da loja', () {
    test('sugere a partir do nome', () {
      expect(LojaOnlineRepository.sugerirSlug('Adega do Zé!'), 'adega-do-ze');
      expect(
        LojaOnlineRepository.sugerirSlug('  Bar & Conveniência 24h '),
        'bar-conveniencia-24h',
      );
    });

    test('valida formato', () {
      expect(LojaOnlineRepository.validarSlug('Adega-do-Ze'), 'adega-do-ze');
      for (final ruim in [
        'ab',
        'adega do ze',
        '-adega',
        'adega--ze',
        'adega_ze',
      ]) {
        expect(
          () => LojaOnlineRepository.validarSlug(ruim),
          throwsA(isA<RegraException>()),
          reason: ruim,
        );
      }
    });
  });

  group('cardápio público', () {
    test('só produtos ativos e marcados, sem custo nem saldo exato', () {
      final c = LojaOnlineRepository.cardapioPublico([
        _gelo,
        _cerveja,
        _interno,
        _desativado,
      ]);
      expect(c.map((p) => p['id']), ['p1', 'p2']);
      final cerveja = c.first;
      expect(cerveja['disponivel'], isTrue);
      expect(cerveja['maximo'], 99);
      expect(cerveja.containsKey('custo'), isFalse);
      expect(cerveja.containsKey('estoque'), isFalse);
      expect(c.last['disponivel'], isFalse);
      expect(c.last['maximo'], 0);
    });

    test('dados públicos da loja', () {
      const config = ConfigLoja(
        nomeLoja: 'Adega do Zé',
        lojaOnlineAtiva: true,
        slug: 'adega-do-ze',
        taxaEntrega: 7,
        pedidoMinimo: 30,
        chavePix: 'ze@pix.com',
      );
      final info = LojaOnlineRepository.infoPublica(config, 'loja1');
      expect(info['ativa'], isTrue);
      expect(info['taxaEntrega'], 7);
      expect(info['pedidoMinimo'], 30);
      expect(info['formas'], ConfigLoja.formasDeliveryPadrao);
      expect(info.containsKey('aberta'), isFalse);
      expect(
        LojaOnlineRepository.infoPublica(
          const ConfigLoja(lojaOnlineAtiva: true),
          'x',
        )['ativa'],
        isFalse,
        reason: 'sem link não fica ativa',
      );
    });
  });

  group('conferência do pedido online', () {
    test('usa o preço atual e aponta mudanças', () {
      final c = PedidoOnlineRepository.conferir(
        _pedido(const [
          ItemPedidoOnline(
            produtoId: 'p1',
            nome: 'Cerveja Lata',
            quantidade: 12,
            precoUnitario: 5,
          ),
        ]),
        {'p1': _cerveja},
      );
      expect(c.problemas, isEmpty);
      expect(c.precosAlterados, hasLength(1));
      expect(c.subtotalCentavos, 6600);
      expect(c.carrinho.single.quantidade, 12);
    });

    test('recusa item sem estoque ou fora de venda', () {
      final c = PedidoOnlineRepository.conferir(
        _pedido(const [
          ItemPedidoOnline(
            produtoId: 'p2',
            nome: 'Gelo',
            quantidade: 2,
            precoUnitario: 10,
          ),
          ItemPedidoOnline(
            produtoId: 'p4',
            nome: 'Vinho antigo',
            quantidade: 1,
            precoUnitario: 30,
          ),
          ItemPedidoOnline(
            produtoId: 'sumiu',
            nome: 'Produto apagado',
            quantidade: 1,
            precoUnitario: 1,
          ),
        ]),
        {'p2': _gelo, 'p4': _desativado},
      );
      expect(c.problemas, hasLength(3));
      expect(c.carrinho, isEmpty);
    });
  });
}
