import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Ícone na AppBar que mostra se há dados aguardando sincronização.
///
/// - nuvem riscada: dados vindos só do cache (provavelmente sem internet)
/// - nuvem com seta: há gravações locais ainda não enviadas
/// - nuvem com check: tudo sincronizado
class SyncStatusIcon extends StatefulWidget {
  const SyncStatusIcon({super.key});

  @override
  State<SyncStatusIcon> createState() => _SyncStatusIconState();
}

class _SyncStatusIconState extends State<SyncStatusIcon> {
  static const _colecoes = ['vendas', 'produtos', 'clientes'];

  final _subs = <StreamSubscription>[];
  final _pendentes = <String, bool>{};
  final _cache = <String, bool>{};

  @override
  void initState() {
    super.initState();
    for (final nome in _colecoes) {
      _subs.add(FirebaseFirestore.instance
          .collection(nome)
          .snapshots(includeMetadataChanges: true)
          .listen((s) {
        setState(() {
          _pendentes[nome] = s.metadata.hasPendingWrites;
          _cache[nome] = s.metadata.isFromCache;
        });
      }));
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pendente = _pendentes.values.any((v) => v);
    final offline = _cache.values.any((v) => v);

    final (icone, texto, cor) = switch ((offline, pendente)) {
      (true, true) => (
          Icons.cloud_off,
          'Sem conexão. Há dados aguardando envio.',
          Colors.orange
        ),
      (true, false) => (Icons.cloud_off, 'Sem conexão', Colors.grey),
      (false, true) => (Icons.cloud_upload, 'Enviando dados...', Colors.blue),
      (false, false) => (Icons.cloud_done, 'Tudo sincronizado', Colors.green),
    };

    return IconButton(
      tooltip: texto,
      icon: Icon(icone, color: cor),
      onPressed: () => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(texto))),
    );
  }
}
