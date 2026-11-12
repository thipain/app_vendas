import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/contato.dart';
import '../../core/dinheiro.dart';
import '../../core/formatters.dart';
import '../../core/imagem.dart';
import '../../core/impressao/pedido_pdf.dart';
import '../../core/regra_exception.dart';
import '../../data/config_repository.dart';
import '../../data/dados.dart';
import '../../data/pedido_repository.dart';
import '../../data/venda_repository.dart';
import '../../models/comanda.dart';
import '../../models/pedido.dart';
import '../../models/venda.dart';
import '../../widgets/confirmar.dart';
import '../../widgets/largura_maxima.dart';
import '../../widgets/mensagens.dart';
import '../../widgets/seletor.dart';
import '../inicio/comum.dart';
import 'delivery_comum.dart';
import 'pedido_form_page.dart';

/// Pedido de delivery aberto pela loja: dados do cliente, itens, pagamento
/// (comprovante do Pix, troco, maquininha) e a ação de cada etapa.
class PedidoDetalhePage extends StatefulWidget {
  final String pedidoId;
  const PedidoDetalhePage({super.key, required this.pedidoId});

  @override
  State<PedidoDetalhePage> createState() => _PedidoDetalhePageState();
}

class _PedidoDetalhePageState extends State<PedidoDetalhePage> {
  final _repo = PedidoRepository();
  late final _stream = _repo.watch(widget.pedidoId);
  late final _comprovante = _repo.watchComprovante(widget.pedidoId);
  bool _carregandoImagem = false;

  static final _hora = DateFormat('dd/MM HH:mm');

  String _mensagemCliente(Pedido p) {
    final loja = ConfigRepository.atual.value;
    final b = StringBuffer('Olá, ${primeiroNome(p.clienteNome)}! ');
    switch (p.status) {
      case Pedido.emRota:
        b.write(
          'Seu pedido #${p.codigo} da ${loja.nomeLoja} saiu para entrega. ',
        );
      case Pedido.entregue || Pedido.concluido:
        b.write('Obrigado pela compra na ${loja.nomeLoja}! ');
      default:
        b.write(
          'Recebemos seu pedido #${p.codigo} na ${loja.nomeLoja}. '
          'Total: ${formatarMoeda(p.total)} '
          '(taxa de entrega ${formatarMoeda(p.taxaEntrega)}). ',
        );
    }
    if (p.isPix && !p.pixConfirmado && loja.chavePix.isNotEmpty) {
      b.write(
        'Para pagar no Pix, use a chave ${loja.chavePix} e envie o '
        'comprovante por aqui.',
      );
    } else if (p.troco > 0 && p.status != Pedido.concluido) {
      b.write('Vamos levar troco para ${formatarMoeda(p.trocoPara!)}.');
    } else if (p.isCartao && p.status != Pedido.concluido) {
      b.write('O entregador leva a maquininha (${p.formaPagamento}).');
    }
    return b.toString().trim();
  }

