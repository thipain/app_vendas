import 'package:flutter/material.dart';

import '../core/dinheiro.dart';
import '../core/formatters.dart';
import '../core/regra_exception.dart';
import '../models/venda.dart';

/// Estado do desconto e das formas de pagamento de uma venda (PDV e
/// fechamento de comanda). Gera as linhas "cruas" de [Pagamento]; quem valida
/// de verdade é o repositório, com processarPagamentos.
class PagamentoController extends ChangeNotifier {
  String _forma = FormaPagamento.pix;
  int _parcelas = 1;
  bool _dividir = false;
  String _forma2 = FormaPagamento.dinheiro;
  int _parcelas2 = 1;
  bool _descontoPercentual = false;

  final recebido = TextEditingController();
  final valor2 = TextEditingController();
  final recebido2 = TextEditingController();
  final desconto = TextEditingController();

  PagamentoController() {
    for (final c in [recebido, valor2, recebido2, desconto]) {
      c.addListener(notifyListeners);
    }
  }

  String get forma => _forma;
  set forma(String v) {
    _forma = v;
    notifyListeners();
  }

  int get parcelas => _parcelas;
  set parcelas(int v) {
    _parcelas = v;
    notifyListeners();
  }

  bool get dividir => _dividir;
  set dividir(bool v) {
    _dividir = v;
    notifyListeners();
  }

  String get forma2 => _forma2;
  set forma2(String v) {
    _forma2 = v;
    notifyListeners();
  }

  int get parcelas2 => _parcelas2;
  set parcelas2(int v) {
    _parcelas2 = v;
    notifyListeners();
  }

  bool get descontoPercentual => _descontoPercentual;
  set descontoPercentual(bool v) {
    _descontoPercentual = v;
    notifyListeners();
  }

  /// Valor digitado no desconto (R$ ou %), nunca negativo.
  double get descontoInformado {
    final v = lerValor(desconto.text) ?? 0;
    return v < 0 ? 0 : v;
  }

  int descontoCentavos(int subtotalCentavos) => calcularDesconto(
    subtotalCentavos,
    _descontoPercentual,
    descontoInformado,
  );

  int totalCentavos(int subtotalCentavos) =>
      subtotalCentavos - descontoCentavos(subtotalCentavos);

  int get _segundaCentavos =>
      _dividir ? centavos(lerValor(valor2.text) ?? 0) : 0;

  /// Parte paga na forma principal.
  int principalCentavos(int totalCentavos) => totalCentavos - _segundaCentavos;

  /// Prévia do troco (só dinheiro). Campos de recebido vazios = valor exato.
  int trocoCentavos(int totalCentavos) {
    var troco = 0;
    final principal = principalCentavos(totalCentavos);
    if (_forma == FormaPagamento.dinheiro) {
      final r = lerValor(recebido.text);
      final rc = r == null ? principal : centavos(r);
      if (rc > principal) troco += rc - principal;
    }
    if (_dividir && _forma2 == FormaPagamento.dinheiro) {
      final segunda = _segundaCentavos;
      final r = lerValor(recebido2.text);
      final rc = r == null ? segunda : centavos(r);
      if (rc > segunda) troco += rc - segunda;
    }
    return troco;
  }

  /// Linhas de pagamento para o repositório. Valida a segunda forma como o
  /// sistema original (0 < segunda < total).
  List<Pagamento> montar(int totalCentavos) {
    if (totalCentavos <= 0) return const [];
    final segunda = _segundaCentavos;
    if (_dividir && (segunda <= 0 || segunda >= totalCentavos)) {
      throw const RegraException(
        'Informe um valor válido para a segunda forma de pagamento.',
      );
    }
    final principal = totalCentavos - segunda;
    Pagamento linha(
      String forma,
      int valor,
      int parcelas,
      TextEditingController recebidoCtrl,
    ) {
      final r = lerValor(recebidoCtrl.text);
      return Pagamento(
        forma: forma,
        valor: deCentavos(valor),
        parcelas: forma == FormaPagamento.credito ? parcelas : 1,
        recebido: forma == FormaPagamento.dinheiro
            ? (r ?? deCentavos(valor))
            : deCentavos(valor),
      );
    }

    return [
      linha(_forma, principal, _parcelas, recebido),
      if (_dividir && segunda > 0)
        linha(_forma2, segunda, _parcelas2, recebido2),
    ];
  }

