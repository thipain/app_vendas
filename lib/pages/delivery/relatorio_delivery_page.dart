import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/contato.dart';
import '../../core/formatters.dart';
import '../../data/config_repository.dart';
import '../../data/dados.dart';
import '../../data/loja_online_repository.dart';
import '../../data/pedido_online_repository.dart';
import '../../data/pedido_repository.dart';
import '../../models/cupom.dart';
import '../../models/pedido.dart';
import '../../models/pedido_online.dart';
import '../../models/resumo_delivery.dart';
import '../../widgets/filtro_periodo.dart';
import '../../widgets/largura_maxima.dart';
import '../inicio/comum.dart';

/// Relatório do delivery (canais, bairros, motoboys, tempos) e clientes
/// (quem mais compra e quem sumiu, com convite pelo WhatsApp).
class RelatorioDeliveryPage extends StatelessWidget {
  const RelatorioDeliveryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 2,
      child: Scaffold(
        body: Column(
          children: [
            TabBar(
              tabs: [
                Tab(icon: Icon(Icons.insights_outlined), text: 'Resumo'),
                Tab(icon: Icon(Icons.people_outline), text: 'Clientes'),
              ],
            ),
            Expanded(child: TabBarView(children: [_Resumo(), _Clientes()])),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _Resumo extends StatefulWidget {
  const _Resumo();

  @override
  State<_Resumo> createState() => _ResumoState();
}

class _ResumoState extends State<_Resumo> {
  late Periodo _periodo;
  late Stream<List<Pedido>> _pedidos;
  late Stream<List<PedidoOnline>> _online;

  @override
  void initState() {
    super.initState();
    _definir(Periodo.mesAtual());
  }

  void _definir(Periodo p) {
    _periodo = p;
    _pedidos = PedidoRepository().watchPeriodo(p.inicio, p.fim);
    _online = PedidoOnlineRepository().watchPeriodo(p.inicio, p.fim);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PedidoOnline>>(
      stream: _online,
      builder: (context, so) => StreamBuilder<List<Pedido>>(
        stream: _pedidos,
        builder: (context, s) {
          final recusados = (so.data ?? const [])
              .where((p) => p.status == PedidoOnline.recusado)
              .length;
          final r = s.hasData
              ? ResumoDelivery.de(s.data!, recusadosOnline: recusados)
              : null;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              LarguraMaxima(
                largura: 1100,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FiltroPeriodo(
                        periodo: _periodo,
                        onChanged: (p) => setState(() => _definir(p)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Pedidos registrados no período. Valores e grupos '
                      'contam só os pedidos concluídos.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    if (s.hasError)
                      EstadoVazio(
                        icone: Icons.error_outline,
                        titulo: 'Não foi possível carregar os pedidos',
                        mensagem: '${s.error}',
                      )
                    else if (r == null)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (r.registrados == 0 && r.recusadosOnline == 0)
                      const EstadoVazio(
                        icone: Icons.delivery_dining_outlined,
                        titulo: 'Nenhum pedido de delivery no período',
                      )
                    else
                      ..._conteudo(context, r),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _conteudo(BuildContext context, ResumoDelivery r) {
    return [
      GradeKpi(
        larguraMinima: 200,
        children: [
          KpiCard(
            titulo: 'Pedidos concluídos',
            valor: '${r.concluidos}',
            subtitulo:
                '${r.registrados} registrados · ${r.cancelados} cancelados'
                '${r.recusadosOnline > 0 ? ' · ${r.recusadosOnline} recusados online' : ''}',
            icone: Icons.delivery_dining_outlined,
          ),
          KpiCard(
            titulo: 'Faturamento do delivery',
            valor: formatarMoeda(r.faturamento),
            subtitulo: 'ticket médio ${formatarMoeda(r.ticketMedio)}',
            icone: Icons.payments_outlined,
          ),
          KpiCard(
            titulo: 'Taxas de entrega',
            valor: formatarMoeda(r.taxas),
            subtitulo: r.descontos > 0
                ? 'cupons: - ${formatarMoeda(r.descontos)}'
                : 'cobradas dos clientes',
            icone: Icons.local_shipping_outlined,
          ),
          KpiCard(
            titulo: 'Tempo médio até entregar',
            valor: formatarMinutos(r.mediaTotal),
            subtitulo:
                'preparo ${formatarMinutos(r.mediaPreparo)} · '
                'rua ${formatarMinutos(r.mediaEntrega)}',
            icone: Icons.timer_outlined,
          ),
        ],
      ),
      const TituloSecao('Por canal'),
      _Tabela(
        colunas: const ['Canal', 'Pedidos', 'Total'],
        linhas: [
          for (final g in r.canais)
            [g.nome, '${g.pedidos}', formatarMoeda(g.total)],
        ],
      ),
      const TituloSecao('Motoboys'),
      _Tabela(
        colunas: const ['Motoboy', 'Entregas', 'Valor levado', 'Tempo na rua'],
        linhas: [
          for (final g in r.motoboys)
            [
              g.nome.isEmpty ? 'Sem nome' : g.nome,
              '${g.pedidos}',
              formatarMoeda(g.total),
              formatarMinutos(g.mediaEntrega),
            ],
        ],
        vazio: 'Nenhuma entrega com motoboy no período.',
      ),
      const TituloSecao('Bairros que mais pedem'),
      _Tabela(
        colunas: const ['Bairro', 'Pedidos', 'Total'],
        linhas: [
          for (final g in r.bairros.take(15))
            [g.nome, '${g.pedidos}', formatarMoeda(g.total)],
        ],
      ),
      const TituloSecao('Formas de pagamento'),
      _Tabela(
        colunas: const ['Forma', 'Pedidos', 'Total'],
        linhas: [
          for (final g in r.formas)
            [g.nome, '${g.pedidos}', formatarMoeda(g.total)],
        ],
      ),
      const SizedBox(height: 24),
    ];
  }
}

class _Tabela extends StatelessWidget {
  final List<String> colunas;
  final List<List<String>> linhas;
  final String vazio;

  const _Tabela({
    required this.colunas,
    required this.linhas,
    this.vazio = 'Nada no período.',
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (linhas.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(vazio, style: t.textTheme.bodySmall),
        ),
      );
    }
    Widget celula(String s, int i, {TextStyle? estilo}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        s,
        style: estilo,
        textAlign: i == 0 ? TextAlign.left : TextAlign.right,
      ),
    );
    return Card(
      margin: EdgeInsets.zero,
      child: Table(
        columnWidths: const {0: FlexColumnWidth(2)},
        children: [
          TableRow(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: t.colorScheme.outlineVariant),
              ),
            ),
            children: [
              for (final (i, c) in colunas.indexed)
                celula(c, i, estilo: t.textTheme.labelLarge),
            ],
          ),
          for (final l in linhas)
            TableRow(children: [for (final (i, c) in l.indexed) celula(c, i)]),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _Clientes extends StatefulWidget {
  const _Clientes();

  @override
  State<_Clientes> createState() => _ClientesState();
}

class _ClientesState extends State<_Clientes> {
  static const _janelas = {
    90: 'Últimos 90 dias',
    180: 'Últimos 6 meses',
    365: 'Último ano',
  };
  static final _data = DateFormat('dd/MM/yyyy');

  int _dias = 180;
  bool _soSumidos = false;
  int _diasSumido = 30;
  String? _cupom;
  late Stream<List<Pedido>> _stream = _carregar();

  Stream<List<Pedido>> _carregar() {
    final agora = DateTime.now();
    final inicio = DateTime(agora.year, agora.month, agora.day - _dias);
    return PedidoRepository().watchPeriodo(
      inicio,
      agora.add(const Duration(days: 1)),
    );
  }

  String _mensagem(ClienteDelivery c) {
    final loja = ConfigRepository.atual.value;
    final b = StringBuffer(
      'Oi, ${primeiroNome(c.nome)}! Aqui é da ${loja.nomeLoja}. ',
    );
    b.write('Faz um tempinho que você não pede com a gente. ');
    final cupom = Dados.cupons.value
        .where((x) => x.codigo == _cupom)
        .firstOrNull;
    if (cupom != null) {
      b.write('Use o cupom ${cupom.codigo} e ganhe ${cupom.resumo}');
      if (cupom.minimo > 0) {
        b.write(' em pedidos a partir de ${formatarMoeda(cupom.minimo)}');
      }
      b.write('. ');
    }
    if (loja.lojaOnlineAtiva && loja.slug.isNotEmpty) {
      b.write('Peça pelo link: ${LojaOnlineRepository.linkDaLoja(loja.slug)}');
    }
    return b.toString().trim();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cuponsAtivos = Dados.cupons.value.where((c) => c.ativo).toList();
    return StreamBuilder<List<Pedido>>(
      stream: _stream,
      builder: (context, s) {
        final agora = DateTime.now();
        final todos = s.hasData ? ClienteDelivery.agrupar(s.data!) : null;
        final lista = todos
            ?.where((c) => !_soSumidos || c.diasSemPedir(agora) >= _diasSumido)
            .toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            LarguraMaxima(
              largura: 900,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      DropdownButton<int>(
                        value: _dias,
                        items: [
                          for (final e in _janelas.entries)
                            DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ),
                        ],
                        onChanged: (v) => setState(() {
                          _dias = v ?? _dias;
                          _stream = _carregar();
                        }),
                      ),
                      FilterChip(
                        label: Text('Sumidos há $_diasSumido+ dias'),
                        selected: _soSumidos,
                        onSelected: (v) => setState(() => _soSumidos = v),
                      ),
                      if (_soSumidos)
                        DropdownButton<int>(
                          value: _diasSumido,
                          items: const [
                            DropdownMenuItem(value: 15, child: Text('15 dias')),
                            DropdownMenuItem(value: 30, child: Text('30 dias')),
                            DropdownMenuItem(value: 60, child: Text('60 dias')),
                          ],
                          onChanged: (v) =>
                              setState(() => _diasSumido = v ?? _diasSumido),
                        ),
                      if (cuponsAtivos.isNotEmpty)
                        DropdownButton<String?>(
                          value: _cupom,
                          hint: const Text('Cupom na mensagem'),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Sem cupom na mensagem'),
                            ),
                            for (final Cupom c in cuponsAtivos)
                              DropdownMenuItem<String?>(
                                value: c.codigo,
                                child: Text('Cupom ${c.codigo}'),
                              ),
                          ],
                          onChanged: (v) => setState(() => _cupom = v),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Clientes dos pedidos de delivery concluídos, juntados '
                    'pelo telefone e ordenados por quem mais gastou.',
                    style: t.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  if (s.hasError)
                    EstadoVazio(
                      icone: Icons.error_outline,
                      titulo: 'Não foi possível carregar os pedidos',
                      mensagem: '${s.error}',
                    )
                  else if (lista == null)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (lista.isEmpty)
                    EstadoVazio(
                      icone: Icons.people_outline,
                      titulo: _soSumidos
                          ? 'Nenhum cliente sumido'
                          : 'Nenhum cliente no período',
                    )
                  else
                    Card(
                      margin: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (final (i, c) in lista.indexed)
                            ListTile(
                              leading: CircleAvatar(child: Text('${i + 1}')),
                              title: Text(c.nome),
                              subtitle: Text(
                                '${c.pedidos} pedido(s) · '
                                '${formatarMoeda(c.total)} · '
                                'último em ${_data.format(c.ultimoPedido)} '
                                '(${c.diasSemPedir(agora)} dias)'
                                '${c.bairro.isEmpty ? '' : '\n${c.bairro}'}',
                              ),
                              isThreeLine: c.bairro.isNotEmpty,
                              trailing: IconButton(
                                tooltip: 'Chamar no WhatsApp',
                                icon: const Icon(Icons.chat_outlined),
                                onPressed: () => abrirWhatsApp(
                                  context,
                                  c.telefone,
                                  mensagem: _mensagem(c),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
