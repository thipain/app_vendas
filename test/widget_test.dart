import 'package:app_vendas/core/formatters.dart';
import 'package:app_vendas/core/update/update_service.dart';
import 'package:app_vendas/models/venda.dart';
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
}
