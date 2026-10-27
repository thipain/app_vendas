import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/formatters.dart';
import '../../core/impressao/comprovante_pdf.dart';
import '../../core/permissoes.dart';
import '../../core/sessao.dart';
import '../../data/config_repository.dart';
import '../../data/venda_repository.dart';
import '../../models/config_loja.dart';
import '../../models/venda.dart';
import '../../widgets/filtro_periodo.dart';
import '../../widgets/foto_produto.dart';
import '../../widgets/largura_maxima.dart';
import '../../widgets/mensagens.dart';
import 'venda_detalhe_page.dart';

/// Comprovante não fiscal de 80 mm: prévia, impressão, compartilhamento e
/// edição do texto completo da nota.
class ComprovantePage extends StatefulWidget {
  final String vendaId;
  final bool editar;

  /// Abre a impressão assim que a venda carregar (reimpressão).
  final bool imprimir;

  /// Abre um módulo do menu (ex.: 'vendas') depois de voltar à tela
  /// principal. Sem ele, os atalhos de navegação não aparecem.
  final void Function(String modulo)? abrirModulo;

  const ComprovantePage({
    super.key,
    required this.vendaId,
    this.editar = false,
    this.imprimir = false,
    this.abrirModulo,
  });

  @override
  State<ComprovantePage> createState() => _ComprovantePageState();
}

class _ComprovantePageState extends State<ComprovantePage> {
  late final _stream = VendaRepository().watch(widget.vendaId);
  final _texto = TextEditingController();
  late bool _editando = widget.editar;
  bool _textoPreenchido = false;
  bool _impressaoAutomatica = false;
  bool _ocupado = false;

  static final _milhar = NumberFormat('#,##0', 'pt_BR');

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  void _preencher(Venda v, ConfigLoja loja) {
    _texto.text = v.textoComprovante ?? textoComprovantePadrao(v, loja);
    _textoPreenchido = true;
  }

  Future<void> _imprimir(Venda v, ConfigLoja loja, {String? textoLivre}) async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    try {
      await imprimirComprovante(v, loja, textoLivre: textoLivre);
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _compartilhar(Venda v, ConfigLoja loja) async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    try {
      await compartilharComprovante(v, loja);
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  bool _salvar(Venda v) {
    final ok = executar(
      context,
      () => VendaRepository().salvarTextoComprovante(v, _texto.text),
      sucesso: 'Alterações salvas. A nota já está pronta para impressão.',
    );
    if (ok) setState(() => _editando = false);
    return ok;
  }

  void _restaurar(Venda v, ConfigLoja loja) {
    final ok = executar(
      context,
      () => VendaRepository().salvarTextoComprovante(v, ''),
      sucesso: 'Comprovante original restaurado.',
    );
    if (ok) _texto.text = textoComprovantePadrao(v, loja);
  }

  void _irPara(String modulo) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    widget.abrirModulo?.call(modulo);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ConfigLoja>(
      valueListenable: ConfigRepository.atual,
      builder: (context, loja, _) => StreamBuilder<Venda?>(
        stream: _stream,
        builder: (context, snap) {
          final v = snap.data;
          final visivel = v != null && podeVerVenda(v);
          if (visivel) {
            if (_editando && !_textoPreenchido) _preencher(v, loja);
            if (widget.imprimir && !_impressaoAutomatica) {
              _impressaoAutomatica = true;
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _imprimir(v, loja),
              );
            }
          }
          Widget corpo;
          if (snap.hasError) {
            corpo = Center(child: Text('Erro ao carregar: ${snap.error}'));
          } else if (snap.connectionState == ConnectionState.waiting) {
            corpo = const Center(child: CircularProgressIndicator());
          } else if (!visivel) {
            corpo = const EstadoVazio(
              icone: Icons.search_off,
              titulo: 'Venda não encontrada.',
            );
          } else if (_editando) {
            corpo = _editor(v, loja);
          } else {
            corpo = _previa(v, loja);
          }
          return Scaffold(
            appBar: AppBar(
              title: Text(
                v == null
                    ? 'Comprovante'
                    : _editando
                    ? 'Editar nota #${v.codigo}'
                    : 'Comprovante #${v.codigo}',
              ),
              actions: [
                if (_ocupado)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                if (visivel && !_editando) ...[
                  IconButton(
                    tooltip: 'Editar nota completa',
                    icon: const Icon(Icons.edit_note),
                    onPressed: () => setState(() {
                      _editando = true;
                      _preencher(v, loja);
                    }),
                  ),
                  IconButton(
                    tooltip: 'Compartilhar',
                    icon: const Icon(Icons.share_outlined),
                    onPressed: () => _compartilhar(v, loja),
                  ),
                  IconButton(
                    tooltip: 'Imprimir',
                    icon: const Icon(Icons.print_outlined),
                    onPressed: () => _imprimir(v, loja),
                  ),
                ],
              ],
            ),
            body: corpo,
          );
        },
      ),
    );
  }

