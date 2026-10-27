import 'package:cloud_firestore/cloud_firestore.dart';

class RegistroPonto {
  static const entrada = 'entrada';
  static const saida = 'saida';

  final String id;
  final String usuarioId;
  final String usuarioNome;
  final String tipo;
  final double? latitude;
  final double? longitude;
  final String? endereco;
  final DateTime data;
  final bool pendente;

  const RegistroPonto({
    required this.id,
    required this.usuarioId,
    required this.usuarioNome,
    required this.tipo,
    this.latitude,
    this.longitude,
    this.endereco,
    required this.data,
    this.pendente = false,
  });

  String get tipoNome => tipo == entrada ? 'Entrada' : 'Saída';

  String get local {
    if (endereco != null && endereco!.isNotEmpty) return endereco!;
    if (latitude != null && longitude != null) {
      return '${latitude!.toStringAsFixed(6)}, ${longitude!.toStringAsFixed(6)}';
    }
    return 'Local não informado';
  }

  factory RegistroPonto.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return RegistroPonto(
      id: doc.id,
      usuarioId: d['usuarioId'] as String? ?? '',
      usuarioNome: (d['usuario'] as Map?)?['nome'] as String? ?? '',
      tipo: d['tipo'] as String? ?? entrada,
      latitude: (d['latitude'] as num?)?.toDouble(),
      longitude: (d['longitude'] as num?)?.toDouble(),
      endereco: d['endereco'] as String?,
      data: (d['data'] as Timestamp?)?.toDate() ?? DateTime.now(),
      pendente: doc.metadata.hasPendingWrites,
    );
  }
}
