import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/contato.dart';
import '../../core/dinheiro.dart';
import '../../core/formatters.dart';
import '../../core/sessao.dart';
import '../../data/config_repository.dart';
import '../../data/pedido_repository.dart';
import '../../data/ponto_repository.dart';
import '../../models/pedido.dart';
import '../../widgets/largura_maxima.dart';
import '../../widgets/mensagens.dart';
import '../inicio/comum.dart';
import 'delivery_comum.dart';

/// Tela do entregador: entregas a fazer (com endereço, contato e o que
/// cobrar) e as já entregues que ainda precisam ser acertadas na loja.
class EntregasPage extends StatefulWidget {
  const EntregasPage({super.key});

  @override
  State<EntregasPage> createState() => _EntregasPageState();
}

class _EntregasPageState extends State<EntregasPage> {
  final _repo = PedidoRepository();
  late final _stream = _repo.watchDoEntregador(Sessao.instancia.atual.id);
  final _enviando = <String>{};

  static final _hora = DateFormat('HH:mm');

  Future<void> _entregar(Pedido p) async {
    var conferiu = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Entregar pedido #${p.codigo}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FaixaPagamento(p),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: conferiu,
                onChanged: (v) => setState(() => conferiu = v ?? false),
                title: const Text(
                  'Conferi o documento: o cliente é maior de 18 anos',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar'),
            ),
            FilledButton(
              onPressed: conferiu ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Entregue'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _enviando.add(p.id));
    try {
      final local = await PontoRepository().obterLocalizacao();
      _repo.marcarEntregue(p, local: local.endereco);
      if (mounted) avisar(context, 'Entrega registrada.');
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _enviando.remove(p.id));
    }
  }

  String _mensagemSaindo(Pedido p) =>
      'Olá, ${primeiroNome(p.clienteNome)}! Aqui é o entregador da '
      '${ConfigRepository.atual.value.nomeLoja}. Estou a caminho com seu '
      'pedido #${p.codigo}.';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      body: StreamBuilder<List<Pedido>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Erro ao carregar: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final aFazer = snap.data!
              .where((p) => p.status == Pedido.emRota)
              .toList();
          final entregues = snap.data!
              .where((p) => p.status == Pedido.entregue)
              .toList();
          final dinheiro = entregues
              .where((p) => p.isDinheiro)
              .fold<int>(0, (s, p) => s + p.totalCentavos);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              LarguraMaxima(
                largura: 640,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TituloSecao('Para entregar (${aFazer.length})'),
                    if (aFazer.isEmpty)
                      const Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: Icon(Icons.check_circle_outline),
                          title: Text('Nenhuma entrega no momento.'),
                          subtitle: Text(
                            'Quando a loja despachar um pedido para você, '
                            'ele aparece aqui.',
                          ),
                        ),
                      ),
                    for (final p in aFazer) _cartaoEntrega(p, t),
                    if (entregues.isNotEmpty) ...[
                      TituloSecao('Entregues — acertar na loja'),
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: t.colorScheme.tertiaryContainer,
                        child: ListTile(
                          leading: const Icon(Icons.payments_outlined),
                          title: Text(
                            'Dinheiro para devolver: '
                            '${formatarMoeda(deCentavos(dinheiro))}',
                          ),
                          subtitle: Text(
                            '${entregues.length} entrega(s) aguardando o '
                            'acerto no caixa.',
                          ),
                        ),
                      ),
                      for (final p in entregues)
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text('#${p.codigo} · ${p.clienteNome}'),
                            subtitle: Text(
                              '${p.formaPagamento} · '
                              'entregue ${p.entregueEm == null ? '' : _hora.format(p.entregueEm!)}',
                            ),
                            trailing: Text(formatarMoeda(p.total)),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _cartaoEntrega(Pedido p, ThemeData t) {
    final enviando = _enviando.contains(p.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('#${p.codigo}', style: t.textTheme.labelLarge),
                const Spacer(),
                if (p.saiuEm != null)
                  Text(
                    'saiu ${_hora.format(p.saiuEm!)}',
                    style: t.textTheme.bodySmall,
                  ),
              ],
            ),
            Text(p.clienteNome, style: t.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(p.endereco, style: t.textTheme.titleMedium),
            if (p.bairro.isNotEmpty) Text('Bairro: ${p.bairro}'),
            if (p.referencia.isNotEmpty) Text('Ref.: ${p.referencia}'),
            if (p.observacao.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Obs.: ${p.observacao}',
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
              ),
            const SizedBox(height: 12),
            FaixaPagamento(p),
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('${p.quantidadeItens} item(ns)'),
              children: [
                for (final i in p.itens)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Text(
                      '${i.quantidade}×',
                      style: t.textTheme.titleSmall,
                    ),
                    title: Text(i.nome),
                  ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.navigation_outlined),
                  label: const Text('Rota'),
                  onPressed: () => abrirMapa(context, p.enderecoCompleto),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('WhatsApp'),
                  onPressed: () => abrirWhatsApp(
                    context,
                    p.telefone,
                    mensagem: _mensagemSaindo(p),
                  ),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.call_outlined),
                  label: const Text('Ligar'),
                  onPressed: () => ligar(context, p.telefone),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: enviando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.done_all),
              label: const Text('Marcar como entregue'),
              onPressed: enviando ? null : () => _entregar(p),
            ),
          ],
        ),
      ),
    );
  }
}
