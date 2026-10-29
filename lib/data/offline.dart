import '../core/relatorio_erros.dart';

/// Dispara uma gravação no Firestore sem aguardar o servidor.
///
/// Offline, o Future de set/update/commit só completa quando a gravação chega
/// ao servidor. O dado já fica disponível no cache local na hora, então a tela
/// não deve ficar esperando: os listeners (snapshots) atualizam a interface.
void semAguardar(Future<void> operacao, String descricao) {
  // Uma gravação recusada pelo servidor (ex.: sem permissão) se perde: o erro
  // vai para o relatório do dono do sistema.
  operacao.catchError(
    (Object e, StackTrace s) => RelatorioErros.registrar(
      e,
      s,
      origem: 'sincronizacao',
      contexto: descricao,
    ),
  );
}
