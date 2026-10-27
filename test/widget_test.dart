import 'package:app_vendas/core/formatters.dart';
import 'package:app_vendas/core/update/update_service.dart';
import 'package:app_vendas/core/regra_exception.dart';
import 'package:app_vendas/models/caixa.dart';
import 'package:app_vendas/models/loja.dart';
import 'package:app_vendas/models/venda.dart';
import 'package:app_vendas/widgets/seletor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('compararVersoes', () {
    test('detecta versão mais nova', () {
      expect(compararVersoes('1.2.0', '1.1.9'), greaterThan(0));
      expect(compararVersoes('2.0.0', '1.99.99'), greaterThan(0));
      expect(compararVersoes('1.0.10', '1.0.9'), greaterThan(0));
    });

    test('versões iguais ou mais antigas', () {
      expect(compararVersoes('1.0.0', '1.0.0'), 0);
      expect(compararVersoes('1.0', '1.0.0'), 0);
      expect(compararVersoes('1.0.0+5', '1.0.0'), 0);
      expect(compararVersoes('1.0.0', '1.0.1'), lessThan(0));
    });
  });

  test('lerValor aceita formato brasileiro', () {
    expect(lerValor('1.234,56'), 1234.56);
    expect(lerValor('10,5'), 10.5);
    expect(lerValor('10.5'), 10.5);
    expect(lerValor(''), isNull);
  });

  test('total da venda aplica desconto', () {
    final venda = Venda(
      itens: const [
        ItemVenda(produtoId: 'a', nome: 'A', quantidade: 2, precoUnitario: 10),
        ItemVenda(produtoId: 'b', nome: 'B', quantidade: 1, precoUnitario: 5.5),
      ],
      desconto: 0.5,
      formaPagamento: 'Pix',
      data: DateTime(2026),
    );
    expect(venda.subtotal, 25.5);
    expect(venda.total, 25);
  });

  group('processarPagamentos', () {
    test('dinheiro calcula troco e soma fecha com o total', () {
      final p = processarPagamentos(const [
        Pagamento(forma: FormaPagamento.dinheiro, valor: 30, recebido: 50),
        Pagamento(forma: FormaPagamento.pix, valor: 20),
      ], 5000);
      expect(p, hasLength(2));
      expect(p.first.troco, 20);
      expect(p.last.troco, 0);
    });

    test('total zero vira cortesia', () {
      final p = processarPagamentos(const [], 0);
      expect(p.single.forma, FormaPagamento.cortesia);
    });

    test('ignora linhas zeradas e limita parcelas do crédito', () {
      final p = processarPagamentos(const [
        Pagamento(forma: FormaPagamento.credito, valor: 10, parcelas: 30),
        Pagamento(forma: FormaPagamento.pix, valor: 0),
      ], 1000);
      expect(p.single.parcelas, FormaPagamento.maxParcelas);
    });

    test('recusa soma diferente e dinheiro insuficiente', () {
      expect(
        () => processarPagamentos(const [
          Pagamento(forma: FormaPagamento.pix, valor: 9.99),
        ], 1000),
        throwsA(isA<RegraException>()),
      );
      expect(
        () => processarPagamentos(const [
          Pagamento(forma: FormaPagamento.dinheiro, valor: 10, recebido: 5),
        ], 1000),
        throwsA(isA<RegraException>()),
      );
    });
  });

  test('desconto percentual e em valor ficam limitados ao subtotal', () {
    expect(calcularDesconto(10000, true, 10), 1000);
    expect(calcularDesconto(10000, true, 150), 10000);
    expect(calcularDesconto(10000, false, 25.5), 2550);
    expect(calcularDesconto(10000, false, 500), 10000);
    expect(calcularDesconto(10000, false, -3), 0);
  });

  test('caixa: só dinheiro entra na gaveta e o saldo segue a fórmula', () {
    final venda = Venda(
      itens: const [
        ItemVenda(produtoId: 'a', nome: 'A', quantidade: 1, precoUnitario: 50),
      ],
      pagamentos: const [
        Pagamento(
          forma: FormaPagamento.dinheiro,
          valor: 30,
          recebido: 50,
          troco: 20,
        ),
        Pagamento(forma: FormaPagamento.debito, valor: 20),
      ],
      formaPagamento: FormaPagamento.dinheiro,
      data: DateTime(2026),
    );
    expect(venda.valorEmDinheiro, 30);

    MovimentoCaixa m(String tipo, double valor) => MovimentoCaixa(
      id: tipo,
      caixaId: 'c',
      tipo: tipo,
      valor: valor,
      data: DateTime(2026),
    );
    expect(
      saldoCaixa([
        m(MovimentoCaixa.abertura, 100),
        m(MovimentoCaixa.venda, 30),
        m(MovimentoCaixa.suprimento, 10.1),
        m(MovimentoCaixa.sangria, 20),
        m(MovimentoCaixa.estorno, 5),
        m(MovimentoCaixa.fechamento, 999),
      ]),
      115.1,
    );
  });

  test('busca ignora acentos e maiúsculas', () {
    expect(normalizarBusca('Água Tônica'), 'agua tonica');
  });

  group('mensalidade da loja', () {
    final hoje = DateTime(2026, 10, 27, 10);
    Loja loja(DateTime? pagoAte, {bool ativa = true, bool teste = false}) =>
        Loja(
          id: 'l',
          nome: 'L',
          ativa: ativa,
          pagoAte: pagoAte,
          carenciaDias: 5,
          emTeste: teste,
        );

    test('situação conforme o vencimento e a carência', () {
      expect(loja(null).situacao(hoje), SituacaoLoja.semCobranca);
      expect(loja(DateTime(2026, 12, 1)).situacao(hoje), SituacaoLoja.emDia);
      expect(
        loja(DateTime(2026, 10, 30)).situacao(hoje),
        SituacaoLoja.vencendo,
      );
      expect(
        loja(DateTime(2026, 10, 30), teste: true).situacao(hoje),
        SituacaoLoja.emTeste,
      );
      expect(
        loja(DateTime(2026, 10, 25)).situacao(hoje),
        SituacaoLoja.atrasada,
      );
      expect(
        loja(DateTime(2026, 10, 20)).situacao(hoje),
        SituacaoLoja.travadaPagamento,
      );
      expect(
        loja(DateTime(2027), ativa: false).situacao(hoje),
        SituacaoLoja.travadaManual,
      );
      expect(loja(DateTime(2026, 10, 20)).situacao(hoje).travada, isTrue);
    });

    test('pagamento avança o vencimento a partir do anterior', () {
      expect(
        proximoVencimento(DateTime(2026, 10, 10), 1, hoje),
        DateTime(2026, 11, 10),
      );
      expect(
        proximoVencimento(DateTime(2026, 1, 31), 1, DateTime(2026, 2, 1)),
        DateTime(2026, 2, 28),
      );
      // Vencida há mais de um mês ou sem cobrança: conta a partir de hoje.
      expect(
        proximoVencimento(DateTime(2026, 6, 1), 1, hoje),
        DateTime(2026, 11, 27),
      );
      expect(proximoVencimento(null, 3, hoje), DateTime(2027, 1, 27));
    });
  });
}
