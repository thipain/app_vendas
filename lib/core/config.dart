/// Configurações gerais do app.
class AppConfig {
  /// Repositório público no GitHub de onde o app busca novas versões (Releases).
  static const githubOwner = 'SEU_USUARIO_GITHUB';
  static const githubRepo = 'app_vendas';

  /// Se o texto da Release contiver esta marcação, a atualização é obrigatória.
  static const marcadorAtualizacaoObrigatoria = '[obrigatoria]';
}
