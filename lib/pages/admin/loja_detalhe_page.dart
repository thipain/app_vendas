import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../data/sistema_repository.dart';
import '../../models/loja.dart';
import '../../widgets/largura_maxima.dart';
import '../../widgets/mensagens.dart';
import '../inicio/comum.dart';
import 'admin_comum.dart';
import 'loja_form_page.dart';

/// Detalhes de uma loja: situação, cobrança, ações e histórico de pagamentos.
class LojaDetalhePage extends StatefulWidget {
  final Loja loja;
  final ValueChanged<String> onEntrarLoja;

  const LojaDetalhePage({
    super.key,
    required this.loja,
    required this.onEntrarLoja,
  });

  @override
  State<LojaDetalhePage> createState() => _LojaDetalhePageState();
}

class _LojaDetalhePageState extends State<LojaDetalhePage> {
  final _repo = SistemaRepository();
  late final Stream<Loja?> _loja = _repo.watchLoja(widget.loja.id);
  late final Stream<List<PagamentoLoja>> _pagamentos = _repo
      .watchPagamentosDaLoja(widget.loja.id);

  Future<void> _editar(Loja l) async {
    final ok = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => LojaFormPage(loja: l)));
    if (ok == true && mounted) avisar(context, 'Cadastro salvo.');
  }

  void _entrarComoSuporte(Loja l) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    widget.onEntrarLoja(l.id);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Loja?>(
      stream: _loja,
      initialData: widget.loja,
      builder: (context, snap) {
        final l = snap.data ?? widget.loja;
        return Scaffold(
          appBar: AppBar(
            title: Text(l.nome),
            actions: [
              IconButton(
                tooltip: 'Editar cadastro e cobrança',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _editar(l),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              LarguraMaxima(
                largura: 900,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (snap.hasError)
                      Text(
                        'Erro ao atualizar: ${snap.error}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    _situacao(context, l),
                    _acoes(context, l),
                    _cadastro(context, l),
                    const TituloSecao('Histórico de pagamentos'),
                    _historico(context),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _situacao(BuildContext context, Loja l) {
    final t = Theme.of(context);
    final s = l.situacao();
    final cor = corSituacao(context, s);
    final venc = l.pagoAte;
    final trava = l.travaEm;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cor.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(iconeSituacao(s), color: cor, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    s.rotulo,
                    style: t.textTheme.titleLarge?.copyWith(color: cor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 32,
              runSpacing: 12,
              children: [
                _Info(
                  'Vencimento',
                  venc == null ? 'Sem cobrança' : formatoData.format(venc),
                  venc == null ? null : textoVencimento(l),
                ),
                if (trava != null)
                  _Info(
                    'Trava em',
                    formatoData.format(trava),
                    '${l.carenciaDias} dia(s) de carência',
                  ),
                _Info(
                  'Mensalidade',
                  l.valorMensal > 0 ? formatarMoeda(l.valorMensal) : '—',
                  l.emTeste ? 'em teste grátis' : null,
                ),
                _Info('Plano', l.plano.rotulo, l.plano.descricaoLimite),
                if (!l.ativa)
                  _Info(
                    'Travada manualmente',
                    l.travadaEm == null
                        ? 'Sim'
                        : formatarDataHora(l.travadaEm!),
                    null,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Exclusão definitiva: pede para digitar o nome da loja.
  Future<void> _excluir(Loja l) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmarExclusao(loja: l),
    );
    if (confirmado != true || !mounted) return;
    final etapa = ValueNotifier<String>('Preparando...');
    final nav = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: ValueListenableBuilder<String>(
            valueListenable: etapa,
            builder: (_, e, _) => Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 16),
                Expanded(child: Text(e)),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      await SistemaRepository().excluirLoja(
        l,
        progresso: (e) => etapa.value = e,
      );
      nav.pop();
      if (!mounted) return;
      avisar(context, 'Loja ${l.nome} excluída.');
      Navigator.of(context).pop();
    } catch (e) {
      nav.pop();
      if (mounted) mostrarErro(context, e);
    }
  }

  Widget _acoes(BuildContext context, Loja l) {
    final temFone = telefoneWhatsApp(l) != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: () => registrarPagamento(context, l),
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Registrar pagamento'),
          ),
          OutlinedButton.icon(
            onPressed: temFone ? () => cobrarNoWhatsApp(context, l) : null,
            icon: const Icon(Icons.chat_outlined),
            label: Text(
              temFone ? 'Cobrar no WhatsApp' : 'Sem telefone para cobrar',
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => alternarTrava(context, l),
            style: l.ativa
                ? OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  )
                : null,
            icon: Icon(l.ativa ? Icons.lock_outline : Icons.lock_open),
            label: Text(l.ativa ? 'Travar' : 'Liberar'),
          ),
          OutlinedButton.icon(
            onPressed: () => _editar(l),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Editar cadastro e cobrança'),
          ),
          OutlinedButton.icon(
            onPressed: () => adicionarAdministrador(context, l),
            icon: const Icon(Icons.person_add_alt_outlined),
            label: const Text('Adicionar administrador'),
          ),
          OutlinedButton.icon(
            onPressed: () => _entrarComoSuporte(l),
            icon: const Icon(Icons.support_agent),
            label: const Text('Entrar como suporte'),
          ),
          TextButton.icon(
            onPressed: () => _excluir(l),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('Excluir loja'),
          ),
        ],
      ),
    );
  }

  Widget _cadastro(BuildContext context, Loja l) {
    String ou(String v) => v.trim().isEmpty ? '—' : v;
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(ou(l.responsavelNome)),
            subtitle: const Text('Responsável'),
          ),
          ListTile(
            leading: const Icon(Icons.phone_outlined),
            title: Text(ou(l.responsavelTelefone)),
            subtitle: const Text('Telefone / WhatsApp'),
          ),
          ListTile(
            leading: const Icon(Icons.email_outlined),
            title: Text(ou(l.responsavelEmail)),
            subtitle: const Text('E-mail'),
          ),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: Text(ou(l.documento)),
            subtitle: const Text('CPF / CNPJ'),
          ),
          if (l.observacoes.trim().isNotEmpty)
            ListTile(
              leading: const Icon(Icons.notes),
              title: Text(l.observacoes),
              subtitle: const Text('Observações'),
            ),
          ListTile(
            leading: const Icon(Icons.event_available_outlined),
            title: Text(
              l.criadaEm == null ? '—' : formatoData.format(l.criadaEm!),
            ),
            subtitle: const Text('Cliente desde'),
          ),
        ],
      ),
    );
  }

  Widget _historico(BuildContext context) {
    return StreamBuilder<List<PagamentoLoja>>(
      stream: _pagamentos,
      builder: (context, snap) {
        if (snap.hasError) return Text('Erro: ${snap.error}');
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final pags = snap.data!;
        if (pags.isEmpty) {
          return const Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: Icon(Icons.receipt_long_outlined),
              title: Text('Nenhum pagamento registrado.'),
            ),
          );
        }
        final total = pags.fold<double>(0, (s, p) => s + p.valor);
        return Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                title: Text('Total recebido: ${formatarMoeda(total)}'),
                subtitle: Text('${pags.length} pagamento(s)'),
              ),
              for (final p in pags) ...[
                const Divider(height: 1),
                LinhaPagamento(p, mostrarLoja: false),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Info extends StatelessWidget {
  final String rotulo;
  final String valor;
  final String? detalhe;

  const _Info(this.rotulo, this.valor, this.detalhe);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          rotulo,
          style: t.textTheme.labelMedium?.copyWith(
            color: t.colorScheme.outline,
          ),
        ),
        Text(
          valor,
          style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        if (detalhe != null) Text(detalhe!, style: t.textTheme.bodySmall),
      ],
    );
  }
}

