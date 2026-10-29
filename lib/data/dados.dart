import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/sessao.dart';
import '../models/caixa.dart';
import '../models/produto.dart';
import '../models/usuario.dart';
import 'caixa_repository.dart';
import 'config_repository.dart';
import 'estoque.dart';
import 'produto_repository.dart';
import 'usuario_repository.dart';

/// Dados usados por várias telas ao mesmo tempo, mantidos em memória enquanto
/// o usuário está logado (um único listener do Firestore para cada um).
class Dados {
  /// Todos os produtos, ativos e desativados, em ordem alfabética.
  static final produtos = ValueNotifier<List<Produto>>(const []);

  /// Caixa aberto no momento (null = caixa fechado).
  static final caixaAberto = ValueNotifier<Caixa?>(null);

  /// Equipe completa (usada em retiradas, ponto e equipe).
  static final equipe = ValueNotifier<List<Usuario>>(const []);

  static final _subs = <StreamSubscription<Object?>>[];

  static List<Produto> get produtosAtivos =>
      produtos.value.where((p) => p.ativo).toList();

  static Map<String, Produto> get produtosPorId =>
      Estoque.porId(produtos.value);

  /// Produtos ativos com estoque no mínimo ou abaixo (inclui zerados).
  static List<Produto> get produtosEmAlerta =>
      produtosAtivos.where((p) => p.estoque <= p.estoqueMinimo).toList()
        ..sort((a, b) => a.estoque.compareTo(b.estoque));

  static void iniciar() {
    parar();
    ConfigRepository.iniciar();
    _subs.add(
      ProdutoRepository().watchTodos().listen(
        (l) => produtos.value = l,
        onError: (Object e) => debugPrint('Produtos: $e'),
      ),
    );
    _subs.add(
      CaixaRepository().watchAberto().listen(
        (c) => caixaAberto.value = c,
        onError: (Object e) => debugPrint('Caixa: $e'),
      ),
    );
    if (Sessao.instancia.isAdmin) {
      ProdutoRepository().removerFotosAntigas().catchError(
        (Object e) => debugPrint('Limpeza de fotos: $e'),
      );
    }
    _subs.add(
      UsuarioRepository().watchTodos().listen(
        (l) => equipe.value = l,
        onError: (Object e) => debugPrint('Equipe: $e'),
      ),
    );
  }

  static void parar() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    ConfigRepository.parar();
    produtos.value = const [];
    caixaAberto.value = null;
    equipe.value = const [];
  }

  /// Funcionários ativos (para escolher em retiradas).
  static List<Usuario> get equipeAtiva =>
      equipe.value.where((u) => u.ativo).toList();

  static Usuario get eu => Sessao.instancia.atual;
}
