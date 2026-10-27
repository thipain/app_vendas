import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/formatters.dart';
import '../../data/caixa_repository.dart';
import '../../data/dados.dart';
import '../../models/caixa.dart';
import '../../widgets/filtro_periodo.dart';
import '../../widgets/largura_maxima.dart';
import '../../widgets/mensagens.dart';
import '../../widgets/pendente_icon.dart';

/// Abertura e fechamento do caixa, suprimentos, sangrias e o histórico de
/// fechamentos. Só existe um caixa aberto por vez na loja.
class CaixaPage extends StatefulWidget {
  const CaixaPage({super.key});

  @override
  State<CaixaPage> createState() => _CaixaPageState();
}

class _CaixaPageState extends State<CaixaPage> {
  final _repo = CaixaRepository();
  late final _ultimos = _repo.watchUltimos(limite: 30);
  Stream<List<MovimentoCaixa>>? _movimentos;
  String? _caixaDosMovimentos;

  static final _hora = DateFormat('HH:mm:ss');
  static final _diaHora = DateFormat('dd/MM HH:mm');

  Stream<List<MovimentoCaixa>> _streamMovimentos(String caixaId) {
    if (_caixaDosMovimentos != caixaId || _movimentos == null) {
      _caixaDosMovimentos = caixaId;
      _movimentos = _repo.watchMovimentos(caixaId);
    }
    return _movimentos!;
  }

  // ---------------------------------------------------------------- ações

