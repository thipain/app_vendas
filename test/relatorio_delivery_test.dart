import 'package:app_vendas/data/pedido_online_repository.dart';
import 'package:app_vendas/models/comanda.dart';
import 'package:app_vendas/models/cupom.dart';
import 'package:app_vendas/models/pedido.dart';
import 'package:app_vendas/models/pedido_online.dart';
import 'package:app_vendas/models/produto.dart';
import 'package:app_vendas/models/resumo_delivery.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime(2026, 11, 10, 20);

Pedido _p(
  String id, {
  String status = Pedido.concluido,
  String telefone = '(11) 98888-0000',
  String nome = 'Maria',
  String bairro = 'Centro - Itu/SP',
  String? online,
  String motoboy = 'Thiago',
  double preco = 10,
  int qtd = 3,
  double taxa = 5,
  double desconto = 0,
  int preparo = 15,
  int rua = 20,
  int diasAtras = 0,
}) {
  final criado = _t0.subtract(Duration(days: diasAtras));
  return Pedido(
    id: id,
    status: status,
    clienteNome: nome,
    telefone: telefone,
    endereco: 'Rua A, 1',
    bairro: bairro,
    formaPagamento: 'Pix',
    taxaEntrega: taxa,
    desconto: desconto,
    pedidoOnlineId: online,
    motoboyId: 'm-$motoboy',
    entregadorNome: motoboy,
    criadoEm: criado,
    saiuEm: criado.add(Duration(minutes: preparo)),
    entregueEm: criado.add(Duration(minutes: preparo + rua)),
    itens: [
      ItemComanda(
        produtoId: 'x',
        nome: 'Cerveja',
        quantidade: qtd,
        precoUnitario: preco,
        adicionadoEm: criado,
      ),
    ],
  );
}

void main() {
  test('pedido com cupom desconta só dos produtos', () {
    final p = _p('a', desconto: 6);
    expect(p.subtotal, 30);
    expect(p.total, 29); // 30 - 6 + 5
    expect(_p('b', desconto: 999).total, 5, reason: 'desconto limitado');
  });

  test('resumo do delivery', () {
    final r = ResumoDelivery.de([
      _p('1'),
      _p('2', online: 'o2', bairro: 'centro', motoboy: 'Kaua', rua: 40),
      _p('3', bairro: 'Vila Nova', desconto: 5),
      _p('4', status: Pedido.cancelado),
      _p('5', status: Pedido.emRota, preparo: 10, rua: 0),
    ], recusadosOnline: 2);
    expect(r.registrados, 5);
    expect(r.concluidos, 3);
    expect(r.cancelados, 1);
    expect(r.recusadosOnline, 2);
    expect(r.faturamento, 35 + 35 + 30);
    expect(r.taxas, 15);
    expect(r.descontos, 5);
    expect(r.ticketMedio, closeTo(33.33, 0.01));
    expect(r.canais.map((g) => g.nome), ['Balcão / WhatsApp', 'Loja online']);
    expect(r.bairros.first.nome, 'Centro');
    expect(r.bairros.first.pedidos, 2);
    final thiago = r.motoboys.firstWhere((g) => g.nome == 'Thiago');
    expect(thiago.pedidos, 2);
    expect(thiago.mediaEntrega, 20);
    expect(r.motoboys.firstWhere((g) => g.nome == 'Kaua').mediaEntrega, 40);
    expect(r.mediaPreparo, 13.75); // (15+15+15+10)/4
  });

  test('clientes juntados pelo telefone, com e sem 55', () {
    final c = ClienteDelivery.agrupar([
      _p('1', telefone: '(11) 98888-0000', diasAtras: 40),
      _p('2', telefone: '+55 11 98888-0000', nome: 'Maria S.', diasAtras: 35),
      _p('3', telefone: '11 97777-1111', nome: 'João', qtd: 10),
      _p('4', telefone: '11 97777-1111', status: Pedido.cancelado),
    ]);
    expect(c, hasLength(2));
    expect(c.first.nome, 'João', reason: 'quem mais gastou primeiro');
    final maria = c.last;
    expect(maria.pedidos, 2);
    expect(maria.nome, 'Maria S.', reason: 'nome do pedido mais recente');
    expect(maria.diasSemPedir(_t0), 35);
  });

  group('cupom', () {
    const dezPorCento = Cupom(codigo: 'BEMVINDO10', quantia: 10, minimo: 30);
    const cincoReais = Cupom(codigo: 'MENOS5', tipo: Cupom.valor, quantia: 5);

    test('desconto percentual e em valor', () {
      expect(dezPorCento.descontoCentavos(4550), 455);
      expect(cincoReais.descontoCentavos(4550), 500);
      expect(
        cincoReais.descontoCentavos(300),
        300,
        reason: 'não passa do subtotal',
      );
    });

    test('validade, mínimo e ativo', () {
      final hoje = DateTime(2026, 11, 12, 23, 59);
      expect(dezPorCento.motivoInvalido(3000, hoje), isNull);
      expect(dezPorCento.motivoInvalido(2999, hoje), contains('a partir'));
      final venceHoje = Cupom(
        codigo: 'X',
        quantia: 10,
        validoAte: DateTime(2026, 11, 12),
      );
      expect(
        venceHoje.motivoInvalido(100, hoje),
        isNull,
        reason: 'vale o dia todo',
      );
      expect(
        venceHoje.motivoInvalido(100, DateTime(2026, 11, 13)),
        'Cupom vencido.',
      );
      const desativado = Cupom(codigo: 'Y', quantia: 5, ativo: false);
      expect(desativado.motivoInvalido(100, hoje), 'Cupom desativado.');
      expect(Cupom.codigoValido('BEMVINDO10'), isTrue);
      expect(Cupom.codigoValido('bem vindo'), isFalse);
    });

    test('pedido online recalcula o cupom ao aceitar', () {
      const cerveja = Produto(id: 'p1', nome: 'Cerveja', preco: 5, estoque: 50);
      final po = PedidoOnline(
        id: 'o1',
        status: PedidoOnline.aguardando,
        clienteNome: 'Ana',
        endereco: 'Rua B',
        formaPagamento: 'Dinheiro',
        cupom: 'BEMVINDO10',
        desconto: 4,
        criadoEm: _t0,
        itens: const [
          ItemPedidoOnline(
            produtoId: 'p1',
            nome: 'Cerveja',
            quantidade: 8,
            precoUnitario: 5,
          ),
        ],
      );
      final ok = PedidoOnlineRepository.conferir(
        po,
        {'p1': cerveja},
        cupons: {'BEMVINDO10': dezPorCento},
        agora: _t0,
      );
      expect(ok.descontoCentavos, 400);
      expect(ok.avisoCupom, isNull);
      final sem = PedidoOnlineRepository.conferir(po, {
        'p1': cerveja,
      }, agora: _t0);
      expect(sem.descontoCentavos, 0);
      expect(sem.avisoCupom, contains('não existe'));
    });
  });

  test('formatar minutos', () {
    expect(formatarMinutos(null), '—');
    expect(formatarMinutos(12.4), '12 min');
    expect(formatarMinutos(65), '1h05');
  });
}
