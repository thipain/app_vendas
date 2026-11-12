import 'package:flutter/material.dart';

import '../../core/dinheiro.dart';
import '../../core/formatters.dart';
import '../../data/alarme_online.dart';
import '../../data/config_repository.dart';
import '../../data/dados.dart';
import '../../data/loja_online_repository.dart';
import '../../data/pedido_repository.dart';
import '../../data/venda_repository.dart';
import '../../models/config_loja.dart';
import '../../models/pedido.dart';
import '../../models/pedido_online.dart';
import '../../models/venda.dart';
import '../../widgets/confirmar.dart';
import '../../widgets/largura_maxima.dart';
import '../../widgets/mensagens.dart';
import 'delivery_comum.dart';
import 'pedido_detalhe_page.dart';
import 'pedido_form_page.dart';
import 'pedido_online_widgets.dart';

/// Painel do delivery: pedidos em andamento separados por etapa (colunas no
/// PC, abas no celular) e o acerto do dinheiro com cada entregador.
class PedidosPage extends StatefulWidget {
  const PedidosPage({super.key});

  @override
  State<PedidosPage> createState() => _PedidosPageState();
}

class _PedidosPageState extends State<PedidosPage> {
  late final _stream = PedidoRepository().watchAtivos();

  static const _colunas = [
    (Pedido.novo, 'Novos', Icons.fiber_new_outlined),
    (Pedido.preparo, 'Em preparo', Icons.soup_kitchen_outlined),
    (Pedido.emRota, 'Em rota', Icons.two_wheeler),
    (Pedido.entregue, 'Entregues — acertar', Icons.point_of_sale),
  ];

