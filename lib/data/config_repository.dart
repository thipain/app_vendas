import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/config_loja.dart';
import 'auditoria_repository.dart';
import 'offline.dart';
import 'banco.dart';

/// Configurações da loja, compartilhadas por todos os aparelhos.
class ConfigRepository {
  static DocumentReference<Map<String, dynamic>> get _doc =>
      Banco.col('config').doc('loja');

  /// Valor atual, atualizado em tempo real (e disponível offline pelo cache).
  static final atual = ValueNotifier<ConfigLoja>(const ConfigLoja());
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  static void iniciar() {
    _sub ??= _doc.snapshots().listen(
      (s) => atual.value = ConfigLoja.fromMap(s.data()),
      onError: (Object e) => debugPrint('Configurações: $e'),
    );
  }

  static void parar() {
    _sub?.cancel();
    _sub = null;
    atual.value = const ConfigLoja();
  }

  static void salvar(ConfigLoja nova) {
    final antes = atual.value.toMap()..remove('logo');
    final depois = nova.toMap()..remove('logo');
    final batch = FirebaseFirestore.instance.batch();
    batch.set(_doc, nova.toMap(), SetOptions(merge: true));
    AuditoriaRepository.noBatch(
      batch,
      'settings.update',
      'Configurações da loja alteradas',
      entidade: 'config',
      entidadeId: 'loja',
      antes: antes,
      depois: depois,
    );
    atual.value = nova;
    semAguardar(batch.commit(), 'configurações');
  }
}
