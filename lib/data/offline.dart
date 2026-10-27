import 'package:flutter/foundation.dart';

/// Dispara uma gravação no Firestore sem aguardar o servidor.
///
/// Offline, o Future de set/update/commit só completa quando a gravação chega
/// ao servidor. O dado já fica disponível no cache local na hora, então a tela
/// não deve ficar esperando: os listeners (snapshots) atualizam a interface.
void semAguardar(Future<void> operacao, String descricao) {
  operacao.catchError(
    (Object e) => debugPrint('Falha ao sincronizar $descricao: $e'),
  );
}