  Widget _previa(Venda v, ConfigLoja loja) {
    final abrir = widget.abrirModulo;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: _PapelComprovante(venda: v, loja: loja),
        ),
        const SizedBox(height: 16),
        LarguraMaxima(
          largura: 520,
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.edit_note),
                label: const Text('Editar nota completa'),
                onPressed: () => setState(() {
                  _editando = true;
                  _preencher(v, loja);
                }),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.print_outlined),
                label: const Text('Imprimir'),
                onPressed: () => _imprimir(v, loja),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.share_outlined),
                label: const Text('Compartilhar'),
                onPressed: () => _compartilhar(v, loja),
              ),
              if (abrir != null) ...[
                OutlinedButton.icon(
                  icon: const Icon(Icons.add_shopping_cart),
                  label: const Text('Nova venda'),
                  onPressed: () => _irPara('vendas'),
                ),
                if (Sessao.instancia.pode(Permissao.historico))
                  OutlinedButton.icon(
                    icon: const Icon(Icons.history),
                    label: const Text('Histórico'),
                    onPressed: () => _irPara('historico'),
                  ),
                if (Sessao.instancia.pode(Permissao.comandas))
                  OutlinedButton.icon(
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('Comandas'),
                    onPressed: () => _irPara('comandas'),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _editor(Venda v, ConfigLoja loja) {
    final t = Theme.of(context);
    return LarguraMaxima(
      largura: 640,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Conteúdo completo da impressão',
              style: t.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'O texto salvo substitui o layout padrão em todas as '
              'impressões desta venda. Deixe vazio ou restaure para voltar '
              'ao original.',
              style: t.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: _texto,
                expands: true,
                maxLines: null,
                minLines: null,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ),
            const SizedBox(height: 4),
            ListenableBuilder(
              listenable: _texto,
              builder: (_, _) {
                final n = _texto.text.length;
                return Text(
                  '${_milhar.format(n)}/${_milhar.format(limiteTextoComprovante)} caracteres',
                  textAlign: TextAlign.right,
                  style: t.textTheme.bodySmall?.copyWith(
                    color: n > limiteTextoComprovante
                        ? t.colorScheme.error
                        : null,
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                TextButton(
                  onPressed: () => setState(() {
                    _editando = false;
                    _textoPreenchido = false;
                  }),
                  child: const Text('Cancelar edição'),
                ),
                if (v.textoComprovante != null)
                  OutlinedButton(
                    onPressed: () => _restaurar(v, loja),
                    child: const Text('Restaurar original'),
                  ),
                OutlinedButton(
                  onPressed: () => _salvar(v),
                  child: const Text('Salvar alterações'),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Salvar e imprimir'),
                  onPressed: () {
                    final texto = _texto.text.replaceAll('\r\n', '\n').trim();
                    if (_salvar(v)) _imprimir(v, loja, textoLivre: texto);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Prévia em tela do papel de 80 mm.
class _PapelComprovante extends StatelessWidget {
  final Venda venda;
  final ConfigLoja loja;

  const _PapelComprovante({required this.venda, required this.loja});

  @override
  Widget build(BuildContext context) {
    final v = venda;
    const preto = Color(0xFF111111);
    const base = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12,
      color: preto,
      height: 1.35,
    );
    final forte = base.copyWith(fontWeight: FontWeight.bold);
    final cinza = base.copyWith(fontSize: 11, color: const Color(0xFF666666));
    Widget linha(String a, String b, {TextStyle? estilo}) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(a, style: estilo ?? base)),
        Text(b, style: estilo ?? base),
      ],
    );
    const tracos = Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Text(
        '--------------------------------',
        style: base,
        maxLines: 1,
        overflow: TextOverflow.clip,
      ),
    );
    final livre = (v.textoComprovante ?? '').trim();

    final List<Widget> conteudo;
    if (livre.isNotEmpty) {
      conteudo = [Text(livre, style: base)];
    } else {
      conteudo = [
        Center(
          child: FotoProduto(
            foto: loja.logo,
            nome: loja.nomeLoja,
            tamanho: 52,
            raio: 10,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          loja.nomeLoja,
          textAlign: TextAlign.center,
          style: forte.copyWith(fontSize: 14),
        ),
        for (final s in [loja.documento, loja.telefone, loja.endereco])
          if (s.trim().isNotEmpty)
            Text(s.trim(), textAlign: TextAlign.center, style: base),
        const SizedBox(height: 6),
        Text(
          'COMPROVANTE NÃO FISCAL',
          textAlign: TextAlign.center,
          style: forte,
        ),
        if (v.isCancelada)
          Text(
            'VENDA CANCELADA',
            textAlign: TextAlign.center,
            style: forte.copyWith(color: Colors.red.shade700, fontSize: 14),
          ),
        tracos,
        linha('Venda', '#${v.codigo}'),
        linha('Data', formatarDataHora(v.data)),
        linha('Atendente', v.vendedorNome),
        if (v.comandaNome != null) linha('Comanda', v.comandaNome!),
        if (v.clienteNome != null) linha('Cliente', v.clienteNome!),
        tracos,
        Row(
          children: [
            Expanded(child: Text('Item', style: forte)),
            SizedBox(width: 40, child: Text('Qtd.', style: forte)),
            Text('Total', style: forte),
          ],
        ),
        for (final i in v.itens)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(i.nome, style: base),
                      Text(
                        '${formatarMoeda(i.precoUnitario)} un.',
                        style: cinza,
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text('${i.quantidade}', style: base),
                ),
                Text(formatarMoeda(i.subtotal), style: base),
              ],
            ),
          ),
        tracos,
        linha('Subtotal', formatarMoeda(v.subtotal)),
        linha('Desconto', '- ${formatarMoeda(v.desconto)}'),
        linha(
          'Total',
          formatarMoeda(v.total),
          estilo: forte.copyWith(fontSize: 14),
        ),
        const SizedBox(height: 4),
        for (final (rotulo, valor) in linhasPagamentoComprovante(v))
          linha(rotulo, valor),
        if (v.isCancelada) ...[
          tracos,
          if (v.canceladaEm != null)
            Text(
              'Cancelada em ${formatarDataHora(v.canceladaEm!)}',
              style: forte,
            ),
          if ((v.motivoCancelamento ?? '').isNotEmpty)
            Text(v.motivoCancelamento!, style: base),
        ],
        if (loja.mensagemComprovante.trim().isNotEmpty) ...[
          tracos,
          Text(
            loja.mensagemComprovante.trim(),
            textAlign: TextAlign.center,
            style: base,
          ),
        ],
      ];
    }

    return Material(
      color: Colors.white,
      elevation: 3,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: conteudo,
        ),
      ),
    );
  }
}