  Future<void> _anexar(Pedido p, {bool camera = false}) async {
    setState(() => _carregandoImagem = true);
    try {
      final b64 = await escolherImagem(camera: camera, lado: 1280);
      if (b64 == null) return;
      _repo.anexarComprovante(p, b64);
      if (mounted) avisar(context, 'Comprovante anexado.');
    } on FormatException catch (e) {
      if (mounted) mostrarErro(context, RegraException(e.message));
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _carregandoImagem = false);
    }
  }

  void _verImagem(String b64) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: InteractiveViewer(
                child: Image.memory(base64Decode(b64), fit: BoxFit.contain),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fechar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _adicionarItem(Pedido p) async {
    final produto = await selecionarProduto(
      context,
      titulo: 'Adicionar ao pedido',
      exigirEstoque: true,
    );
    if (produto == null || !mounted) return;
    executar(
      context,
      () => _repo.adicionarItens(p, [ItemCarrinho(produto, 1)]),
    );
  }

  void _quantidade(Pedido p, ItemComanda item, int nova) {
    executar(
      context,
      () => _repo.alterarQuantidade(
        p,
        item,
        nova,
        Dados.produtosPorId[item.produtoId],
      ),
    );
  }

  Future<void> _despachar(Pedido p, {bool trocar = false}) async {
    final m = await escolherMotoboy(context);
    if (m == null || !mounted) return;
    executar(
      context,
      () => trocar ? _repo.trocarMotoboy(p, m) : _repo.despachar(p, m),
      sucesso: trocar
          ? 'Motoboy trocado para ${m.nome}.'
          : 'Pedido saiu com ${m.nome}.',
    );
  }

  Future<void> _entregue(Pedido p) async {
    final ok = await confirmar(
      context,
      titulo: 'Pedido entregue',
      mensagem:
          'Confirmar que o pedido #${p.codigo} foi entregue a '
          '${p.clienteNome}? O pagamento é acertado depois, ao concluir.',
      confirmarTexto: 'Entregue',
    );
    if (!ok || !mounted) return;
    executar(
      context,
      () => _repo.marcarEntregue(p, local: 'Marcado pela loja'),
    );
  }

  Future<void> _cancelar(Pedido p) async {
    final motivo = await pedirTexto(
      context,
      titulo: 'Cancelar pedido #${p.codigo}',
      rotulo: 'Motivo do cancelamento',
      minimo: 5,
      confirmar: 'Cancelar pedido',
      ajuda: 'Os itens voltam para o estoque.',
    );
    if (motivo == null || !mounted) return;
    if (executar(
      context,
      () => _repo.cancelar(p, motivo, Dados.produtosPorId),
      sucesso: 'Pedido cancelado e itens devolvidos ao estoque.',
    )) {
      Navigator.pop(context);
    }
  }

  Future<void> _concluir(Pedido p) async {
    final venda = await concluirPedido(context, p);
    if (venda != null && mounted) {
      avisar(context, 'Pedido concluído. Venda #${venda.codigo} registrada.');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Pedido?>(
      stream: _stream,
      builder: (context, snap) {
        final p = snap.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(p == null ? 'Pedido' : 'Pedido #${p.codigo}'),
            actions: [
              if (p != null) ...[
                IconButton(
                  tooltip: 'Imprimir via do entregador',
                  icon: const Icon(Icons.print_outlined),
                  onPressed: () =>
                      imprimirViaPedido(
                        p,
                        ConfigRepository.atual.value,
                      ).catchError((Object e) {
                        if (context.mounted) mostrarErro(context, e);
                      }),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    switch (v) {
                      case 'editar':
                        Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => PedidoFormPage(pedido: p),
                          ),
                        );
                      case 'compartilhar':
                        compartilharViaPedido(p, ConfigRepository.atual.value);
                      case 'cancelar':
                        _cancelar(p);
                    }
                  },
                  itemBuilder: (_) => [
                    if (p.isAtivo)
                      const PopupMenuItem(
                        value: 'editar',
                        child: Text('Editar cliente, endereço e pagamento'),
                      ),
                    const PopupMenuItem(
                      value: 'compartilhar',
                      child: Text('Compartilhar via em PDF'),
                    ),
                    if (p.isAtivo)
                      const PopupMenuItem(
                        value: 'cancelar',
                        child: Text('Cancelar pedido'),
                      ),
                  ],
                ),
              ],
            ],
          ),
          body: p == null
              ? Center(
                  child: snap.connectionState == ConnectionState.waiting
                      ? const CircularProgressIndicator()
                      : const Text('Pedido não encontrado.'),
                )
              : _corpo(context, p),
          bottomNavigationBar: p == null || !p.isAtivo
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _acaoPrincipal(p),
                  ),
                ),
        );
      },
    );
  }

  Widget _acaoPrincipal(Pedido p) {
    final botoes = switch (p.status) {
      Pedido.novo => [
        OutlinedButton.icon(
          icon: const Icon(Icons.soup_kitchen_outlined),
          label: const Text('Iniciar preparo'),
          onPressed: () => executar(context, () => _repo.iniciarPreparo(p)),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.two_wheeler),
          label: const Text('Saiu para entrega'),
          onPressed: () => _despachar(p),
        ),
      ],
      Pedido.preparo => [
        FilledButton.icon(
          icon: const Icon(Icons.two_wheeler),
          label: const Text('Saiu para entrega'),
          onPressed: () => _despachar(p),
        ),
      ],
      Pedido.emRota => [
        OutlinedButton.icon(
          icon: const Icon(Icons.swap_horiz),
          label: const Text('Trocar motoboy'),
          onPressed: () => _despachar(p, trocar: true),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.done),
          label: const Text('Marcar entregue'),
          onPressed: () => _entregue(p),
        ),
      ],
      Pedido.entregue => [
        OutlinedButton.icon(
          icon: const Icon(Icons.swap_horiz),
          label: const Text('Trocar motoboy'),
          onPressed: () => _despachar(p, trocar: true),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.point_of_sale),
          label: const Text('Concluir e receber'),
          onPressed: () => _concluir(p),
        ),
      ],
      _ => <Widget>[],
    };
    return Row(
      children: [
        for (final (i, b) in botoes.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: b),
        ],
      ],
    );
  }

  Widget _corpo(BuildContext context, Pedido p) {
    final t = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        LarguraMaxima(
          largura: 760,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ChipStatus(p.status),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Registrado ${_hora.format(p.criadoEm)}'
                      '${p.criadoPorNome.isEmpty ? '' : ' por ${p.criadoPorNome}'}',
                      style: t.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              if (p.status == Pedido.cancelado &&
                  (p.motivoCancelamento ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Motivo: ${p.motivoCancelamento}',
                    style: TextStyle(color: t.colorScheme.error),
                  ),
                ),
              const TituloSecao('Cliente e entrega'),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.clienteNome, style: t.textTheme.titleLarge),
                      Text(p.telefone),
                      const SizedBox(height: 8),
                      Text(p.endereco, style: t.textTheme.titleMedium),
                      if (p.bairro.isNotEmpty) Text('Bairro: ${p.bairro}'),
                      if (p.referencia.isNotEmpty)
                        Text('Referência: ${p.referencia}'),
                      if (p.observacao.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Obs.: ${p.observacao}',
                          style: t.textTheme.bodyMedium?.copyWith(
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            icon: const Icon(Icons.chat_outlined),
                            label: const Text('WhatsApp'),
                            onPressed: () => abrirWhatsApp(
                              context,
                              p.telefone,
                              mensagem: _mensagemCliente(p),
                            ),
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.call_outlined),
                            label: const Text('Ligar'),
                            onPressed: () => ligar(context, p.telefone),
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.map_outlined),
                            label: const Text('Mapa'),
                            onPressed: () =>
                                abrirMapa(context, p.enderecoCompleto),
                          ),
                        ],
                      ),
                      if (p.entregadorNome.isNotEmpty) ...[
                        const Divider(height: 24),
                        Row(
                          children: [
                            const Icon(Icons.two_wheeler),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Motoboy: ${p.entregadorNome}'
                                '${p.saiuEm == null ? '' : ' · saiu ${_hora.format(p.saiuEm!)}'}'
                                '${p.entregueEm == null ? '' : ' · entregue ${_hora.format(p.entregueEm!)}'}',
                              ),
                            ),
                          ],
                        ),
                        if (p.localEntrega.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Local da entrega: ${p.localEntrega}',
                              style: t.textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              const TituloSecao('Itens'),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      for (final i in p.itens)
                        ListTile(
                          title: Text(i.nome),
                          subtitle: Text(
                            '${i.quantidade} × ${formatarMoeda(i.precoUnitario)}',
                          ),
                          trailing: p.podeAlterarItens
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                      ),
                                      onPressed: () =>
                                          _quantidade(p, i, i.quantidade - 1),
                                    ),
                                    Text(formatarMoeda(i.total)),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.add_circle_outline,
                                      ),
                                      onPressed: () =>
                                          _quantidade(p, i, i.quantidade + 1),
                                    ),
                                  ],
                                )
                              : Text(formatarMoeda(i.total)),
                        ),
                      if (p.podeAlterarItens)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              icon: const Icon(Icons.add),
                              label: const Text('Adicionar produto'),
                              onPressed: () => _adicionarItem(p),
                            ),
                          ),
                        ),
                      const Divider(),
                      _linhaValor('Produtos', p.subtotal),
                      _linhaValor('Taxa de entrega', p.taxaEntrega),
                      _linhaValor('Total', p.total, destaque: true),
                    ],
                  ),
                ),
              ),
              const TituloSecao('Pagamento'),
              FaixaPagamento(p),
              if (p.isPix) ...[const SizedBox(height: 12), _secaoPix(p, t)],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }

  Widget _secaoPix(Pedido p, ThemeData t) {
    final mobile =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Comprovante do Pix', style: t.textTheme.titleSmall),
            const SizedBox(height: 8),
            StreamBuilder<String?>(
              stream: _comprovante,
              builder: (context, snap) {
                final img = snap.data;
                if (img == null) {
                  return Text(
                    p.temComprovante
                        ? 'Carregando comprovante...'
                        : 'Nenhum comprovante anexado.',
                    style: t.textTheme.bodySmall,
                  );
                }
                return Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    onTap: () => _verImagem(img),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        base64Decode(img),
                        height: 220,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                );
              },
            ),
            if (p.isAtivo) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    icon: _carregandoImagem
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.attach_file),
                    label: Text(
                      p.temComprovante
                          ? 'Trocar comprovante'
                          : 'Anexar comprovante',
                    ),
                    onPressed: _carregandoImagem ? null : () => _anexar(p),
                  ),
                  if (mobile)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Fotografar'),
                      onPressed: _carregandoImagem
                          ? null
                          : () => _anexar(p, camera: true),
                    ),
                  if (p.temComprovante)
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remover'),
                      onPressed: () =>
                          executar(context, () => _repo.removerComprovante(p)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Pix recebido na conta da loja'),
                subtitle: Text(
                  p.temComprovante
                      ? 'Confira no extrato do banco antes de confirmar.'
                      : 'Ainda sem comprovante anexado.',
                ),
                value: p.pixConfirmado,
                onChanged: (v) =>
                    executar(context, () => _repo.confirmarPix(p, v)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _linhaValor(String rotulo, double valor, {bool destaque = false}) {
    final t = Theme.of(context);
    final estilo = destaque ? t.textTheme.titleMedium : null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(rotulo, style: estilo)),
          Text(formatarMoeda(valor), style: estilo),
        ],
      ),
    );
  }
}

