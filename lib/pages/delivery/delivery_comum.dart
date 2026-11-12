import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../data/dados.dart';
import '../../models/pedido.dart';
import '../../models/motoboy.dart';
import '../../models/venda.dart';
import '../../widgets/mensagens.dart';
import '../inicio/comum.dart';

/// Cor de cada etapa do pedido.
Color corStatus(BuildContext context, String status) {
  final c = Theme.of(context).colorScheme;
  return switch (status) {
    Pedido.novo => Colors.orange.shade700,
    Pedido.preparo => Colors.blue.shade700,
    Pedido.emRota => Colors.purple.shade600,
    Pedido.entregue => Colors.teal.shade700,
    Pedido.concluido => Colors.green.shade700,
    Pedido.cancelado => c.error,
    _ => c.outline,
  };
}

IconData iconeForma(String forma) => switch (forma) {
  FormaPagamento.pix => Icons.pix,
  FormaPagamento.dinheiro => Icons.payments_outlined,
  FormaPagamento.debito || FormaPagamento.credito => Icons.credit_card,
  FormaPagamento.vr => Icons.restaurant_outlined,
  _ => Icons.attach_money,
};

class ChipStatus extends StatelessWidget {
  final String status;
  const ChipStatus(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final cor = corStatus(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withValues(alpha: 0.5)),
      ),
      child: Text(
        Pedido.nomes[status] ?? status,
        style: TextStyle(color: cor, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}

/// Faixa destacada com o que fazer no pagamento (troco, maquininha, Pix).
class FaixaPagamento extends StatelessWidget {
  final Pedido pedido;
  const FaixaPagamento(this.pedido, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = pedido;
    final alerta = p.isPix ? !p.pixConfirmado : true;
    final cor = p.isPix && p.pixConfirmado
        ? Colors.green.shade700
        : p.isCartao
        ? Colors.indigo.shade600
        : Colors.orange.shade800;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withValues(alpha: alerta ? 0.8 : 0.4)),
      ),
      child: Row(
        children: [
          Icon(iconeForma(p.formaPagamento), color: cor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.instrucaoPagamento,
                  style: t.textTheme.titleSmall?.copyWith(color: cor),
                ),
                Text(
                  'Total do pedido: ${formatarMoeda(p.total)}',
                  style: t.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Cartão resumido de um pedido (painel e lista do entregador).
class CartaoPedido extends StatelessWidget {
  final Pedido pedido;
  final VoidCallback onTap;
  final bool mostrarStatus;

  const CartaoPedido({
    super.key,
    required this.pedido,
    required this.onTap,
    this.mostrarStatus = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = pedido;
    final minutos = DateTime.now().difference(p.criadoEm).inMinutes;
    final tempo = minutos < 60
        ? '$minutos min'
        : '${minutos ~/ 60}h${(minutos % 60).toString().padLeft(2, '0')}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('#${p.codigo}', style: t.textTheme.labelLarge),
                  const SizedBox(width: 8),
                  if (mostrarStatus) ChipStatus(p.status),
                  const Spacer(),
                  if (p.pendente)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.schedule,
                        size: 16,
                        color: Colors.orange,
                      ),
                    ),
                  Text(tempo, style: t.textTheme.bodySmall),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                p.clienteNome,
                style: t.textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                p.enderecoCompleto,
                style: t.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(formatarMoeda(p.total), style: t.textTheme.titleSmall),
                  _Etiqueta(
                    icone: iconeForma(p.formaPagamento),
                    texto: p.formaPagamento,
                  ),
                  if (p.isPix && !p.pixConfirmado)
                    _Etiqueta(
                      icone: Icons.warning_amber,
                      texto: p.temComprovante
                          ? 'Conferir Pix'
                          : 'Sem comprovante',
                      cor: Colors.orange.shade800,
                    ),
                  if (p.troco > 0)
                    _Etiqueta(
                      icone: Icons.currency_exchange,
                      texto: 'Troco ${formatarMoeda(p.troco)}',
                      cor: Colors.orange.shade800,
                    ),
                  if (p.isCartao)
                    _Etiqueta(
                      icone: Icons.point_of_sale,
                      texto: 'Maquininha',
                      cor: Colors.indigo.shade600,
                    ),
                  if (p.entregadorNome.isNotEmpty)
                    _Etiqueta(
                      icone: Icons.two_wheeler,
                      texto: primeiroNome(p.entregadorNome),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  final IconData icone;
  final String texto;
  final Color? cor;

  const _Etiqueta({required this.icone, required this.texto, this.cor});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = cor ?? t.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 14, color: c),
          const SizedBox(width: 4),
          Text(texto, style: t.textTheme.labelSmall?.copyWith(color: c)),
        ],
      ),
    );
  }
}

/// Escolhe o motoboy que vai levar o pedido, entre os cadastrados e ativos
/// na loja.
Future<Motoboy?> escolherMotoboy(BuildContext context) async {
  final ativos = Dados.motoboys.value.where((m) => m.ativo).toList();
  if (ativos.isEmpty) {
    avisar(
      context,
      'Cadastre os motoboys em "Motoboys e diárias" antes de despachar.',
    );
    return null;
  }
  return showDialog<Motoboy>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Qual motoboy vai entregar?'),
      children: [
        for (final m in ativos)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, m),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Text(iniciais(m.nome))),
              title: Text(m.nome),
              subtitle: m.usuarioId == null
                  ? null
                  : const Text('Recebe o pedido no celular'),
            ),
          ),
      ],
    ),
  );
}
