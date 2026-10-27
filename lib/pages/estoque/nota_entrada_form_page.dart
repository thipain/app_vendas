import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/formatters.dart';
import '../../core/regra_exception.dart';
import '../../data/dados.dart';
import '../../data/nota_entrada_repository.dart';
import '../../models/nota_entrada.dart';
import '../../models/produto.dart';
import '../../widgets/foto_produto.dart';
import '../../widgets/largura_maxima.dart';
import '../../widgets/mensagens.dart';
import '../../widgets/seletor.dart';
import 'estoque_widgets.dart';
import 'nota_entrada_detalhe_page.dart';

class _Linha {
  String? produtoId;
  String produtoNome;
  final TextEditingController quantidade;
  final TextEditingController custo;

  _Linha({this.produtoId, this.produtoNome = '', int? qtd, double? custo})
    : quantidade = TextEditingController(text: qtd == null ? '1' : '$qtd'),
      custo = TextEditingController(
        text: custo == null ? '' : custoParaCampo(custo),
      );

  void dispose() {
    quantidade.dispose();
    custo.dispose();
  }
}

/// Criação e edição de nota de entrada. Ao salvar, abre a página da nota
/// (impressão), a menos que [abrirNotaAoSalvar] seja false (edição a partir
/// da própria página da nota).
class NotaEntradaFormPage extends StatefulWidget {
  final NotaEntrada? nota;
  final bool abrirNotaAoSalvar;

  const NotaEntradaFormPage({
    super.key,
    this.nota,
    this.abrirNotaAoSalvar = true,
  });

  @override
  State<NotaEntradaFormPage> createState() => _NotaEntradaFormPageState();
}

class _NotaEntradaFormPageState extends State<NotaEntradaFormPage> {
  static final _dia = DateFormat('dd/MM/yyyy');

  final _repo = NotaEntradaRepository();
  late final NotaEntrada? _antiga = widget.nota;
  late DateTime _data = _antiga?.dataEntrada ?? DateTime.now();
  late final _numero = TextEditingController(text: _antiga?.numero ?? '');
  late final _fornecedor = TextEditingController(
    text: _antiga?.fornecedor ?? '',
  );
  late final _total = TextEditingController(
    text: _antiga == null ? '' : valorParaCampo(_antiga.total),
  );
  late final _observacao = TextEditingController(
    text: _antiga?.observacao ?? '',
  );
  late final List<_Linha> _linhas = _antiga == null
      ? [_Linha()]
      : [
          for (final i in _antiga.itens)
            _Linha(
              produtoId: i.produtoId,
              produtoNome: i.produtoNome,
              qtd: i.quantidade,
              custo: i.custoUnitario,
            ),
        ];

  /// Produtos que já estavam na nota (podem continuar mesmo desativados).
  late final Set<String> _originais = {
    for (final i in _antiga?.itens ?? const <ItemNotaEntrada>[]) i.produtoId,
  };

  @override
  void dispose() {
    for (final c in [_numero, _fornecedor, _total, _observacao]) {
      c.dispose();
    }
    for (final l in _linhas) {
      l.dispose();
    }
    super.dispose();
  }

  double get _somaItens {
    var soma = 0.0;
    for (final l in _linhas) {
      final q = int.tryParse(l.quantidade.text.trim()) ?? 0;
      final c = lerValor(l.custo.text) ?? 0;
      soma += (q * c * 100).roundToDouble() / 100;
    }
    return soma;
  }

