import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/config.dart';
import '../core/regra_exception.dart';
import '../core/sessao.dart';
import '../models/config_loja.dart';
import '../models/produto.dart';
import 'auditoria_repository.dart';
import 'banco.dart';
import 'config_repository.dart';
import 'dados.dart';
import 'offline.dart';

/// Loja online: dados públicos que a página do cliente lê sem login de
/// funcionário. Fica fora de `lojas/{id}` (que é privado):
///
/// - `lojasPublicas/{lojaId}`: nome, logo, taxa, formas de pagamento, chave
///   Pix, pedido mínimo, horário e se está aberta agora;
/// - `lojasPublicas/{lojaId}/cardapio/atual`: produtos marcados para a loja
///   online (nome, preço, categoria e se está disponível; sem estoque nem
///   custo);
/// - `slugs/{link}`: link da loja → id da loja.
class LojaOnlineRepository {
  static final _db = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> get publica =>
      _db.collection('lojasPublicas').doc(Banco.lojaId);
  static DocumentReference<Map<String, dynamic>> get _cardapio =>
      publica.collection('cardapio').doc('atual');
  static CollectionReference<Map<String, dynamic>> get _slugs =>
      _db.collection('slugs');

  static final _slugValido = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

  static String linkDaLoja(String slug) => '${AppConfig.urlLojaOnline}/$slug';

