import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/update/update_checker.dart';
import '../widgets/confirmar.dart';
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
  static const _titulos = ['Vendas', 'Produtos', 'Clientes'];
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
          mensagem: 'Vendas ainda não sincronizadas continuarão salvas neste '
              'aparelho e serão enviadas quando você entrar novamente com '
              'este mesmo usuário. Deseja sair?',
          confirmarTexto: 'Sair',
        );
        if (ok) await FirebaseAuth.instance.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titulos[_indice]),
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
      body: IndexedStack(index: _indice, children: _paginas),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indice,
        onDestinationSelected: (i) => setState(() => _indice = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.point_of_sale), label: 'Vendas'),
          NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined), label: 'Produtos'),
          NavigationDestination(
              icon: Icon(Icons.people_outline), label: 'Clientes'),
        ],
      ),
    );
  }
}
