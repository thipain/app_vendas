import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../core/regra_exception.dart';
import '../core/sessao.dart';
import '../models/registro_ponto.dart';
import 'auditoria_repository.dart';
import 'offline.dart';

class Localizacao {
  final double? latitude;
  final double? longitude;
  final String endereco;
  const Localizacao({this.latitude, this.longitude, required this.endereco});
}

class PontoRepository {
  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _col => _db.collection('ponto');

  Stream<List<RegistroPonto>> watchPeriodo(DateTime inicio, DateTime fim) => _col
      .where('data', isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
      .where('data', isLessThan: Timestamp.fromDate(fim))
      .orderBy('data', descending: true)
      .snapshots(includeMetadataChanges: true)
      .map((s) => s.docs.map(RegistroPonto.fromDoc).toList());

  /// Último registro do usuário (de qualquer dia): define se o próximo é
  /// entrada ou saída.
  Stream<RegistroPonto?> watchUltimo(String usuarioId) => _col
      .where('usuarioId', isEqualTo: usuarioId)
      .orderBy('data', descending: true)
      .limit(1)
      .snapshots(includeMetadataChanges: true)
      .map((s) => s.docs.isEmpty ? null : RegistroPonto.fromDoc(s.docs.first));

  static String proximoTipo(RegistroPonto? ultimo) =>
      ultimo?.tipo == RegistroPonto.entrada
          ? RegistroPonto.saida
          : RegistroPonto.entrada;

  /// Obtém a coordenada e tenta converter em endereço (OpenStreetMap).
  Future<Localizacao> obterLocalizacao() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const Localizacao(endereco: 'Geolocalização indisponível');
      }
      var permissao = await Geolocator.checkPermission();
      if (permissao == LocationPermission.denied) {
        permissao = await Geolocator.requestPermission();
      }
      if (permissao == LocationPermission.denied ||
          permissao == LocationPermission.deniedForever) {
        return const Localizacao(endereco: 'Localização não autorizada');
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      var endereco =
          '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';
      try {
        final r = await http.get(
          Uri.https('nominatim.openstreetmap.org', '/reverse', {
            'format': 'jsonv2',
            'lat': '${pos.latitude}',
            'lon': '${pos.longitude}',
          }),
          headers: {
            'Accept-Language': 'pt-BR',
            'User-Agent': 'app_vendas (github.com/thipain/app_vendas)',
          },
        ).timeout(const Duration(seconds: 8));
        if (r.statusCode == 200) {
          final nome = (jsonDecode(r.body) as Map)['display_name'] as String?;
          if (nome != null && nome.isNotEmpty) endereco = nome;
        }
      } catch (e) {
        debugPrint('Endereço do ponto: $e');
      }
      return Localizacao(
          latitude: pos.latitude, longitude: pos.longitude, endereco: endereco);
    } catch (e) {
      debugPrint('Localização do ponto: $e');
      return const Localizacao(endereco: 'Geolocalização indisponível');
    }
  }

  /// Registra o ponto do usuário logado. O tipo alterna a partir do último
  /// registro; registros com menos de 60 segundos de intervalo são recusados.
  String registrar(RegistroPonto? ultimo, Localizacao local) {
    if (ultimo != null &&
        DateTime.now().difference(ultimo.data) < const Duration(seconds: 60)) {
      throw const RegraException(
          'Aguarde um minuto antes de registrar novamente.');
    }
    final tipo = proximoTipo(ultimo);
    final eu = Sessao.instancia.atual;
    final endereco = local.endereco.length > 255
        ? local.endereco.substring(0, 255)
        : local.endereco;
    final ref = _col.doc();
    final batch = _db.batch();
    batch.set(ref, {
      'usuarioId': eu.id,
      'usuario': Sessao.instancia.autor,
      'tipo': tipo,
      'latitude': local.latitude,
      'longitude': local.longitude,
      'endereco': endereco,
      'data': Timestamp.now(),
    });
    AuditoriaRepository.noBatch(batch, 'time.punch', 'Ponto registrado: $tipo',
        entidade: 'ponto', entidadeId: ref.id, depois: {'endereco': endereco});
    semAguardar(batch.commit(), 'ponto');
    return tipo;
  }
}
