import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/formatters.dart';
import '../../data/cupom_repository.dart';
import '../../data/dados.dart';
import '../../models/cupom.dart';
import '../../widgets/confirmar.dart';
import '../../widgets/largura_maxima.dart';
import '../../widgets/mensagens.dart';

/// Cupons de desconto da loja online: o cliente digita o código na página e
/// o desconto vale sobre os produtos (a taxa de entrega continua).
class CuponsPage extends StatelessWidget {
  const CuponsPage({super.key});

  static final _data = DateFormat('dd/MM/yyyy');

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Novo cupom'),
        onPressed: () => editarCupom(context),
      ),
      body: ValueListenableBuilder<List<Cupom>>(
        valueListenable: Dados.cupons,
        builder: (context, lista, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            LarguraMaxima(
              largura: 760,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'O cliente digita o código na loja online. O desconto vale '
                    'sobre os produtos (não sobre a taxa de entrega) e é '
                    'conferido de novo quando a loja aceita o pedido.',
                    style: t.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  if (lista.isEmpty)
                    const Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        leading: Icon(Icons.confirmation_number_outlined),
                        title: Text('Nenhum cupom criado'),
                        subtitle: Text(
                          'Ex.: BEMVINDO10 com 10% para o primeiro pedido.',
                        ),
                      ),
                    ),
                  for (final c in lista)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(
                          Icons.confirmation_number_outlined,
                          color: c.ativo ? t.colorScheme.primary : null,
                        ),
                        title: Text(
                          c.ativo ? c.codigo : '${c.codigo} — desativado',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          [
                            c.resumo,
                            if (c.minimo > 0)
                              'mínimo ${formatarMoeda(c.minimo)}',
                            if (c.validoAte != null)
                              'até ${_data.format(c.validoAte!)}',
                            '${c.usos} uso(s)',
                            if (c.descricao.isNotEmpty) c.descricao,
                          ].join(' · '),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Copiar código',
                              icon: const Icon(Icons.copy, size: 20),
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: c.codigo),
                                );
                                if (context.mounted) {
                                  avisar(context, 'Código copiado.');
                                }
                              },
                            ),
                            const Icon(Icons.edit_outlined),
                          ],
                        ),
                        onTap: () => editarCupom(context, cupom: c),
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

Future<void> editarCupom(BuildContext context, {Cupom? cupom}) async {
  final codigo = TextEditingController(text: cupom?.codigo);
  final valor = TextEditingController(
    text: cupom == null ? '' : valorParaCampo(cupom.quantia),
  );
  final minimo = TextEditingController(
    text: cupom == null || cupom.minimo == 0
        ? ''
        : valorParaCampo(cupom.minimo),
  );
  final descricao = TextEditingController(text: cupom?.descricao);
  var tipo = cupom?.tipo ?? Cupom.percentual;
  var ativo = cupom?.ativo ?? true;
  DateTime? validoAte = cupom?.validoAte;
  final dataFmt = DateFormat('dd/MM/yyyy');

  final acao = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(cupom == null ? 'Novo cupom' : 'Cupom ${cupom.codigo}'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: codigo,
                  enabled: cupom == null,
                  autofocus: cupom == null,
                  maxLength: 20,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Código *',
                    hintText: 'BEMVINDO10',
                  ),
                ),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: Cupom.percentual, label: Text('%')),
                    ButtonSegment(value: Cupom.valor, label: Text('R\$')),
                  ],
                  selected: {tipo},
                  onSelectionChanged: (s) => setState(() => tipo = s.first),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: valor,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: tipo == Cupom.percentual
                        ? 'Desconto (%) *'
                        : 'Desconto (R\$) *',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: minimo,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Pedido mínimo em produtos (R\$)',
                    helperText: 'Vazio = qualquer valor.',
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: Text(
                    validoAte == null
                        ? 'Sem prazo de validade'
                        : 'Vale até ${dataFmt.format(validoAte!)}',
                  ),
                  trailing: validoAte == null
                      ? null
                      : IconButton(
                          tooltip: 'Tirar o prazo',
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => validoAte = null),
                        ),
                  onTap: () async {
                    final hoje = DateTime.now();
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: validoAte ?? hoje,
                      firstDate: DateTime(hoje.year, hoje.month, hoje.day),
                      lastDate: DateTime(hoje.year + 3),
                    );
                    if (d != null) setState(() => validoAte = d);
                  },
                ),
                TextField(
                  controller: descricao,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Anotação interna',
                    hintText: 'Ex.: campanha do Instagram',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ativo'),
                  value: ativo,
                  onChanged: (v) => setState(() => ativo = v),
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (cupom != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'excluir'),
              child: const Text('Excluir'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'salvar'),
            child: const Text('Salvar'),
          ),
        ],
      ),
    ),
  );
  final dados = Cupom(
    codigo: codigo.text,
    tipo: tipo,
    quantia: lerValor(valor.text) ?? 0,
    minimo: lerValor(minimo.text) ?? 0,
    validoAte: validoAte,
    ativo: ativo,
    descricao: descricao.text,
  );
  for (final c in [codigo, valor, minimo, descricao]) {
    c.dispose();
  }
  if (!context.mounted || acao == null) return;
  final repo = CupomRepository();
  if (acao == 'excluir') {
    final ok = await confirmar(
      context,
      titulo: 'Excluir cupom ${cupom!.codigo}',
      mensagem:
          'O código para de funcionar na loja online. Pedidos já feitos '
          'continuam com o desconto.',
      confirmarTexto: 'Excluir',
    );
    if (ok && context.mounted) {
      executar(context, () => repo.excluir(cupom), sucesso: 'Cupom excluído.');
    }
    return;
  }
  executar(
    context,
    () => repo.salvar(dados, novo: cupom == null, todos: Dados.cupons.value),
    sucesso: cupom == null ? 'Cupom criado.' : 'Cupom salvo.',
  );
}