  Future<void> _novo() async {
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const PedidoFormPage()),
    );
    if (id != null && mounted) _abrir(id);
  }

  void _abrir(String id) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => PedidoDetalhePage(pedidoId: id)),
    );
  }

  /// Conclui de uma vez os pedidos entregues por um entregador que não
  /// dependem de conferência (Pix não confirmado fica de fora).
  Future<void> _acertar(String nome, List<Pedido> pedidos) async {
    final prontos = pedidos.where((p) => !p.isPix || p.pixConfirmado).toList();
    final pendentes = pedidos.length - prontos.length;
    if (prontos.isEmpty) {
      avisar(context, 'Confirme os Pix desses pedidos antes do acerto.');
      return;
    }
    final dinheiro = prontos
        .where((p) => p.isDinheiro)
        .fold<int>(0, (s, p) => s + p.totalCentavos);
    final cartao = prontos
        .where((p) => p.isCartao)
        .fold<int>(0, (s, p) => s + p.totalCentavos);
    final ok = await confirmar(
      context,
      titulo: 'Acerto com $nome',
      mensagem:
          '${prontos.length} pedido(s) serão concluídos como combinado.\n\n'
          'Dinheiro a receber do entregador: '
          '${formatarMoeda(deCentavos(dinheiro))}\n'
          'Na maquininha: ${formatarMoeda(deCentavos(cartao))}'
          '${pendentes > 0 ? '\n\n$pendentes pedido(s) com Pix não confirmado ficam para depois.' : ''}'
          '\n\nSe algum cliente pagou de outro jeito, conclua esse pedido '
          'separadamente.',
      confirmarTexto: 'Concluir acerto',
    );
    if (!ok || !mounted) return;
    final repo = VendaRepository();
    var feitos = 0;
    try {
      for (final p in prontos) {
        repo.concluirPedido(
          pedido: p,
          caixa: Dados.caixaAberto.value,
          produtos: Dados.produtosPorId,
          forma: p.formaPagamento,
          recebidoEmDinheiro: p.isDinheiro ? (p.trocoPara ?? p.total) : null,
        );
        feitos++;
      }
      if (mounted) avisar(context, 'Acerto concluído: $feitos pedido(s).');
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Novo pedido'),
        onPressed: _novo,
      ),
      body: ValueListenableBuilder<ConfigLoja>(
        valueListenable: ConfigRepository.atual,
        builder: (context, config, _) => ValueListenableBuilder(
          valueListenable: AlarmeOnline.aguardando,
          builder: (context, online, _) {
            final comOnline = config.lojaOnlineAtiva || online.isNotEmpty;
            return Column(
              children: [
                if (config.lojaOnlineAtiva) const _BarraLojaOnline(),
                Expanded(child: _quadro(context, comOnline ? online : null)),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Colunas (PC) ou abas (celular). [online] null = loja online desligada.
  Widget _quadro(BuildContext context, List<PedidoOnline>? online) {
    final desktop = MediaQuery.sizeOf(context).width >= larguraDesktop;
    return StreamBuilder<List<Pedido>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Erro ao carregar: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final todos = snap.data!;
        final porStatus = {
          for (final (s, _, _) in _colunas)
            s: todos.where((p) => p.status == s).toList(),
        };
        final colunaOnline = online == null
            ? null
            : _ColunaOnline(
                pedidos: online,
                cabecalho: desktop,
                onAceito: _abrir,
              );
        if (desktop) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (colunaOnline != null) Expanded(child: colunaOnline),
              for (final (s, titulo, icone) in _colunas)
                Expanded(
                  child: _Coluna(
                    titulo: titulo,
                    icone: icone,
                    cor: corStatus(context, s),
                    pedidos: porStatus[s]!,
                    onAbrir: _abrir,
                    onAcertar: s == Pedido.entregue ? _acertar : null,
                  ),
                ),
            ],
          );
        }
        return DefaultTabController(
          length: _colunas.length + (colunaOnline == null ? 0 : 1),
          child: Column(
            children: [
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  if (online != null)
                    Tab(
                      icon: Badge(
                        isLabelVisible: online.isNotEmpty,
                        label: Text('${online.length}'),
                        child: const Icon(Icons.public),
                      ),
                      text: 'Online',
                    ),
                  for (final (s, titulo, icone) in _colunas)
                    Tab(
                      icon: Badge(
                        isLabelVisible: porStatus[s]!.isNotEmpty,
                        label: Text('${porStatus[s]!.length}'),
                        child: Icon(icone),
                      ),
                      text: titulo,
                    ),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    ?colunaOnline,
                    for (final (s, titulo, icone) in _colunas)
                      _Coluna(
                        titulo: titulo,
                        icone: icone,
                        cor: corStatus(context, s),
                        pedidos: porStatus[s]!,
                        onAbrir: _abrir,
                        onAcertar: s == Pedido.entregue ? _acertar : null,
                        cabecalho: false,
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Abrir/fechar a loja online e silenciar o alarme.
class _BarraLojaOnline extends StatelessWidget {
  const _BarraLojaOnline();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Material(
      color: t.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: StreamBuilder<bool>(
          stream: LojaOnlineRepository.watchAberta(),
          builder: (context, snap) {
            final aberta = snap.data ?? false;
            return Row(
              children: [
                Icon(
                  Icons.public,
                  color: aberta ? Colors.green.shade700 : t.colorScheme.outline,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    aberta
                        ? 'Loja online ABERTA — recebendo pedidos'
                        : 'Loja online fechada',
                    style: t.textTheme.titleSmall,
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: AlarmeOnline.silenciado,
                  builder: (context, mudo, _) => IconButton(
                    tooltip: mudo ? 'Ligar o alarme' : 'Silenciar o alarme',
                    icon: Icon(
                      mudo
                          ? Icons.notifications_off_outlined
                          : Icons.notifications_active_outlined,
                    ),
                    onPressed: () => AlarmeOnline.silenciado.value = !mudo,
                  ),
                ),
                Switch(
                  value: aberta,
                  onChanged: snap.hasData
                      ? (v) => executar(
                          context,
                          () => LojaOnlineRepository.definirAberta(v),
                          sucesso: v
                              ? 'Loja online aberta.'
                              : 'Loja online fechada.',
                        )
                      : null,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Pedidos da loja online esperando a loja aceitar ou recusar.
class _ColunaOnline extends StatelessWidget {
  final List<PedidoOnline> pedidos;
  final bool cabecalho;
  final ValueChanged<String> onAceito;

  const _ColunaOnline({
    required this.pedidos,
    required this.cabecalho,
    required this.onAceito,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cor = Colors.orange.shade800;
    return Container(
      margin: cabecalho ? const EdgeInsets.all(6) : EdgeInsets.zero,
      decoration: cabecalho
          ? BoxDecoration(
              color: pedidos.isEmpty
                  ? t.colorScheme.surfaceContainerLow
                  : cor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (cabecalho)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Row(
                children: [
                  Icon(Icons.public, color: cor, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Online — responder',
                      style: t.textTheme.titleSmall?.copyWith(color: cor),
                    ),
                  ),
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: cor.withValues(alpha: 0.15),
                    child: Text(
                      '${pedidos.length}',
                      style: t.textTheme.labelSmall?.copyWith(color: cor),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: pedidos.isEmpty
                ? Center(
                    child: Text(
                      'Nenhum pedido online esperando',
                      style: t.textTheme.bodySmall,
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
                    children: [
                      for (final p in pedidos)
                        CartaoPedidoOnline(pedido: p, onAceito: onAceito),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Coluna extends StatelessWidget {
  final String titulo;
  final IconData icone;
  final Color cor;
  final List<Pedido> pedidos;
  final ValueChanged<String> onAbrir;
  final Future<void> Function(String nome, List<Pedido>)? onAcertar;
  final bool cabecalho;

  const _Coluna({
    required this.titulo,
    required this.icone,
    required this.cor,
    required this.pedidos,
    required this.onAbrir,
    this.onAcertar,
    this.cabecalho = true,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final acertos = <String, List<Pedido>>{};
    if (onAcertar != null) {
      for (final p in pedidos) {
        acertos
            .putIfAbsent(
              p.entregadorNome.isEmpty ? 'Sem motoboy' : p.entregadorNome,
              () => [],
            )
            .add(p);
      }
    }
    return Container(
      margin: cabecalho ? const EdgeInsets.all(6) : EdgeInsets.zero,
      decoration: cabecalho
          ? BoxDecoration(
              color: t.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (cabecalho)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Row(
                children: [
                  Icon(icone, color: cor, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      titulo,
                      style: t.textTheme.titleSmall?.copyWith(color: cor),
                    ),
                  ),
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: cor.withValues(alpha: 0.15),
                    child: Text(
                      '${pedidos.length}',
                      style: t.textTheme.labelSmall?.copyWith(color: cor),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: pedidos.isEmpty
                ? Center(
                    child: Text('Nenhum pedido', style: t.textTheme.bodySmall),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
                    children: [
                      for (final e in acertos.entries)
                        _BotaoAcerto(
                          nome: e.key,
                          pedidos: e.value,
                          onAcertar: onAcertar!,
                        ),
                      for (final p in pedidos)
                        CartaoPedido(pedido: p, onTap: () => onAbrir(p.id)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _BotaoAcerto extends StatelessWidget {
  final String nome;
  final List<Pedido> pedidos;
  final Future<void> Function(String nome, List<Pedido>) onAcertar;

  const _BotaoAcerto({
    required this.nome,
    required this.pedidos,
    required this.onAcertar,
  });

  @override
  Widget build(BuildContext context) {
    final dinheiro = pedidos
        .where((p) => p.formaPagamento == FormaPagamento.dinheiro)
        .fold<int>(0, (s, p) => s + p.totalCentavos);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: ListTile(
        leading: const Icon(Icons.handshake_outlined),
        title: Text('Acertar com $nome'),
        subtitle: Text(
          '${pedidos.length} pedido(s) · '
          '${formatarMoeda(deCentavos(dinheiro))} em dinheiro',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => onAcertar(nome, pedidos),
      ),
    );
  }
}
