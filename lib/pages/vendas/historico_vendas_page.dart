import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/formatters.dart';
import '../../data/venda_repository.dart';
import '../../models/venda.dart';
import '../../widgets/filtro_periodo.dart';
import '../../widgets/largura_maxima.dart';
import '../../widgets/pendente_icon.dart';
import '../../widgets/seletor.dart';
import '../shell/app_shell.dart';
import 'venda_detalhe_page.dart';

/// Histórico de vendas com filtros de período, situação e busca; permite
/// reimprimir, editar a nota e estornar.
class HistoricoVendasPage extends StatefulWidget {
  const HistoricoVendasPage({super.key});

  @override
  State<HistoricoVendasPage> createState() => _HistoricoVendasPageState();
}

class _HistoricoVendasPageState extends State<HistoricoVendasPage> {
  static const _porPagina = 50;
  static final _data = DateFormat('dd/MM/yyyy');
  static final _hora = DateFormat('HH:mm:ss');

  final _repo = VendaRepository();
  Periodo _periodo = Periodo.hoje();
  late Stream<List<Venda>> _stream = _criarStream();
  String _status = '';
  String _busca = '';
  int _limite = _porPagina;

  Stream<List<Venda>> _criarStream() =>
      _repo.watchPeriodo(_periodo.inicio, _periodo.fim);

  bool _combina(Venda v) {
    if (_status.isNotEmpty && v.status != _status) return false;
    if (_busca.isEmpty) return true;
    final alvo = normalizarBusca(
      [
        v.id,
        v.codigo,
        v.vendedorNome,
        v.formaPagamento,
        v.comandaNome ?? '',
        v.clienteNome ?? '',
      ].join(' '),
    );
    return alvo.contains(_busca);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LarguraMaxima(
        largura: 1000,
        child: Column(
          children: [
            _filtros(),
            Expanded(
              child: StreamBuilder<List<Venda>>(
                stream: _stream,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(
                      child: Text('Erro ao carregar: ${snap.error}'),
                    );
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final lista = snap.data!.where(_combina).toList();
                  final totalConcluidas = lista
                      .where((v) => !v.isCancelada)
                      .fold<int>(0, (s, v) => s + (v.total * 100).round());
                  final visiveis = lista.take(_limite).toList();
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          '${lista.length} registros · '
                          '${formatarMoeda(totalConcluidas / 100)}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (lista.isEmpty)
                        const EstadoVazio(
                          icone: Icons.receipt_long_outlined,
                          titulo: 'Nenhuma venda encontrada',
                          mensagem: 'Altere o período ou os filtros.',
                        ),
                      for (final v in visiveis)
                        _VendaCard(
                          venda: v,
                          abrirModulo: (m) => AppShell.abrir(this.context, m),
                        ),
                      if (lista.length > visiveis.length)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Center(
                            child: OutlinedButton(
                              onPressed: () =>
                                  setState(() => _limite += _porPagina),
                              child: Text(
                                'Mostrar mais (${visiveis.length} de ${lista.length})',
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filtros() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FiltroPeriodo(
            periodo: _periodo,
            onChanged: (p) => setState(() {
              _periodo = p;
              _stream = _criarStream();
              _limite = _porPagina;
            }),
          ),
          DropdownButton<String>(
            value: _status,
            items: const [
              DropdownMenuItem(value: '', child: Text('Todas')),
              DropdownMenuItem(
                value: Venda.concluida,
                child: Text('Concluídas'),
              ),
              DropdownMenuItem(
                value: Venda.cancelada,
                child: Text('Canceladas'),
              ),
            ],
            onChanged: (s) => setState(() {
              _status = s ?? '';
              _limite = _porPagina;
            }),
          ),
          SizedBox(
            width: 300,
            child: TextField(
              maxLength: 100,
              decoration: const InputDecoration(
                isDense: true,
                counterText: '',
                prefixIcon: Icon(Icons.search),
                hintText: 'Venda, vendedor, pagamento ou comanda',
              ),
              onChanged: (t) => setState(() {
                _busca = normalizarBusca(t.trim());
                _limite = _porPagina;
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _VendaCard extends StatelessWidget {
  final Venda venda;
  final void Function(String modulo) abrirModulo;
  const _VendaCard({required this.venda, required this.abrirModulo});

  @override
  Widget build(BuildContext context) {
    final v = venda;
    final t = Theme.of(context);
    final badge = v.isCancelada ? 'Cancelada' : v.pagamentoResumo;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        title: Row(
          children: [
            Flexible(
              child: Text(
                'Venda #${v.codigo}',
                style: v.isCancelada
                    ? const TextStyle(decoration: TextDecoration.lineThrough)
                    : null,
              ),
            ),
            const SizedBox(width: 6),
            PendenteIcon(pendente: v.pendente),
          ],
        ),
        subtitle: Text(
          '${v.comandaNome == null ? 'Venda direta' : 'Comanda ${v.comandaNome}'}\n'
          '${_HistoricoVendasPageState._data.format(v.data)} '
          '${_HistoricoVendasPageState._hora.format(v.data)} · ${v.vendedorNome}',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(formatarMoeda(v.total), style: t.textTheme.titleMedium),
            if (v.desconto > 0)
              Text(
                'Desconto ${formatarMoeda(v.desconto)}',
                style: t.textTheme.bodySmall,
              ),
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              decoration: BoxDecoration(
                color: v.isCancelada
                    ? t.colorScheme.errorContainer
                    : t.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                badge,
                style: t.textTheme.labelSmall?.copyWith(
                  color: v.isCancelada
                      ? t.colorScheme.onErrorContainer
                      : t.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DetalhesVenda(venda: v),
          const SizedBox(height: 12),
          AcoesVenda(venda: v, abrirModulo: abrirModulo),
        ],
      ),
    );
  }
}