  /// Volta ao padrão (Pix, sem desconto, sem divisão).
  void limpar() {
    _forma = FormaPagamento.pix;
    _parcelas = 1;
    _dividir = false;
    _forma2 = FormaPagamento.dinheiro;
    _parcelas2 = 1;
    _descontoPercentual = false;
    for (final c in [recebido, valor2, recebido2, desconto]) {
      c.removeListener(notifyListeners);
      c.clear();
      c.addListener(notifyListeners);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    for (final c in [recebido, valor2, recebido2, desconto]) {
      c.dispose();
    }
    super.dispose();
  }
}

IconData iconeFormaPagamento(String forma) => switch (forma) {
  FormaPagamento.pix => Icons.pix,
  FormaPagamento.dinheiro => Icons.payments_outlined,
  FormaPagamento.debito => Icons.credit_card,
  FormaPagamento.credito => Icons.credit_score,
  FormaPagamento.vr => Icons.restaurant,
  _ => Icons.redeem,
};

/// Campos de desconto e pagamento. [subtotalCentavos] é o valor antes do
/// desconto; o total e o troco são calculados a partir dele.
class PagamentoForm extends StatelessWidget {
  final PagamentoController controller;
  final int subtotalCentavos;
  final bool mostrarDesconto;

  const PagamentoForm({
    super.key,
    required this.controller,
    required this.subtotalCentavos,
    this.mostrarDesconto = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _conteudo(context),
    );
  }

  Widget _conteudo(BuildContext context) {
    final c = controller;
    final t = Theme.of(context);
    final total = c.totalCentavos(subtotalCentavos);
    final troco = c.trocoCentavos(total);
    final principal = c.principalCentavos(total);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (mostrarDesconto) ...[
          Text('Desconto', style: t.textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('R\$')),
                  ButtonSegment(value: true, label: Text('%')),
                ],
                selected: {c.descontoPercentual},
                onSelectionChanged: (s) => c.descontoPercentual = s.first,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: c.desconto,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '0',
                    labelText: c.descontoPercentual
                        ? 'Desconto %'
                        : 'Desconto R\$',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        Text('Pagamento', style: t.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (total == 0)
          Text(
            'Total zerado: a venda será registrada como Cortesia.',
            style: t.textTheme.bodySmall,
          )
        else ...[
          _Formas(selecionada: c.forma, onChanged: (f) => c.forma = f),
          if (c.forma == FormaPagamento.credito) ...[
            const SizedBox(height: 12),
            _Parcelas(
              rotulo: 'Parcelas no crédito',
              valor: c.parcelas,
              onChanged: (v) => c.parcelas = v,
            ),
          ],
          if (c.forma == FormaPagamento.dinheiro) ...[
            const SizedBox(height: 12),
            TextField(
              controller: c.recebido,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                isDense: true,
                labelText: 'Valor recebido em dinheiro',
                hintText: valorParaCampo(deCentavos(principal)),
                prefixText: 'R\$ ',
              ),
            ),
          ],
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            title: const Text('Dividir em duas formas de pagamento'),
            value: c.dividir,
            onChanged: (v) => c.dividir = v ?? false,
          ),
          if (c.dividir) ...[
            Text('Segunda forma', style: t.textTheme.labelLarge),
            const SizedBox(height: 8),
            _Formas(selecionada: c.forma2, onChanged: (f) => c.forma2 = f),
            const SizedBox(height: 12),
            TextField(
              controller: c.valor2,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Valor na segunda forma',
                prefixText: 'R\$ ',
              ),
            ),
            if (c.forma2 == FormaPagamento.credito) ...[
              const SizedBox(height: 12),
              _Parcelas(
                rotulo: 'Parcelas',
                valor: c.parcelas2,
                onChanged: (v) => c.parcelas2 = v,
              ),
            ],
            if (c.forma2 == FormaPagamento.dinheiro) ...[
              const SizedBox(height: 12),
              TextField(
                controller: c.recebido2,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Recebido',
                  prefixText: 'R\$ ',
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '${c.forma}: ${formatarMoeda(deCentavos(principal))}',
              style: t.textTheme.bodySmall,
            ),
          ],
          if (troco > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: t.colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Troco: ${formatarMoeda(deCentavos(troco))}',
                style: t.textTheme.titleSmall?.copyWith(
                  color: t.colorScheme.onTertiaryContainer,
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _Formas extends StatelessWidget {
  final String selecionada;
  final ValueChanged<String> onChanged;

  const _Formas({required this.selecionada, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final f in FormaPagamento.todas)
          ChoiceChip(
            avatar: Icon(iconeFormaPagamento(f), size: 18),
            showCheckmark: false,
            label: Text(f),
            selected: f == selecionada,
            onSelected: (_) => onChanged(f),
          ),
      ],
    );
  }
}

class _Parcelas extends StatelessWidget {
  final String rotulo;
  final int valor;
  final ValueChanged<int> onChanged;

  const _Parcelas({
    required this.rotulo,
    required this.valor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      key: ValueKey('$rotulo-$valor'),
      initialValue: valor,
      isDense: true,
      decoration: InputDecoration(labelText: rotulo, isDense: true),
      items: [
        for (var i = 1; i <= FormaPagamento.maxParcelas; i++)
          DropdownMenuItem(value: i, child: Text('${i}x')),
      ],
      onChanged: (v) => onChanged(v ?? 1),
    );
  }
}
