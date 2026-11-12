import 'package:app_vendas/models/config_loja.dart';
import 'package:app_vendas/models/motoboy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pagamento do motoboy', () {
    test('diária de 85 + 2 por entrega', () {
      expect(
        pagamentoMotoboyCentavos(
          entregas: 12,
          diaria: 85,
          porEntrega: 2,
          recebeDiaria: true,
        ),
        10900,
      );
    });

    test('sem diária paga só as entregas', () {
      expect(
        pagamentoMotoboyCentavos(
          entregas: 5,
          diaria: 85,
          porEntrega: 2.5,
          recebeDiaria: false,
        ),
        1250,
      );
    });

    test('dia sem entrega com diária ligada paga só a diária', () {
      expect(
        pagamentoMotoboyCentavos(
          entregas: 0,
          diaria: 85,
          porEntrega: 2,
          recebeDiaria: true,
        ),
        8500,
      );
    });
  });

  test('fechamento soma entregas e total sem erro de arredondamento', () {
    final f = FechamentoMotoboys(
      id: 'x',
      inicio: DateTime(2026, 11, 12, 8),
      fim: DateTime(2026, 11, 12, 23),
      linhas: const [
        LinhaFechamento(
          motoboyId: 'a',
          nome: 'Thiago',
          entregas: 10,
          diaria: 85,
          porEntrega: 2,
          total: 105,
        ),
        LinhaFechamento(
          motoboyId: 'b',
          nome: 'Vinicius',
          entregas: 7,
          diaria: 85,
          porEntrega: 2,
          total: 99,
        ),
        LinhaFechamento(
          motoboyId: 'c',
          nome: 'Kaua',
          entregas: 0,
          diaria: 0,
          porEntrega: 2,
          total: 0,
        ),
      ],
    );
    expect(f.entregas, 17);
    expect(f.total, 204);
    expect(
      LinhaFechamento.fromMap(f.linhas.first.toMap()).total,
      f.linhas.first.total,
    );
  });

  test('configuração guarda diária e valor por entrega', () {
    final c = ConfigLoja.fromMap({'diariaMotoboy': 85, 'valorPorEntrega': 2});
    expect(c.diariaMotoboy, 85);
    expect(c.valorPorEntrega, 2);
    final ida = ConfigLoja.fromMap(c.toMap());
    expect(ida.diariaMotoboy, 85);
    expect(ida.valorPorEntrega, 2);
  });
}
