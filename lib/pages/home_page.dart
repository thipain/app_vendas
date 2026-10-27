import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/update/update_checker.dart';
import '../widgets/confirmar.dart';
import '../widgets/largura_maxima.dart';
import '../widgets/sync_status_icon.dart';
import 'clientes/clientes_page.dart';
import 'produtos/produtos_page.dart';
import 'vendas/vendas_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _destinos = [
    (titulo: 'Vendas', icone: Icons.point_of_sale),
    (titulo: 'Produtos', icone: Icons.inventory_2_outlined),
    (titulo: 'Clientes', icone: Icons.people_outline),
  ];
  static const _paginas = [VendasPage(), ProdutosPage(), ClientesPage()];

  int _indice = 0;

  Future<void> _menu(String opcao) async {
    switch (opcao) {
      case 'atualizar':
        await verificarAtualizacao(context, avisarSemNovidade: true);
      case 'sobre':
        final info = await PackageInfo.fromPlatform();
        if (!mounted) return;
        showAboutDialog(
          context: context,
          applicationName: 'App Vendas',
          applicationVersion: '${info.version} (${info.buildNumber})',
        );
      case 'sair':
        final ok = await confirmar(
          context,
          titulo: 'Sair',
          mensagem:
              'Vendas ainda não sincronizadas continuarão salvas neste '
              'aparelho e serão enviadas quando você entrar novamente com '
              'este mesmo usuário. Deseja sair?',
          confirmarTexto: 'Sair',
        );
        if (ok) await FirebaseAuth.instance.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    // No PC (tela larga) o menu fica na lateral; no celular, embaixo.
    final desktop = MediaQuery.sizeOf(context).width >= larguraDesktop;
    final paginas = IndexedStack(index: _indice, children: _paginas);
    return Scaffold(
      appBar: AppBar(
        title: Text(_destinos[_indice].titulo),
        actions: [
          const SyncStatusIcon(),
          PopupMenuButton<String>(
            onSelected: _menu,
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Text(FirebaseAuth.instance.currentUser?.email ?? ''),
              ),
              const PopupMenuItem(
                value: 'atualizar',
                child: Text('Verificar atualização'),
              ),
              const PopupMenuItem(value: 'sobre', child: Text('Sobre')),
              const PopupMenuItem(value: 'sair', child: Text('Sair')),
            ],
          ),
        ],
      ),
      body: desktop
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _indice,
                  onDestinationSelected: (i) => setState(() => _indice = i),
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final d in _destinos)
                      NavigationRailDestination(
                        icon: Icon(d.icone),
                        label: Text(d.titulo),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: paginas),
              ],
            )
          : paginas,
      bottomNavigationBar: desktop
          ? null
          : NavigationBar(
              selectedIndex: _indice,
              onDestinationSelected: (i) => setState(() => _indice = i),
              destinations: [
                for (final d in _destinos)
                  NavigationDestination(icon: Icon(d.icone), label: d.titulo),
              ],
            ),
    );
  }
}
