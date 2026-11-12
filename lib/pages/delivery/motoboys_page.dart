import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/dinheiro.dart';
import '../../core/formatters.dart';
import '../../core/regra_exception.dart';
import '../../core/sessao.dart';
import '../../data/config_repository.dart';
import '../../data/dados.dart';
import '../../data/motoboy_repository.dart';
import '../../models/config_loja.dart';
import '../../models/motoboy.dart';
import '../../models/pedido.dart';
import '../../models/usuario.dart';
import '../../widgets/largura_maxima.dart';
import '../../widgets/mensagens.dart';
import '../inicio/comum.dart';

/// Motoboys da loja: quantas entregas cada um fez desde o último fechamento,
/// quanto receber (diária + valor por entrega), o botão de fechar o dia
/// (zera a contagem) e o cadastro.
class MotoboysPage extends StatefulWidget {
  const MotoboysPage({super.key});

  @override
  State<MotoboysPage> createState() => _MotoboysPageState();
}

class _MotoboysPageState extends State<MotoboysPage> {
  final _repo = MotoboyRepository();
  late final _ultimo = _repo.watchUltimoFechamento();
  late final _historico = _repo.watchFechamentos();

  DateTime? _inicio;
  Stream<List<Pedido>>? _entregas;

  /// Diária ligada/desligada à mão (por motoboy). Sem escolha, recebe
  /// diária quem fez pelo menos uma entrega.
  final _diaria = <String, bool>{};

  static final _dataHora = DateFormat('dd/MM HH:mm');

  Stream<List<Pedido>> _streamDesde(DateTime inicio) {
    if (_inicio != inicio || _entregas == null) {
      _inicio = inicio;
      _entregas = _repo.watchEntregasDesde(inicio);
    }
    return _entregas!;
  }

  static DateTime _hoje() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  List<LinhaFechamento> _linhas(List<Pedido> pedidos, ConfigLoja c) {
    final contagem = <String, int>{};
    for (final p in pedidos) {
      final id = p.motoboyId;
      if (id != null) contagem[id] = (contagem[id] ?? 0) + 1;
    }
    final lista = Dados.motoboys.value
        .where((m) => m.ativo || (contagem[m.id] ?? 0) > 0)
        .toList();
    return [
      for (final m in lista)
        () {
          final n = contagem[m.id] ?? 0;
          final recebe = _diaria[m.id] ?? n > 0;
          return LinhaFechamento(
            motoboyId: m.id,
            nome: m.nome,
            entregas: n,
            diaria: recebe ? c.diariaMotoboy : 0,
            porEntrega: c.valorPorEntrega,
            total: deCentavos(
              pagamentoMotoboyCentavos(
                entregas: n,
                diaria: c.diariaMotoboy,
                porEntrega: c.valorPorEntrega,
                recebeDiaria: recebe,
              ),
            ),
          );
        }(),
    ];
  }