/// Recebe o pagamento de um pedido entregue e gera a venda. O cliente pode
/// ter pago de outro jeito do combinado, por isso a forma pode ser trocada.
Future<Venda?> concluirPedido(BuildContext context, Pedido p) {
  return showDialog<Venda>(
    context: context,
    builder: (_) => _ConcluirDialog(pedido: p),
  );
}

class _ConcluirDialog extends StatefulWidget {
  final Pedido pedido;
  const _ConcluirDialog({required this.pedido});

  @override
  State<_ConcluirDialog> createState() => _ConcluirDialogState();
}

class _ConcluirDialogState extends State<_ConcluirDialog> {
  late String _forma = widget.pedido.formaPagamento;
  late final _recebido = TextEditingController(
    text: valorParaCampo(widget.pedido.trocoPara ?? widget.pedido.total),
  )..addListener(() => setState(() {}));

  @override
  void dispose() {
    _recebido.dispose();
    super.dispose();
  }

  void _confirmar() {
    final p = widget.pedido;
    try {
      double? recebido;
      if (_forma == FormaPagamento.dinheiro) {
        recebido = lerValor(_recebido.text);
        if (recebido == null || centavos(recebido) < p.totalCentavos) {
          throw const RegraException(
            'O valor recebido em dinheiro é menor que o total.',
          );
        }
      }
      final venda = VendaRepository().concluirPedido(
        pedido: p,
        caixa: Dados.caixaAberto.value,
        produtos: Dados.produtosPorId,
        forma: _forma,
        recebidoEmDinheiro: recebido,
      );
      Navigator.pop(context, venda);
    } catch (e) {
      mostrarErro(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pedido;
    final t = Theme.of(context);
    final recebido = lerValor(_recebido.text);
    final troco = recebido == null ? 0 : centavos(recebido) - p.totalCentavos;
    return AlertDialog(
      title: Text('Concluir pedido #${p.codigo}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(formatarMoeda(p.total), style: t.textTheme.headlineSmall),
            Text(
              'Produtos ${formatarMoeda(p.subtotal)} + entrega '
              '${formatarMoeda(p.taxaEntrega)}',
              style: t.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _forma,
              decoration: const InputDecoration(labelText: 'Forma recebida'),
              items: [
                for (final f in FormaPagamento.todas)
                  DropdownMenuItem(value: f, child: Text(f)),
              ],
              onChanged: (v) => setState(() => _forma = v ?? _forma),
            ),
            if (_forma == FormaPagamento.dinheiro) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _recebido,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Valor entregue pelo cliente (R\$)',
                  helperText: troco > 0
                      ? 'Troco: ${formatarMoeda(deCentavos(troco))}'
                      : null,
                ),
              ),
            ],
            if (_forma == FormaPagamento.pix && !p.pixConfirmado) ...[
              const SizedBox(height: 12),
              Text(
                'Confirme o recebimento do Pix na tela do pedido antes de '
                'concluir.',
                style: TextStyle(color: t.colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              _forma == FormaPagamento.dinheiro
                  ? 'O dinheiro entra no caixa aberto agora.'
                  : 'A venda é registrada no caixa aberto agora.',
              style: t.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Voltar'),
        ),
        FilledButton(onPressed: _confirmar, child: const Text('Concluir')),
      ],
    );
  }
}