  Future<void> _escolherData() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _data = d);
  }

  Future<void> _escolherProduto(_Linha linha) async {
    final ativos = Dados.produtosAtivos;
    final inativos = Dados.produtos.value.where((p) => !p.ativo);
    final p = await selecionar<Produto>(
      context,
      titulo: 'Buscar produto',
      itens: [...ativos, ...inativos],
      textoBusca: (p) => '${p.nome} ${p.codigo} ${p.categoria}',
      habilitado: (p) => p.ativo || _originais.contains(p.id),
      itemBuilder: (p) => ListTile(
        leading: FotoProduto(foto: p.foto, nome: p.nome, tamanho: 40),
        title: Text(p.ativo ? p.nome : '${p.nome} — desativado'),
        subtitle: Text(
          '${p.codigo.isEmpty ? '' : '${p.codigo} · '}(saldo ${p.estoque})',
        ),
        trailing: Text('custo ${formatarMoeda(p.custo)}'),
      ),
    );
    if (p == null) return;
    setState(() {
      linha.produtoId = p.id;
      linha.produtoNome = p.nome;
      linha.custo.text = custoParaCampo(p.custo);
    });
  }

  void _salvar() {
    final itens = <ItemNotaEntrada>[];
    for (final l in _linhas) {
      final q = int.tryParse(l.quantidade.text.trim()) ?? 0;
      if (l.produtoId == null || q <= 0) {
        mostrarErro(
          context,
          const RegraException(
            'Selecione o produto e informe uma quantidade maior que zero.',
          ),
        );
        return;
      }
      final textoCusto = l.custo.text.trim();
      final custo = textoCusto.isEmpty ? 0.0 : lerValor(textoCusto);
      if (custo == null || custo < 0 || custo > 99999999.9999) {
        mostrarErro(
          context,
          RegraException('${l.produtoNome}: custo unitário inválido.'),
        );
        return;
      }
      itens.add(
        ItemNotaEntrada(
          produtoId: l.produtoId!,
          produtoNome: l.produtoNome,
          quantidade: q,
          custoUnitario: (custo * 10000).round() / 10000,
        ),
      );
    }
    final textoTotal = _total.text.trim();
    final total = textoTotal.isEmpty ? 0.0 : lerValor(textoTotal);
    if (total == null || total < 0) {
      mostrarErro(
        context,
        const RegraException('Informe um valor total válido (ou deixe 0).'),
      );
      return;
    }

    String? id;
    final ok = executar(
      context,
      () => id = _repo.salvar(
        antiga: _antiga,
        dataEntrada: _data,
        numero: _numero.text,
        fornecedor: _fornecedor.text,
        totalInformado: (total * 100).round() / 100,
        observacao: _observacao.text,
        itens: itens,
        produtos: Dados.produtosPorId,
      ),
      sucesso: _antiga == null
          ? 'Nota criada e produtos adicionados ao estoque.'
          : 'Nota alterada e estoque reconciliado com as diferenças.',
    );
    if (!ok || id == null) return;
    if (widget.abrirNotaAoSalvar) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => NotaEntradaDetalhePage(id: id!)),
      );
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    const decimal = TextInputType.numberWithOptions(decimal: true);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _antiga == null
              ? 'Nova nota de entrada'
              : 'Editar nota #${_antiga.id.length > 8 ? _antiga.id.substring(0, 8).toUpperCase() : _antiga.id}',
        ),
      ),
      body: LarguraMaxima(
        largura: 760,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_antiga != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Ao salvar, o estoque é reconciliado somente com as '
                  'diferenças entre as quantidades antigas e as novas.',
                  style: t.bodySmall,
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Data da entrada *',
                    ),
                    child: InkWell(
                      onTap: _escolherData,
                      child: Row(
                        children: [
                          Expanded(child: Text(_dia.format(_data))),
                          const Icon(Icons.calendar_today, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _numero,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      labelText: 'Número da nota',
                    ),
                  ),
                ),
              ],
            ),
            TextField(
              controller: _fornecedor,
              maxLength: 160,
              decoration: const InputDecoration(labelText: 'Fornecedor'),
            ),
            TextField(
              controller: _total,
              keyboardType: decimal,
              decoration: InputDecoration(
                labelText: 'Valor total da nota',
                prefixText: 'R\$ ',
                helperText:
                    'Vazio ou 0 usa a soma dos itens (${formatarMoeda(_somaItens)})',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _observacao,
              maxLength: 255,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Observações'),
            ),
            const SizedBox(height: 8),
            Text('Produtos recebidos', style: t.titleMedium),
            const SizedBox(height: 8),
            for (final (i, l) in _linhas.indexed) _linha(i, l),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _linhas.add(_Linha())),
                icon: const Icon(Icons.add),
                label: const Text('Adicionar produto'),
              ),
            ),
            const Divider(),
            Text(
              'Soma dos itens: ${formatarMoeda(_somaItens)}',
              textAlign: TextAlign.end,
              style: t.titleSmall,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _salvar,
              icon: const Icon(Icons.check),
              label: Text(
                _antiga == null
                    ? 'Salvar nota e dar entrada no estoque'
                    : 'Salvar alterações',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _linha(int indice, _Linha l) {
    final produto = l.produtoId == null
        ? null
        : Dados.produtosPorId[l.produtoId];
    final podeRemover = _linhas.length > 1;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _escolherProduto(l),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.inventory_2_outlined, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l.produtoId == null
                                  ? 'Selecionar produto'
                                  : [
                                      l.produtoNome,
                                      if (produto != null && !produto.ativo)
                                        '— desativado',
                                      if (produto != null)
                                        '(saldo ${produto.estoque})',
                                    ].join(' '),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: l.produtoId == null
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Remover linha',
                  onPressed: podeRemover
                      ? () => setState(() => _linhas.removeAt(indice).dispose())
                      : null,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: l.quantidade,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(7),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Quantidade',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: l.custo,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Custo unitário',
                        prefixText: 'R\$ ',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