  Future<void> _fecharDia(DateTime inicio, List<LinhaFechamento> linhas) async {
    final total = linhas.fold<int>(0, (s, l) => s + centavos(l.total));
    final entregas = linhas.fold<int>(0, (s, l) => s + l.entregas);
    final caixa = Dados.caixaAberto.value;
    var pagarPeloCaixa = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Fechar o dia dos motoboys'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final l in linhas.where((l) => l.total > 0))
                  Row(
                    children: [
                      Expanded(
                        child: Text('${l.nome} (${l.entregas} entregas)'),
                      ),
                      Text(formatarMoeda(l.total)),
                    ],
                  ),
                const Divider(),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Total a pagar ($entregas entregas)',
                        style: Theme.of(ctx).textTheme.titleSmall,
                      ),
                    ),
                    Text(
                      formatarMoeda(deCentavos(total)),
                      style: Theme.of(ctx).textTheme.titleSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: pagarPeloCaixa,
                  onChanged: caixa == null || total == 0
                      ? null
                      : (v) => setState(() => pagarPeloCaixa = v ?? false),
                  title: const Text('Pagar com o dinheiro do caixa'),
                  subtitle: Text(
                    caixa == null
                        ? 'O caixa está fechado.'
                        : 'Registra uma sangria com o total.',
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'A contagem de entregas volta a zero e começa um novo dia. '
                  'O resumo fica guardado em "Dias anteriores".',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Fechar o dia e zerar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    if (executar(
      context,
      () => _repo.fecharDia(
        inicio: inicio,
        linhas: linhas,
        caixa: pagarPeloCaixa ? caixa : null,
      ),
      sucesso: 'Dia fechado. A contagem de entregas foi zerada.',
    )) {
      setState(_diaria.clear);
    }
  }

  Future<void> _editarValores(ConfigLoja c) async {
    final diaria = TextEditingController(text: valorParaCampo(c.diariaMotoboy));
    final porEntrega = TextEditingController(
      text: valorParaCampo(c.valorPorEntrega),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pagamento dos motoboys'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: diaria,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Diária (R\$)',
                helperText: 'Paga a quem trabalhou no dia.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: porEntrega,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Valor por entrega (R\$)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    final d = lerValor(diaria.text);
    final e = lerValor(porEntrega.text);
    diaria.dispose();
    porEntrega.dispose();
    if (ok != true || !mounted) return;
    executar(context, () {
      if (d == null || e == null) {
        throw const RegraException('Informe os dois valores.');
      }
      ConfigRepository.salvarPagamentoMotoboys(diaria: d, porEntrega: e);
    }, sucesso: 'Valores salvos.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Cadastrar motoboy'),
        onPressed: () => editarMotoboy(context),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          LarguraMaxima(
            largura: 760,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _secaoDia(),
                const TituloSecao('Motoboys cadastrados'),
                _secaoCadastro(),
                const TituloSecao('Dias anteriores'),
                _secaoHistorico(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _secaoDia() {
    final t = Theme.of(context);
    return StreamBuilder<FechamentoMotoboys?>(
      stream: _ultimo,
      builder: (context, snapUltimo) {
        if (snapUltimo.hasError) {
          return Text('Erro ao carregar: ${snapUltimo.error}');
        }
        if (snapUltimo.connectionState == ConnectionState.waiting &&
            !snapUltimo.hasData) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final inicio = snapUltimo.data?.fim ?? _hoje();
        return StreamBuilder<List<Pedido>>(
          stream: _streamDesde(inicio),
          builder: (context, snap) {
            if (snap.hasError) {
              return Text('Erro ao carregar: ${snap.error}');
            }
            return ValueListenableBuilder<List<Motoboy>>(
              valueListenable: Dados.motoboys,
              builder: (context, _, _) => ValueListenableBuilder<ConfigLoja>(
                valueListenable: ConfigRepository.atual,
                builder: (context, c, _) {
                  final linhas = _linhas(snap.data ?? const [], c);
                  final total = linhas.fold<int>(
                    0,
                    (s, l) => s + centavos(l.total),
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TituloSecao(
                        'Dia atual — desde ${_dataHora.format(inicio)}',
                      ),
                      Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: const Icon(Icons.payments_outlined),
                          title: Text(
                            'Diária ${formatarMoeda(c.diariaMotoboy)} + '
                            '${formatarMoeda(c.valorPorEntrega)} por entrega',
                          ),
                          subtitle:
                              c.diariaMotoboy == 0 && c.valorPorEntrega == 0
                              ? const Text('Defina os valores de pagamento.')
                              : null,
                          trailing: Sessao.instancia.isAdmin
                              ? TextButton(
                                  onPressed: () => _editarValores(c),
                                  child: const Text('Alterar'),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Card(
                        margin: EdgeInsets.zero,
                        child: Column(
                          children: [
                            if (linhas.isEmpty)
                              const ListTile(
                                title: Text('Nenhum motoboy cadastrado.'),
                              ),
                            for (final l in linhas)
                              ListTile(
                                leading: CircleAvatar(
                                  child: Text('${l.entregas}'),
                                ),
                                title: Text(l.nome),
                                subtitle: Text(
                                  '${l.entregas} entrega(s) · '
                                  '${l.diaria > 0 ? 'com diária' : 'sem diária'}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      formatarMoeda(l.total),
                                      style: t.textTheme.titleMedium,
                                    ),
                                    const SizedBox(width: 4),
                                    Tooltip(
                                      message: 'Pagar diária',
                                      child: Switch(
                                        value: l.diaria > 0,
                                        onChanged: (v) => setState(
                                          () => _diaria[l.motoboyId] = v,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const Divider(height: 1),
                            ListTile(
                              title: Text(
                                'Total a pagar',
                                style: t.textTheme.titleMedium,
                              ),
                              subtitle: Text(
                                '${linhas.fold<int>(0, (s, l) => s + l.entregas)} '
                                'entregas no dia',
                              ),
                              trailing: Text(
                                formatarMoeda(deCentavos(total)),
                                style: t.textTheme.titleLarge,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Conta os pedidos marcados como entregues desde o '
                        'último fechamento. A diária liga sozinha para quem '
                        'fez entrega; use a chave para ajustar.',
                        style: t.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('Fechar o dia e zerar'),
                        onPressed: linhas.isEmpty
                            ? null
                            : () => _fecharDia(inicio, linhas),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _secaoCadastro() {
    return ValueListenableBuilder<List<Motoboy>>(
      valueListenable: Dados.motoboys,
      builder: (context, lista, _) {
        if (lista.isEmpty) {
          return const Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: Icon(Icons.two_wheeler),
              title: Text('Nenhum motoboy cadastrado'),
              subtitle: Text('Use o botão "Cadastrar motoboy".'),
            ),
          );
        }
        final equipe = {for (final u in Dados.equipe.value) u.id: u};
        return Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (final m in lista)
                ListTile(
                  leading: CircleAvatar(child: Text(iniciais(m.nome))),
                  title: Text(m.ativo ? m.nome : '${m.nome} — desativado'),
                  subtitle: Text(
                    [
                      if (m.telefone.isNotEmpty) m.telefone,
                      m.usuarioId == null
                          ? 'sem login no app'
                          : 'login: ${equipe[m.usuarioId]?.email ?? '—'}',
                    ].join(' · '),
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => editarMotoboy(context, motoboy: m),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _secaoHistorico() {
    final t = Theme.of(context);
    return StreamBuilder<List<FechamentoMotoboys>>(
      stream: _historico,
      builder: (context, snap) {
        final lista = snap.data ?? const [];
        if (lista.isEmpty) {
          return Text(
            'Nenhum dia fechado ainda.',
            style: t.textTheme.bodySmall,
          );
        }
        return Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (final f in lista)
                ExpansionTile(
                  title: Text(
                    '${_dataHora.format(f.inicio)} até ${_dataHora.format(f.fim)}',
                  ),
                  subtitle: Text(
                    '${f.entregas} entregas · ${formatarMoeda(f.total)}'
                    '${f.pagoPeloCaixa ? ' · pago pelo caixa' : ''}'
                    '${f.porNome.isEmpty ? '' : ' · ${f.porNome}'}',
                  ),
                  children: [
                    for (final l in f.linhas)
                      ListTile(
                        dense: true,
                        title: Text(l.nome),
                        subtitle: Text(
                          '${l.entregas} × ${formatarMoeda(l.porEntrega)}'
                          '${l.diaria > 0 ? ' + diária ${formatarMoeda(l.diaria)}' : ''}',
                        ),
                        trailing: Text(formatarMoeda(l.total)),
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Cadastro ou edição de um motoboy.
Future<void> editarMotoboy(BuildContext context, {Motoboy? motoboy}) async {
  final nome = TextEditingController(text: motoboy?.nome);
  final telefone = TextEditingController(text: motoboy?.telefone);
  var ativo = motoboy?.ativo ?? true;
  String? usuarioId = motoboy?.usuarioId;
  final logins = Dados.equipe.value
      .where((u) => u.isEntregador || u.id == usuarioId)
      .toList();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(motoboy == null ? 'Cadastrar motoboy' : 'Editar motoboy'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nome,
                autofocus: true,
                maxLength: 60,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nome *'),
              ),
              TextField(
                controller: telefone,
                maxLength: 30,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Telefone / WhatsApp',
                ),
              ),
              DropdownButtonFormField<String?>(
                initialValue: usuarioId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Login no app (opcional)',
                  helperText:
                      'Com login, ele vê no celular os pedidos que levar. '
                      'Crie o login em Equipe, com o nível Entregador.',
                  helperMaxLines: 3,
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Sem login'),
                  ),
                  for (final Usuario u in logins)
                    DropdownMenuItem<String?>(
                      value: u.id,
                      child: Text('${u.nome} (${u.email})'),
                    ),
                ],
                onChanged: (v) => setState(() => usuarioId = v),
              ),
              if (motoboy != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ativo'),
                  subtitle: const Text(
                    'Desativado não aparece para despachar pedidos.',
                  ),
                  value: ativo,
                  onChanged: (v) => setState(() => ativo = v),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    ),
  );
  final dados = Motoboy(
    id: motoboy?.id ?? '',
    nome: nome.text,
    telefone: telefone.text,
    ativo: ativo,
    usuarioId: usuarioId,
  );
  nome.dispose();
  telefone.dispose();
  if (ok != true || !context.mounted) return;
  executar(
    context,
    () => MotoboyRepository().salvar(dados, Dados.motoboys.value),
    sucesso: motoboy == null ? 'Motoboy cadastrado.' : 'Motoboy alterado.',
  );
}
