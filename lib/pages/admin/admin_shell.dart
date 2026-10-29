import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../data/sistema_repository.dart';
import '../../models/loja.dart';
import '../../widgets/confirmar.dart';
import '../../widgets/largura_maxima.dart';
import 'admin_comum.dart';
import 'auditoria_sistema_page.dart';
import 'avisos_page.dart';
import 'erros_app_page.dart';
import 'lojas_page.dart';
import 'mensalidades_page.dart';
import 'visao_geral_page.dart';

/// Painel administrativo do dono do sistema: lojas (clientes), mensalidades,
/// avisos e auditoria. Visual próprio, diferente do app das lojas.
class AdminShell extends StatefulWidget {
  const AdminShell({
    super.key,
    required this.minhasLojas,
    required this.onEntrarLoja,
  });

  /// Lojas em que o dono do sistema também é membro.
  final List<Vinculo> minhasLojas;

  /// Entra no app de uma loja (como membro ou como suporte).
  final ValueChanged<String> onEntrarLoja;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _Secao {
  final String titulo;
  final IconData icone;
  final Widget Function(ValueChanged<String> entrar) builder;

  const _Secao(this.titulo, this.icone, this.builder);
}

final _secoes = [
  _Secao(
    'Visão geral',
    Icons.space_dashboard_outlined,
    (e) => VisaoGeralPage(onEntrarLoja: e),
  ),
  _Secao('Lojas', Icons.storefront_outlined, (e) => LojasPage(onEntrarLoja: e)),
  _Secao(
    'Mensalidades',
    Icons.request_quote_outlined,
    (e) => MensalidadesPage(onEntrarLoja: e),
  ),
  _Secao('Avisos', Icons.campaign_outlined, (_) => const AvisosPage()),
  _Secao(
    'Erros do app',
    Icons.bug_report_outlined,
    (_) => const ErrosAppPage(),
  ),
  _Secao(
    'Auditoria do sistema',
    Icons.manage_search,
    (_) => const AuditoriaSistemaPage(),
  ),
];

class _AdminShellState extends State<AdminShell> {
  final _scaffold = GlobalKey<ScaffoldState>();
  int _atual = 0;

  void _selecionar(int i) {
    setState(() => _atual = i);
    if (_scaffold.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
  }

  /// Fecha as páginas empilhadas e entra na loja.
  void _entrar(String lojaId) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    widget.onEntrarLoja(lojaId);
  }

  Future<void> _escolherLoja() async {
    final id = await showDialog<String>(
      context: context,
      builder: (_) => _DialogEntrarLoja(minhasLojas: widget.minhasLojas),
    );
    if (id != null && mounted) _entrar(id);
  }

  Future<void> _conta(String opcao) async {
    if (opcao != 'sair') return;
    final ok = await confirmar(
      context,
      titulo: 'Sair',
      mensagem: 'Deseja sair do painel administrativo?',
      confirmarTexto: 'Sair',
    );
    if (ok) await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final desktop = MediaQuery.sizeOf(context).width >= larguraDesktop;
    final secao = _secoes[_atual];
    final menu = _Menu(atual: _atual, onSelecionar: _selecionar);
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    return Scaffold(
      key: _scaffold,
      drawer: desktop ? null : Drawer(child: menu),
      appBar: AppBar(
        backgroundColor: t.colorScheme.inverseSurface,
        foregroundColor: t.colorScheme.onInverseSurface,
        title: Row(
          children: [
            if (desktop) ...[
              const Icon(Icons.admin_panel_settings),
              const SizedBox(width: 8),
              const Text('Painel administrativo'),
              const SizedBox(width: 12),
              Text(
                '· ${secao.titulo}',
                style: TextStyle(
                  color: t.colorScheme.onInverseSurface.withValues(alpha: 0.7),
                ),
              ),
            ] else
              Flexible(
                child: Text(secao.titulo, overflow: TextOverflow.ellipsis),
              ),
          ],
        ),
        actions: [
          if (desktop)
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: t.colorScheme.onInverseSurface,
              ),
              onPressed: _escolherLoja,
              icon: const Icon(Icons.login),
              label: const Text('Entrar numa loja'),
            )
          else
            IconButton(
              tooltip: 'Entrar numa loja',
              icon: const Icon(Icons.login),
              onPressed: _escolherLoja,
            ),
          PopupMenuButton<String>(
            tooltip: 'Conta',
            icon: const Icon(Icons.account_circle_outlined),
            onSelected: _conta,
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Text('Dono do sistema\n$email'),
              ),
              const PopupMenuItem(value: 'sair', child: Text('Sair')),
            ],
          ),
        ],
      ),
      body: Row(
        children: [
          if (desktop) ...[
            SizedBox(width: 260, child: menu),
            const VerticalDivider(width: 1),
          ],
          Expanded(
            child: KeyedSubtree(
              key: ValueKey(_atual),
              child: secao.builder(_entrar),
            ),
          ),
        ],
      ),
    );
  }
}

