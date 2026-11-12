import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../models/pedido_online.dart';
import 'pedido_online_repository.dart';

/// Pedidos da loja online aguardando resposta, com alarme sonoro: toca quando
/// chega um pedido novo e repete a cada 30 segundos enquanto houver pedido
/// sem resposta (a não ser que alguém silencie).
class AlarmeOnline {
  static final aguardando = ValueNotifier<List<PedidoOnline>>(const []);
  static final silenciado = ValueNotifier<bool>(false);

  static StreamSubscription<List<PedidoOnline>>? _sub;
  static Timer? _repetir;
  static AudioPlayer? _player;
  static final _vistos = <String>{};
  static bool _primeiraLeitura = true;

  static void iniciar() {
    parar();
    _primeiraLeitura = true;
    _sub = PedidoOnlineRepository().watchAguardando().listen((lista) {
      final novos = lista.where((p) => !_vistos.contains(p.id)).toList();
      _vistos
        ..clear()
        ..addAll(lista.map((p) => p.id));
      aguardando.value = lista;
      // Um pedido novo volta a tocar mesmo que tenham silenciado antes.
      if (novos.isNotEmpty) silenciado.value = false;
      if (novos.isNotEmpty || (_primeiraLeitura && lista.isNotEmpty)) tocar();
      _primeiraLeitura = false;
    }, onError: (Object e) => debugPrint('Pedidos online: $e'));
    _repetir = Timer.periodic(const Duration(seconds: 30), (_) {
      if (aguardando.value.isNotEmpty && !silenciado.value) tocar();
    });
  }

  static void parar() {
    _sub?.cancel();
    _sub = null;
    _repetir?.cancel();
    _repetir = null;
    _player?.dispose();
    _player = null;
    _vistos.clear();
    aguardando.value = const [];
  }

  static Future<void> tocar() async {
    if (silenciado.value) return;
    try {
      final p = _player ??= AudioPlayer();
      await p.stop();
      await p.play(AssetSource('sons/novo_pedido.wav'), volume: 1);
    } catch (e) {
      debugPrint('Alarme: $e');
    }
  }
}