  /// Sugere um link a partir do nome ("Adega do Zé" → "adega-do-ze").
  static String sugerirSlug(String nome) {
    const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const para = 'aaaaaeeeeiiiiooooouuuucn';
    final b = StringBuffer();
    for (final r in nome.toLowerCase().runes) {
      final c = String.fromCharCode(r);
      final i = de.indexOf(c);
      b.write(i >= 0 ? para[i] : c);
    }
    return b
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  static String validarSlug(String slug) {
    final s = slug.trim().toLowerCase();
    if (s.length < 3 || s.length > 40 || !_slugValido.hasMatch(s)) {
      throw const RegraException(
        'O link da loja deve ter de 3 a 40 letras minúsculas, números e '
        'hífens (ex.: adega-do-ze).',
      );
    }
    return s;
  }

  /// Reserva o link para esta loja (precisa de internet). Libera o link
  /// antigo quando ele muda.
  static Future<void> reservarSlug(String novo, {String antigo = ''}) async {
    final s = validarSlug(novo);
    final lojaId = Banco.lojaId;
    await _db.runTransaction((tx) async {
      final ref = _slugs.doc(s);
      final atual = await tx.get(ref);
      final dono = atual.data()?['lojaId'] as String?;
      if (atual.exists && dono != lojaId) {
        throw const RegraException(
          'Este link já é usado por outra loja. Escolha outro.',
        );
      }
      if (!atual.exists) tx.set(ref, {'lojaId': lojaId});
      if (antigo.isNotEmpty && antigo != s) {
        final velho = await tx.get(_slugs.doc(antigo));
        if (velho.data()?['lojaId'] == lojaId) tx.delete(_slugs.doc(antigo));
      }
    });
  }

  /// Se a loja online está aceitando pedidos agora.
  static Stream<bool> watchAberta() =>
      publica.snapshots().map((d) => d.data()?['aberta'] as bool? ?? false);

  static void definirAberta(bool aberta) {
    final batch = _db.batch();
    batch.set(publica, {
      'aberta': aberta,
      'abertaAlteradaEm': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    AuditoriaRepository.noBatch(
      batch,
      aberta ? 'online.open' : 'online.close',
      aberta ? 'Loja online aberta' : 'Loja online fechada',
      entidade: 'lojaOnline',
      entidadeId: Banco.lojaId,
    );
    semAguardar(batch.commit(), 'abrir/fechar loja online');
  }

  // ---------------------------------------------------------------------
  // Publicação automática do cardápio e dos dados da loja.

  static final _subs = <void Function()>[];
  static Timer? _espera;
  static String? _ultimaInfo;
  static String? _ultimoCardapio;

  /// Mantém os dados públicos em dia enquanto o app está aberto (só para a
  /// equipe da loja; o entregador não tem acesso aos produtos).
  static void iniciar() {
    parar();
    void agendar() {
      _espera?.cancel();
      _espera = Timer(const Duration(seconds: 3), _publicar);
    }

    Dados.produtos.addListener(agendar);
    ConfigRepository.atual.addListener(agendar);
    _subs.add(() => Dados.produtos.removeListener(agendar));
    _subs.add(() => ConfigRepository.atual.removeListener(agendar));
    agendar();
  }

  static void parar() {
    for (final s in _subs) {
      s();
    }
    _subs.clear();
    _espera?.cancel();
    _espera = null;
    _ultimaInfo = null;
    _ultimoCardapio = null;
  }

  /// Dados públicos da loja (sem o "aberta", que é controlado à parte).
  @visibleForTesting
  static Map<String, Object?> infoPublica(ConfigLoja c, String lojaId) => {
    'lojaId': lojaId,
    'ativa': c.lojaOnlineAtiva && c.slug.isNotEmpty,
    'slug': c.slug,
    'nome': c.nomeLoja,
    'logo': c.logo,
    'telefone': c.telefone,
    'endereco': c.endereco,
    'cor': ConfigLoja.corParaHex(c.corPrimaria),
    'taxaEntrega': c.taxaEntrega,
    'pedidoMinimo': c.pedidoMinimo,
    'formas': c.formasDelivery,
    'chavePix': c.chavePix,
    'horario': c.horarioAtendimento,
  };

  /// Produtos do cardápio público, por categoria e nome.
  @visibleForTesting
  static List<Map<String, Object?>> cardapioPublico(List<Produto> produtos) {
    final lista =
        produtos.where((p) => p.ativo && p.naLojaOnline && p.preco > 0).toList()
          ..sort((a, b) {
            final c = a.categoria.toLowerCase().compareTo(
              b.categoria.toLowerCase(),
            );
            return c != 0
                ? c
                : a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
          });
    return [
      for (final p in lista)
        {
          'id': p.id,
          'nome': p.nome,
          'categoria': p.categoria.isEmpty ? 'Outros' : p.categoria,
          'unidade': p.unidade,
          'preco': p.preco,
          'disponivel': p.estoque > 0,
          // Limite por pedido: o cliente não pede mais do que há em estoque
          // (até 99), sem expor o saldo exato quando ele é grande.
          'maximo': p.estoque > 99 ? 99 : (p.estoque < 0 ? 0 : p.estoque),
        },
    ];
  }

  static Future<void> _publicar() async {
    if (!Banco.temLoja || Sessao.instancia.usuario == null) return;
    if (Sessao.instancia.atual.isEntregador) return;
    final c = ConfigRepository.atual.value;
    // Só publica depois que a loja online foi configurada uma vez.
    if (c.slug.isEmpty) return;
    final info = infoPublica(c, Banco.lojaId);
    final infoJson = jsonEncode(info);
    final batch = _db.batch();
    var mudou = false;
    if (infoJson != _ultimaInfo) {
      batch.set(publica, {
        ...info,
        'atualizadoEm': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _ultimaInfo = infoJson;
      mudou = true;
    }
    if (c.lojaOnlineAtiva && Dados.produtos.value.isNotEmpty) {
      final cardapio = cardapioPublico(Dados.produtos.value);
      final cardapioJson = jsonEncode(cardapio);
      if (cardapioJson != _ultimoCardapio) {
        batch.set(_cardapio, {
          'produtos': cardapio,
          'atualizadoEm': FieldValue.serverTimestamp(),
        });
        _ultimoCardapio = cardapioJson;
        mudou = true;
      }
    }
    if (mudou) semAguardar(batch.commit(), 'cardápio da loja online');
  }
}
