/// Erro de regra de negócio com mensagem pronta para mostrar ao usuário.
class RegraException implements Exception {
  final String mensagem;
  const RegraException(this.mensagem);

  @override
  String toString() => mensagem;
}
