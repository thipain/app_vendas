import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/contato.dart';
import '../../core/dinheiro.dart';
import '../../core/formatters.dart';
import '../../data/alarme_online.dart';
import '../../data/dados.dart';
import '../../data/pedido_online_repository.dart';
import '../../models/cupom.dart';
import '../../models/pedido_online.dart';
import '../../widgets/mensagens.dart';
import 'delivery_comum.dart';

/// Cartão de um pedido da loja online aguardando resposta.
class CartaoPedidoOnline extends StatelessWidget {
  final PedidoOnline pedido;
  final ValueChanged<String> onAceito;

  const CartaoPedidoOnline({
    super.key,
    required this.pedido,
    required this.onAceito,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = pedido;
    final minutos = DateTime.now().difference(p.criadoEm).inMinutes;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.orange.shade700, width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => responderPedidoOnline(context, p, onAceito),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.public, size: 18, color: Colors.orange.shade800),
                  const SizedBox(width: 6),
                  Text('Online #${p.codigo}', style: t.textTheme.labelLarge),
                  const Spacer(),
                  Text(
                    minutos < 1 ? 'agora' : 'há $minutos min',
                    style: t.textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(p.clienteNome, style: t.textTheme.titleMedium),
              Text(
                '${p.endereco} — ${p.bairro}',
                style: t.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(iconeForma(p.formaPagamento), size: 16),
                  const SizedBox(width: 4),
                  Text(p.formaPagamento),
                  if (p.isPix) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.attach_file, size: 16),
                    const Text('comprovante'),
                  ],
                  const Spacer(),
                  Text(formatarMoeda(p.total), style: t.textTheme.titleSmall),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.orange.shade800,
                ),
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Ver e responder'),
                onPressed: () => responderPedidoOnline(context, p, onAceito),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mostra o pedido online completo (com o comprovante do Pix) para a loja
/// aceitar ou recusar.
Future<void> responderPedidoOnline(
  BuildContext context,
  PedidoOnline pedido,
  ValueChanged<String> onAceito,
) async {
  final id = await showDialog<String>(
    context: context,
    builder: (_) => _RespostaDialog(pedido: pedido),
  );
  if (id != null) onAceito(id);
}

class _RespostaDialog extends StatefulWidget {
  final PedidoOnline pedido;
  const _RespostaDialog({required this.pedido});

  @override
  State<_RespostaDialog> createState() => _RespostaDialogState();
}

class _RespostaDialogState extends State<_RespostaDialog> {
  final _repo = PedidoOnlineRepository();
  Map<String, Cupom> get _cupons => {
    for (final c in Dados.cupons.value) c.codigo: c,
  };
  late final Future<String?> _comprovante = widget.pedido.isPix
      ? _repo.lerComprovante(widget.pedido.id)
      : Future.value(null);

  Future<void> _recusar() async {
    final motivo = await pedirTexto(
      context,
      titulo: 'Recusar pedido #${widget.pedido.codigo}',
      rotulo: 'Motivo (o cliente vê)',
      minimo: 3,
      confirmar: 'Recusar',
      ajuda: 'Ex.: "Fora da área de entrega" ou "Produto acabou".',
    );
    if (motivo == null || !mounted) return;
    if (executar(
      context,
      () => _repo.recusar(widget.pedido, motivo),
      sucesso: 'Pedido recusado. O cliente vê o motivo na página.',
    )) {
      Navigator.pop(context);
    }
  }

