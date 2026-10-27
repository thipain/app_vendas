import 'package:flutter/material.dart';

import '../../core/permissoes.dart';
import '../auditoria/auditoria_page.dart';
import '../caixa/caixa_page.dart';
import '../calculadora/calculadora_page.dart';
import '../clientes/clientes_page.dart';
import '../comandas/comandas_page.dart';
import '../configuracoes/configuracoes_page.dart';
import '../equipe/equipe_page.dart';
import '../estoque/movimentacoes_page.dart';
import '../estoque/notas_entrada_page.dart';
import '../estoque/notificacoes_page.dart';
import '../estoque/transformacoes_page.dart';
import '../inicio/dashboard_page.dart';
import '../perfil/perfil_page.dart';
import '../ponto/meu_ponto_page.dart';
import '../ponto/ponto_equipe_page.dart';
import '../produtos/produtos_page.dart';
import '../relatorios/relatorios_page.dart';
import '../retiradas/retiradas_page.dart';
import '../vendas/historico_vendas_page.dart';
import '../vendas/pdv_page.dart';

/// Uma área do sistema no menu lateral.
///
/// As páginas dos módulos devolvem um Scaffold SEM AppBar: o título, o menu
/// e os atalhos ficam na barra do AppShell.
class Modulo {
  final String id;
  final String titulo;
  final IconData icone;
  final String permissao;
  final String grupo;
  final bool noMenu;

  /// [argumento] permite abrir o módulo já filtrado (ex.: estoque "zerados").
  final Widget Function(Object? argumento) builder;

  const Modulo({
    required this.id,
    required this.titulo,
    required this.icone,
    required this.permissao,
    required this.grupo,
    required this.builder,
    this.noMenu = true,
  });
}

class Grupos {
  static const operacao = 'Operação diária';
  static const estoque = 'Produtos e estoque';
  static const gestao = 'Gestão';
}

final modulos = <Modulo>[
  Modulo(
    id: 'dashboard',
    titulo: 'Visão geral',
    icone: Icons.space_dashboard_outlined,
    permissao: Permissao.dashboard,
    grupo: Grupos.operacao,
    builder: (_) => const DashboardPage(),
  ),
  Modulo(
    id: 'caixa',
    titulo: 'Abrir e fechar caixa',
    icone: Icons.point_of_sale_outlined,
    permissao: Permissao.caixa,
    grupo: Grupos.operacao,
    builder: (_) => const CaixaPage(),
  ),
  Modulo(
    id: 'vendas',
    titulo: 'Nova venda',
    icone: Icons.shopping_cart_outlined,
    permissao: Permissao.vendas,
    grupo: Grupos.operacao,
    builder: (arg) => PdvPage(comandaId: arg as String?),
  ),
  Modulo(
    id: 'comandas',
    titulo: 'Comandas',
    icone: Icons.receipt_long_outlined,
    permissao: Permissao.comandas,
    grupo: Grupos.operacao,
    builder: (_) => const ComandasPage(),
  ),
  Modulo(
    id: 'retiradas',
    titulo: 'Retirada de funcionário',
    icone: Icons.local_drink_outlined,
    permissao: Permissao.retiradas,
    grupo: Grupos.operacao,
    builder: (_) => const RetiradasPage(),
  ),
  Modulo(
    id: 'meu_ponto',
    titulo: 'Meu ponto',
    icone: Icons.fingerprint,
    permissao: Permissao.meuPonto,
    grupo: Grupos.operacao,
    builder: (_) => const MeuPontoPage(),
  ),
  Modulo(
    id: 'clientes',
    titulo: 'Clientes',
    icone: Icons.people_outline,
    permissao: Permissao.clientes,
    grupo: Grupos.operacao,
    builder: (_) => const ClientesPage(),
  ),
  Modulo(
    id: 'estoque',
    titulo: 'Produtos e estoque',
    icone: Icons.inventory_2_outlined,
    permissao: Permissao.estoque,
    grupo: Grupos.estoque,
    builder: (arg) => ProdutosPage(filtroInicial: arg as String?),
  ),
  Modulo(
    id: 'notificacoes',
    titulo: 'Notificações de estoque',
    icone: Icons.notifications_outlined,
    permissao: Permissao.notificacoes,
    grupo: Grupos.estoque,
    builder: (_) => const NotificacoesPage(),
  ),
  Modulo(
    id: 'transformacoes',
    titulo: 'Montagem e desmanche',
    icone: Icons.call_split,
    permissao: Permissao.transformacoes,
    grupo: Grupos.estoque,
    builder: (_) => const TransformacoesPage(),
  ),
  Modulo(
    id: 'entradas',
    titulo: 'Notas de entrada',
    icone: Icons.local_shipping_outlined,
    permissao: Permissao.entradas,
    grupo: Grupos.estoque,
    builder: (_) => const NotasEntradaPage(),
  ),
  Modulo(
    id: 'movimentacoes',
    titulo: 'Histórico do estoque',
    icone: Icons.swap_vert,
    permissao: Permissao.movimentacoes,
    grupo: Grupos.estoque,
    builder: (_) => const MovimentacoesPage(),
  ),
  Modulo(
    id: 'historico',
    titulo: 'Histórico de vendas',
    icone: Icons.history,
    permissao: Permissao.historico,
    grupo: Grupos.gestao,
    builder: (_) => const HistoricoVendasPage(),
  ),
  Modulo(
    id: 'ponto_equipe',
    titulo: 'Ponto da equipe',
    icone: Icons.badge_outlined,
    permissao: Permissao.pontoEquipe,
    grupo: Grupos.gestao,
    builder: (_) => const PontoEquipePage(),
  ),
  Modulo(
    id: 'relatorios',
    titulo: 'Relatórios e lucro',
    icone: Icons.bar_chart,
    permissao: Permissao.relatorios,
    grupo: Grupos.gestao,
    builder: (_) => const RelatoriosPage(),
  ),
  Modulo(
    id: 'auditoria',
    titulo: 'Auditoria',
    icone: Icons.policy_outlined,
    permissao: Permissao.auditoria,
    grupo: Grupos.gestao,
    builder: (_) => const AuditoriaPage(),
  ),
  Modulo(
    id: 'equipe',
    titulo: 'Equipe e acessos',
    icone: Icons.manage_accounts_outlined,
    permissao: Permissao.admin,
    grupo: Grupos.gestao,
    builder: (_) => const EquipePage(),
  ),
  Modulo(
    id: 'configuracoes',
    titulo: 'Configurações',
    icone: Icons.settings_outlined,
    permissao: Permissao.admin,
    grupo: Grupos.gestao,
    builder: (_) => const ConfiguracoesPage(),
  ),
  Modulo(
    id: 'calculadora',
    titulo: 'Calculadora',
    icone: Icons.calculate_outlined,
    permissao: Permissao.calculadora,
    grupo: Grupos.gestao,
    noMenu: false,
    builder: (_) => const CalculadoraPage(),
  ),
  Modulo(
    id: 'perfil',
    titulo: 'Meu perfil',
    icone: Icons.person_outline,
    permissao: Permissao.vendas,
    grupo: Grupos.gestao,
    noMenu: false,
    builder: (_) => const PerfilPage(),
  ),
];