class _Menu extends StatelessWidget {
  final int atual;
  final ValueChanged<int> onSelecionar;

  const _Menu({required this.atual, required this.onSelecionar});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    return Material(
      color: t.colorScheme.surfaceContainerLow,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: t.colorScheme.inverseSurface,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: t.colorScheme.tertiary,
                    foregroundColor: t.colorScheme.onTertiary,
                    child: const Icon(Icons.admin_panel_settings),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Painel administrativo',
                          style: t.textTheme.titleMedium?.copyWith(
                            color: t.colorScheme.onInverseSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: t.colorScheme.tertiary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'DONO DO SISTEMA',
                            style: t.textTheme.labelSmall?.copyWith(
                              color: t.colorScheme.onTertiary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                children: [
                  for (var i = 0; i < _secoes.length; i++)
                    ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      selected: i == atual,
                      selectedTileColor: t.colorScheme.tertiaryContainer,
                      selectedColor: t.colorScheme.onTertiaryContainer,
                      leading: Icon(_secoes[i].icone),
                      title: Text(_secoes[i].titulo),
                      onTap: () => onSelecionar(i),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: Text(email, overflow: TextOverflow.ellipsis),
              subtitle: const Text('Dono do sistema'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Escolhe uma loja para entrar: as minhas (membro) e as demais (suporte).
class _DialogEntrarLoja extends StatefulWidget {
  final List<Vinculo> minhasLojas;

  const _DialogEntrarLoja({required this.minhasLojas});

  @override
  State<_DialogEntrarLoja> createState() => _DialogEntrarLojaState();
}

class _DialogEntrarLojaState extends State<_DialogEntrarLoja> {
  late final Stream<List<Loja>> _lojas = SistemaRepository().watchLojas();
  String _busca = '';

  bool _confere(String nome) =>
      _busca.isEmpty || nome.toLowerCase().contains(_busca.toLowerCase());

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final minhasIds = widget.minhasLojas.map((v) => v.lojaId).toSet();
    return AlertDialog(
      title: const Text('Entrar numa loja'),
      contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      content: SizedBox(
        width: 460,
        height: 480,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Buscar loja',
                ),
                onChanged: (v) => setState(() => _busca = v.trim()),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder<List<Loja>>(
                stream: _lojas,
                builder: (context, snap) {
                  final lojas = snap.data ?? const <Loja>[];
                  final porId = {for (final l in lojas) l.id: l};
                  final minhas = widget.minhasLojas
                      .where(
                        (v) => _confere(porId[v.lojaId]?.nome ?? v.lojaNome),
                      )
                      .toList();
                  final outras = lojas
                      .where(
                        (l) => !minhasIds.contains(l.id) && _confere(l.nome),
                      )
                      .toList();
                  Widget item(String id, String nome, String rotulo, Loja? l) =>
                      ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            nome.isEmpty
                                ? '?'
                                : nome.characters.first.toUpperCase(),
                          ),
                        ),
                        title: Text(nome),
                        subtitle: Text(rotulo),
                        trailing: l == null ? null : SeloSituacao(l.situacao()),
                        onTap: () => Navigator.pop(context, id),
                      );
                  return ListView(
                    children: [
                      if (minhas.isNotEmpty) ...[
                        _Cabecalho('Minhas lojas', t),
                        for (final v in minhas)
                          item(
                            v.lojaId,
                            porId[v.lojaId]?.nome ?? v.lojaNome,
                            'Minha loja',
                            porId[v.lojaId],
                          ),
                      ],
                      if (outras.isNotEmpty) ...[
                        _Cabecalho('Outras lojas (suporte)', t),
                        for (final l in outras)
                          item(l.id, l.nome, 'Entrar como suporte', l),
                      ],
                      if (!snap.hasData && !snap.hasError)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      if (snap.hasError)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text('Erro ao carregar lojas: ${snap.error}'),
                        ),
                      if (snap.hasData && minhas.isEmpty && outras.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Nenhuma loja encontrada.'),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

class _Cabecalho extends StatelessWidget {
  final String texto;
  final ThemeData t;

  const _Cabecalho(this.texto, this.t);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(
      texto.toUpperCase(),
      style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.outline),
    ),
  );
}