  Future<void> _aceitar(String? comprovante) async {
    try {
      final id = _repo.aceitar(
        widget.pedido,
        Dados.produtosPorId,
        comprovantePix: comprovante,
        cupons: _cupons,
      );
      Navigator.pop(context, id);
    } catch (e) {
      mostrarErro(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = widget.pedido;
    final c = PedidoOnlineRepository.conferir(
      p,
      Dados.produtosPorId,
      cupons: _cupons,
    );
    final totalLoja =
        c.subtotalCentavos - c.descontoCentavos + centavos(p.taxaEntrega);
    return AlertDialog(
      title: Text('Pedido online #${p.codigo}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(p.clienteNome, style: t.textTheme.titleLarge),
              Row(
                children: [
                  Expanded(child: Text(p.telefone)),
                  IconButton(
                    tooltip: 'WhatsApp do cliente',
                    icon: const Icon(Icons.chat_outlined),
                    onPressed: () => abrirWhatsApp(context, p.telefone),
                  ),
                ],
              ),
              Text(p.endereco, style: t.textTheme.titleMedium),
              Text(p.bairro),
              if (p.referencia.isNotEmpty) Text('Ref.: ${p.referencia}'),
              if (p.cep.isNotEmpty) Text('CEP ${p.cep}'),
              if (p.observacao.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Obs.: ${p.observacao}',
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  ),
                ),
              const Divider(height: 24),
              for (final i in p.itens)
                Row(
                  children: [
                    Expanded(child: Text('${i.quantidade}× ${i.nome}')),
                    Text(formatarMoeda(i.precoUnitario * i.quantidade)),
                  ],
                ),
              const SizedBox(height: 4),
              if (p.cupom != null)
                Row(
                  children: [
                    Expanded(child: Text('Cupom ${p.cupom}')),
                    Text('- ${formatarMoeda(deCentavos(c.descontoCentavos))}'),
                  ],
                ),
              Row(
                children: [
                  const Expanded(child: Text('Taxa de entrega')),
                  Text(formatarMoeda(p.taxaEntrega)),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: Text('Total', style: t.textTheme.titleMedium),
                  ),
                  Text(
                    formatarMoeda(deCentavos(totalLoja)),
                    style: t.textTheme.titleMedium,
                  ),
                ],
              ),
              if (c.avisoCupom != null) ...[
                const SizedBox(height: 8),
                _Alerta(
                  cor: Colors.orange.shade800,
                  titulo: 'Cupom sem desconto:',
                  linhas: [
                    c.avisoCupom!,
                    'Se aceitar, o pedido entra sem o desconto. Avise o cliente.',
                  ],
                ),
              ],
              if (c.problemas.isNotEmpty) ...[
                const SizedBox(height: 8),
                _Alerta(
                  cor: t.colorScheme.error,
                  titulo: 'Não dá para atender:',
                  linhas: c.problemas,
                ),
              ],
              if (c.precosAlterados.isNotEmpty) ...[
                const SizedBox(height: 8),
                _Alerta(
                  cor: Colors.orange.shade800,
                  titulo:
                      'Preço mudou desde o pedido (vale o preço atual; '
                      'cliente viu ${formatarMoeda(p.total)}):',
                  linhas: c.precosAlterados,
                ),
              ],
              const Divider(height: 24),
              Row(
                children: [
                  Icon(iconeForma(p.formaPagamento)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      p.formaPagamento == 'Dinheiro'
                          ? (p.trocoPara == null
                                ? 'Dinheiro — sem troco'
                                : 'Dinheiro — troco para ${formatarMoeda(p.trocoPara!)}')
                          : p.isPix
                          ? 'Pix — confira o comprovante e o extrato'
                          : '${p.formaPagamento} — levar maquininha',
                      style: t.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              if (p.isPix)
                FutureBuilder<String?>(
                  future: _comprovante,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.all(12),
                        child: LinearProgressIndicator(),
                      );
                    }
                    final img = snap.data;
                    if (img == null) {
                      return Text(
                        'Não foi possível carregar o comprovante.',
                        style: TextStyle(color: t.colorScheme.error),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: InteractiveViewer(
                        child: Image.memory(
                          base64Decode(img),
                          height: 320,
                          fit: BoxFit.contain,
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.block),
          label: const Text('Recusar'),
          onPressed: _recusar,
        ),
        FutureBuilder<String?>(
          future: _comprovante,
          builder: (context, snap) => FilledButton.icon(
            icon: const Icon(Icons.check),
            label: const Text('Aceitar'),
            onPressed:
                c.problemas.isNotEmpty ||
                    (p.isPix &&
                        (snap.connectionState != ConnectionState.done ||
                            snap.data == null))
                ? null
                : () => _aceitar(snap.data),
          ),
        ),
      ],
    );
  }
}

class _Alerta extends StatelessWidget {
  final Color cor;
  final String titulo;
  final List<String> linhas;

  const _Alerta({
    required this.cor,
    required this.titulo,
    required this.linhas,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: cor.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: cor.withValues(alpha: 0.5)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: TextStyle(color: cor, fontWeight: FontWeight.w600),
        ),
        for (final l in linhas) Text('• $l'),
      ],
    ),
  );
}

/// Faixa no topo do app avisando que há pedidos online esperando resposta.
class FaixaPedidosOnline extends StatelessWidget {
  final VoidCallback onAbrir;
  const FaixaPedidosOnline({super.key, required this.onAbrir});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<PedidoOnline>>(
      valueListenable: AlarmeOnline.aguardando,
      builder: (context, lista, _) {
        if (lista.isEmpty) return const SizedBox.shrink();
        return Material(
          color: Colors.orange.shade800,
          child: InkWell(
            onTap: onAbrir,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.notifications_active, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      lista.length == 1
                          ? '1 pedido online esperando resposta'
                          : '${lista.length} pedidos online esperando resposta',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Text(
                    'VER',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
