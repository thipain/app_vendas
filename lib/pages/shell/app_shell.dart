import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/permissoes.dart';
import '../../core/sessao.dart';
import '../../core/update/update_checker.dart';
import '../../data/auditoria_repository.dart';
import '../../data/config_repository.dart';
import '../../data/dados.dart';
import '../../models/config_loja.dart';
import '../../models/produto.dart';
import '../../widgets/confirmar.dart';
import '../../widgets/foto_produto.dart';
import '../../widgets/largura_maxima.dart';
import '../../widgets/sync_status_icon.dart';
import '../calculadora/calculadora_page.dart';
import 'modulos.dart';

/// Estrutura principal: menu lateral agrupado (fixo no PC, gaveta no
/// celular), barra superior com atalhos e o módulo selecionado.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  /// Abre um módulo a partir de qualquer tela (ex.: atalho do painel).
  static void abrir(BuildContext context, String id, {Object? argumento}) {
    context
        .findAncestorStateOfType<_AppShellState>()
        ?._abrir(id, argumento: argumento);
  }

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _scaffold = GlobalKey<ScaffoldState>();
  late Modulo _atual;
  Object? _argumento;

  /// Muda a cada abertura para recriar a página com o novo argumento.
  int _versao = 0;

  List<Modulo> get _permitidos =>
      modulos.where((m) => Sessao.instancia.pode(m.permissao)).toList();

  @override
  void initState() {
    super.initState();
    final p = _permitidos;
    _atual = p.firstWhere((m) => m.id == 'dashboard',
        orElse: () => p.firstWhere((m) => m.id == 'vendas'));
  }

  void _abrir(String id, {Object? argumento}) {
    final m = _permitidos.where((m) => m.id == id).firstOrNull;
    if (m == null) return;
    setState(() {
      _atual = m;
      _argumento = argumento;
      _versao++;
    });
    if (_scaffold.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _menuUsuario(String opcao) async {
    switch (opcao) {
      case 'perfil':
        _abrir('perfil');
      case 'atualizar':
        await verificarAtualizacao(context, avisarSemNovidade: true);
      case 'sobre':
        final info = await PackageInfo.fromPlatform();
        if (!mounted) return;
        showAboutDialog(
          context: context,
          applicationName: ConfigRepository.atual.value.nomeSistema,
          applicationVersion: '${info.version} (${info.buildNumber})',
        );
      case 'sair':
        final ok = await confirmar(
          context,
          titulo: 'Sair',
          mensagem: 'Operações ainda não sincronizadas continuarão salvas '
              'neste aparelho e serão enviadas quando você entrar novamente '
              'com este mesmo usuário. Deseja sair?',
          confirmarTexto: 'Sair',
        );
        if (!ok) return;
        AuditoriaRepository.registrar('auth.logout', 'Saída do sistema');
        Dados.parar();
        await FirebaseAuth.instance.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= larguraDesktop;
    final menu = _Menu(
      atual: _atual.id,
      modulos: _permitidos,
      onSelecionar: (m) => _abrir(m.id),
      onPerfil: () => _abrir('perfil'),
    );
    final eu = Sessao.instancia.atual;
    return Scaffold(
      key: _scaffold,
      drawer: desktop ? null : Drawer(child: menu),
      appBar: AppBar(
        title: Text(_atual.titulo),
        actions: [
          if (desktop)
            ValueListenableBuilder<ConfigLoja>(
              valueListenable: ConfigRepository.atual,
              builder: (_, c, _) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Chip(
                  avatar: const Icon(Icons.circle, size: 10, color: Colors.green),
                  label: Text(c.statusLoja),
                ),
              ),
            ),
          const SyncStatusIcon(),
          if (Sessao.instancia.pode(Permissao.calculadora))
            IconButton(
              tooltip: 'Calculadora',
              icon: const Icon(Icons.calculate_outlined),
              onPressed: () => mostrarCalculadora(context),
            ),
          if (Sessao.instancia.pode(Permissao.notificacoes))
            ValueListenableBuilder<List<Produto>>(
              valueListenable: Dados.produtos,
              builder: (_, _, _) {
                final n = Dados.produtosEmAlerta.length;
                return IconButton(
                  tooltip: n == 0
                      ? 'Nenhum alerta de estoque'
                      : '$n item(ns) com estoque baixo',
                  icon: Badge(
                    isLabelVisible: n > 0,
                    label: Text(n > 99 ? '99+' : '$n'),
                    child: const Icon(Icons.notifications_outlined),
                  ),
                  onPressed: () => _abrir('notificacoes'),
                );
              },
            ),
          PopupMenuButton<String>(
            tooltip: 'Conta',
            onSelected: _menuUsuario,
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Text('${eu.nome}\n${eu.email}'),
              ),
              const PopupMenuItem(value: 'perfil', child: Text('Meu perfil')),
              const PopupMenuItem(
                  value: 'atualizar', child: Text('Verificar atualização')),
              const PopupMenuItem(value: 'sobre', child: Text('Sobre')),
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
              key: ValueKey('${_atual.id}-$_versao'),
              child: _atual.builder(_argumento),
            ),
          ),
        ],
      ),
    );
  }
}

class _Menu extends StatelessWidget {
  final String atual;
  final List<Modulo> modulos;
  final ValueChanged<Modulo> onSelecionar;
  final VoidCallback onPerfil;

  const _Menu({
    required this.atual,
    required this.modulos,
    required this.onSelecionar,
    required this.onPerfil,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final eu = Sessao.instancia.atual;
    final grupos = [Grupos.operacao, Grupos.estoque, Grupos.gestao];
    return Material(
      color: t.colorScheme.surfaceContainerLow,
      child: SafeArea(
        child: Column(
          children: [
            ValueListenableBuilder<ConfigLoja>(
              valueListenable: ConfigRepository.atual,
              builder: (_, c, _) => ListTile(
                contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                leading: FotoProduto(
                    foto: c.logo, nome: c.nomeLoja, tamanho: 40, raio: 10),
                title: Text(c.nomeLoja,
                    style: t.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    '${c.nomeSistema} · ${DateFormat('dd/MM/yyyy').format(DateTime.now())}'),
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final g in grupos)
                    if (modulos.any((m) => m.grupo == g && m.noMenu)) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                        child: Text(g.toUpperCase(),
                            style: t.textTheme.labelSmall
                                ?.copyWith(color: t.colorScheme.outline)),
                      ),
                      for (final m
                          in modulos.where((m) => m.grupo == g && m.noMenu))
                        ListTile(
                          dense: true,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24)),
                          selected: m.id == atual,
                          selectedTileColor: t.colorScheme.secondaryContainer,
                          leading: Icon(m.icone),
                          title: Text(m.titulo),
                          trailing: m.permissao == Permissao.admin
                              ? Text('ADM', style: t.textTheme.labelSmall)
                              : null,
                          onTap: () => onSelecionar(m),
                        ),
                    ],
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: CircleAvatar(
                child: Text(eu.nome.length >= 2
                    ? eu.nome.substring(0, 2).toUpperCase()
                    : eu.nome.toUpperCase()),
              ),
              title: Text(eu.nome, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                  eu.isAdmin ? 'Administrador' : 'Acesso personalizado'),
              onTap: onPerfil,
            ),
          ],
        ),
      ),
    );
  }
}