/// Linha de um pagamento de mensalidade.
class LinhaPagamento extends StatelessWidget {
  final PagamentoLoja pagamento;
  final bool mostrarLoja;
  final VoidCallback? onTap;

  const LinhaPagamento(
    this.pagamento, {
    super.key,
    this.mostrarLoja = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = pagamento;
    return ListTile(
      onTap: onTap,
      leading: const CircleAvatar(child: Icon(Icons.payments_outlined)),
      title: Text(
        mostrarLoja
            ? '${p.lojaNome} · ${formatarMoeda(p.valor)}'
            : formatarMoeda(p.valor),
      ),
      subtitle: Text(
        [
          formatoData.format(p.data),
          p.meses == 1 ? '1 mês' : '${p.meses} meses',
          if (p.forma.isNotEmpty) p.forma,
          'novo vencimento ${formatoData.format(p.novoVencimento)}',
          if (p.observacao.isNotEmpty) p.observacao,
        ].join(' · '),
      ),
    );
  }
}

class _ConfirmarExclusao extends StatefulWidget {
  final Loja loja;
  const _ConfirmarExclusao({required this.loja});

  @override
  State<_ConfirmarExclusao> createState() => _ConfirmarExclusaoState();
}

class _ConfirmarExclusaoState extends State<_ConfirmarExclusao> {
  final _nome = TextEditingController();

  @override
  void dispose() {
    _nome.dispose();
    super.dispose();
  }

  bool get _confere =>
      _nome.text.trim().toLowerCase() == widget.loja.nome.trim().toLowerCase();

  @override
  Widget build(BuildContext context) {
    final erro = Theme.of(context).colorScheme.error;
    return AlertDialog(
      icon: Icon(Icons.delete_forever_outlined, color: erro),
      title: const Text('Excluir loja definitivamente'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Todos os dados da ${widget.loja.nome} serão apagados do '
              'Firebase: produtos, vendas, caixa, comandas, estoque, notas, '
              'equipe, ponto e configurações. Não é possível desfazer.',
            ),
            const SizedBox(height: 8),
            const Text(
              'O histórico de mensalidades e a auditoria do sistema são '
              'mantidos. As contas de acesso (e-mail e senha) continuam '
              'existindo, mas sem nenhuma loja vinculada.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nome,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Digite "${widget.loja.nome}" para confirmar',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: erro),
          onPressed: _confere ? () => Navigator.pop(context, true) : null,
          child: const Text('Excluir'),
        ),
      ],
    );
  }
}