  Future<void> _abrir() async {
    final valor = TextEditingController(text: '0,00');
    final obs = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Abrir caixa'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: valor,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Valor inicial em dinheiro',
                  prefixText: 'R\$ ',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: obs,
                maxLength: 255,
                decoration: const InputDecoration(labelText: 'Observações'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () {
              final v = lerValor(valor.text) ?? -1;
              final ok = executar(
                ctx,
                () => _repo.abrir(
                  atual: Dados.caixaAberto.value,
                  valor: v,
                  observacao: obs.text,
                ),
                sucesso: 'Caixa aberto com sucesso.',
              );
              if (ok) Navigator.pop(ctx);
            },
            child: const Text('Abrir caixa'),
          ),
        ],
      ),
    );
  }

  Future<void> _movimentar(
    Caixa caixa,
    double saldo, {
    required bool sangria,
  }) async {
    final valor = TextEditingController();
    final motivo = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(sangria ? 'Sangria' : 'Suprimento'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (sangria)
                Text(
                  'Saldo disponível: ${formatarMoeda(saldo)}',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              TextField(
                controller: valor,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Valor',
                  prefixText: 'R\$ ',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: motivo,
                maxLength: 255,
                decoration: const InputDecoration(labelText: 'Motivo'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () {
              final ok = executar(
                ctx,
                () => _repo.movimentar(
                  caixa: Dados.caixaAberto.value,
                  sangria: sangria,
                  valor: lerValor(valor.text) ?? 0,
                  motivo: motivo.text,
                  saldoAtual: saldo,
                ),
                sucesso: sangria
                    ? 'Sangria registrada.'
                    : 'Suprimento registrado.',
              );
              if (ok) Navigator.pop(ctx);
            },
            child: Text(sangria ? 'Registrar sangria' : 'Registrar suprimento'),
          ),
        ],
      ),
    );
  }

  Future<void> _fechar(Caixa caixa, double esperado) async {
    final contado = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Fechar caixa #${caixa.codigo}'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Saldo esperado: ${formatarMoeda(esperado)}',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contado,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Valor contado no caixa',
                  prefixText: 'R\$ ',
                ),
              ),
              const SizedBox(height: 12),
              ListenableBuilder(
                listenable: contado,
                builder: (_, _) {
                  final c = lerValor(contado.text);
                  if (c == null) return const SizedBox.shrink();
                  final dif = ((c - esperado) * 100).round() / 100;
                  return Text(
                    'Diferença: ${formatarMoeda(dif)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: dif == 0
                          ? Colors.green.shade700
                          : Theme.of(ctx).colorScheme.error,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () {
              double dif = 0;
              final ok = executar(ctx, () {
                if (Dados.caixaAberto.value?.id != caixa.id) {
                  throw StateError('O caixa já foi fechado por outro usuário.');
                }
                final c = lerValor(contado.text);
                if (c == null) throw StateError('Informe um valor válido.');
                dif = _repo.fechar(caixa, contado: c, esperado: esperado);
              });
              if (ok) {
                Navigator.pop(ctx);
                avisar(
                  context,
                  'Caixa fechado. Diferença: ${formatarMoeda(dif)}',
                );
              }
            },
            child: const Text('Fechar caixa'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- tela

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ValueListenableBuilder<Caixa?>(
        valueListenable: Dados.caixaAberto,
        builder: (context, caixa, _) => LarguraMaxima(
          largura: 1100,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _cabecalho(caixa),
              const SizedBox(height: 16),
              if (caixa == null)
                const Card(
                  child: EstadoVazio(
                    icone: Icons.point_of_sale_outlined,
                    titulo: 'Caixa fechado',
                    mensagem:
                        'Abra um caixa para iniciar as operações '
                        'financeiras do turno.',
                  ),
                )
              else
                _sessaoAberta(caixa),
              const SizedBox(height: 24),
              Text(
                'Últimos fechamentos',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              _ultimosFechamentos(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cabecalho(Caixa? caixa) {
    final t = Theme.of(context);
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        Text(
          'Somente pagamentos em dinheiro movimentam a gaveta.',
          style: t.textTheme.bodyMedium,
        ),
        if (caixa != null)
          Chip(
            avatar: Icon(Icons.circle, size: 10, color: Colors.green.shade600),
            label: Text('Caixa #${caixa.codigo} aberto'),
          )
        else
          FilledButton.icon(
            icon: const Icon(Icons.lock_open),
            label: const Text('Abrir caixa'),
            onPressed: _abrir,
          ),
      ],
    );
  }

  Widget _sessaoAberta(Caixa caixa) {
    return StreamBuilder<List<MovimentoCaixa>>(
      stream: _streamMovimentos(caixa.id),
      builder: (context, snap) {
        final movimentos = snap.data ?? const <MovimentoCaixa>[];
        final saldo = snap.hasData ? saldoCaixa(movimentos) : null;
        final desktop = MediaQuery.sizeOf(context).width >= larguraDesktop;
        final t = Theme.of(context);
        final stats = [
          _Indicador(
            titulo: 'Valor inicial',
            valor: formatarMoeda(caixa.valorAbertura),
          ),
          _Indicador(
            titulo: 'Saldo esperado',
            valor: saldo == null ? '...' : formatarMoeda(saldo),
            destaque: true,
          ),
          _Indicador(
            titulo: 'Aberto por',
            valor: caixa.abertoPorNome,
            detalhe: formatarDataHora(caixa.abertoEm),
          ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (desktop)
              Row(children: [for (final s in stats) Expanded(child: s)])
            else
              ...stats,
            if (caixa.observacao.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Observações: ${caixa.observacao}',
                  style: t.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Suprimento'),
                  onPressed: saldo == null
                      ? null
                      : () => _movimentar(caixa, saldo, sangria: false),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.remove),
                  label: const Text('Sangria'),
                  onPressed: saldo == null
                      ? null
                      : () => _movimentar(caixa, saldo, sangria: true),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Fechar caixa'),
                  onPressed: saldo == null ? null : () => _fechar(caixa, saldo),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Movimentações do caixa', style: t.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (snap.hasError)
              Text('Erro ao carregar: ${snap.error}')
            else if (!snap.hasData)
              const Center(child: CircularProgressIndicator())
            else if (desktop)
              _tabelaMovimentos(movimentos)
            else
              Card(
                child: Column(
                  children: [
                    for (final m in movimentos)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          _iconeMovimento(m.tipo),
                          color: m.efeito < 0 ? t.colorScheme.error : null,
                        ),
                        title: Text(
                          m.descricao.isEmpty ? m.tipoNome : m.descricao,
                        ),
                        subtitle: Text(
                          '${m.tipoNome} · ${_hora.format(m.data)} · ${m.usuarioNome}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PendenteIcon(pendente: m.pendente),
                            const SizedBox(width: 4),
                            Text(formatarMoeda(m.valor)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  static IconData _iconeMovimento(String tipo) => switch (tipo) {
    MovimentoCaixa.abertura => Icons.lock_open,
    MovimentoCaixa.venda => Icons.shopping_cart_outlined,
    MovimentoCaixa.suprimento => Icons.add_circle_outline,
    MovimentoCaixa.sangria => Icons.remove_circle_outline,
    MovimentoCaixa.estorno => Icons.undo,
    _ => Icons.lock_outline,
  };

  Widget _tabelaMovimentos(List<MovimentoCaixa> movimentos) {
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Hora')),
            DataColumn(label: Text('Tipo')),
            DataColumn(label: Text('Descrição')),
            DataColumn(label: Text('Responsável')),
            DataColumn(label: Text('Valor'), numeric: true),
          ],
          rows: [
            for (final m in movimentos)
              DataRow(
                cells: [
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_hora.format(m.data)),
                        const SizedBox(width: 4),
                        PendenteIcon(pendente: m.pendente),
                      ],
                    ),
                  ),
                  DataCell(Text(m.tipoNome)),
                  DataCell(Text(m.descricao)),
                  DataCell(Text(m.usuarioNome)),
                  DataCell(Text(formatarMoeda(m.valor))),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _ultimosFechamentos() {
    return StreamBuilder<List<Caixa>>(
      stream: _ultimos,
      builder: (context, snap) {
        if (snap.hasError) return Text('Erro ao carregar: ${snap.error}');
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final lista = snap.data!;
        if (lista.isEmpty) {
          return const Card(
            child: EstadoVazio(
              icone: Icons.history,
              titulo: 'Nenhum caixa registrado',
            ),
          );
        }
        final t = Theme.of(context);
        final desktop = MediaQuery.sizeOf(context).width >= larguraDesktop;
        Widget diferenca(Caixa c) {
          if (c.isAberto || c.diferenca == null) return const Text('—');
          return Text(
            formatarMoeda(c.diferenca!),
            style: TextStyle(
              color: c.diferenca != 0 ? t.colorScheme.error : null,
              fontWeight: c.diferenca != 0 ? FontWeight.bold : null,
            ),
          );
        }

        String fechamento(Caixa c) =>
            c.isAberto ? 'Em aberto' : formatarMoeda(c.valorFechamento ?? 0);

        if (desktop) {
          return Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Caixa')),
                  DataColumn(label: Text('Responsável')),
                  DataColumn(label: Text('Abertura')),
                  DataColumn(label: Text('Fechamento')),
                  DataColumn(label: Text('Diferença'), numeric: true),
                ],
                rows: [
                  for (final c in lista)
                    DataRow(
                      cells: [
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('#${c.codigo}'),
                              const SizedBox(width: 4),
                              PendenteIcon(pendente: c.pendente),
                            ],
                          ),
                        ),
                        DataCell(Text(c.abertoPorNome)),
                        DataCell(
                          Text(
                            '${formatarMoeda(c.valorAbertura)}\n'
                            '${_diaHora.format(c.abertoEm)}',
                          ),
                        ),
                        DataCell(
                          Text(
                            c.isAberto || c.fechadoEm == null
                                ? fechamento(c)
                                : '${fechamento(c)}\n${_diaHora.format(c.fechadoEm!)}',
                          ),
                        ),
                        DataCell(diferenca(c)),
                      ],
                    ),
                ],
              ),
            ),
          );
        }
        return Card(
          child: Column(
            children: [
              for (final c in lista)
                ListTile(
                  title: Row(
                    children: [
                      Text('Caixa #${c.codigo}'),
                      const SizedBox(width: 6),
                      PendenteIcon(pendente: c.pendente),
                    ],
                  ),
                  subtitle: Text(
                    '${c.abertoPorNome}\nAbertura ${formatarMoeda(c.valorAbertura)} · '
                    '${_diaHora.format(c.abertoEm)}\nFechamento: ${fechamento(c)}',
                  ),
                  isThreeLine: true,
                  trailing: diferenca(c),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Indicador extends StatelessWidget {
  final String titulo;
  final String valor;
  final String? detalhe;
  final bool destaque;

  const _Indicador({
    required this.titulo,
    required this.valor,
    this.detalhe,
    this.destaque = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      color: destaque ? t.colorScheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: t.textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(
              valor,
              style: t.textTheme.titleLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (detalhe != null) Text(detalhe!, style: t.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
