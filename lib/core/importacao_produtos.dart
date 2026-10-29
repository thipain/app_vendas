import '../models/produto.dart';
import 'formatters.dart';

/// Colunas aceitas na planilha de importação, na ordem padrão (usada quando
/// a planilha não tem cabeçalho).
const colunasImportacao = [
  'nome',
  'codigo',
  'categoria',
  'preco',
  'custo',
  'estoque',
  'minimo',
  'unidade',
];

/// Nomes alternativos aceitos no cabeçalho.
const _sinonimos = {
  'produto': 'nome',
  'descricao': 'nome',
  'sku': 'codigo',
  'cod': 'codigo',
  'codigo de barras': 'codigo',
  'ean': 'codigo',
  'preco de venda': 'preco',
  'venda': 'preco',
  'valor': 'preco',
  'preco de custo': 'custo',
  'saldo': 'estoque',
  'quantidade': 'estoque',
  'qtd': 'estoque',
  'estoque minimo': 'minimo',
  'alerta minimo': 'minimo',
  'un': 'unidade',
};

/// Uma linha lida da planilha: o produto pronto para cadastrar ou o erro.
class LinhaImportacao {
  final int numero;
  final Produto? produto;
  final int estoqueInicial;
  final String? erro;

  const LinhaImportacao({
    required this.numero,
    this.produto,
    this.estoqueInicial = 0,
    this.erro,
  });

  bool get valida => erro == null && produto != null;
}

String _semAcento(String s) {
  const de = 'áàâãäéèêëíìîïóòôõöúùûüç';
  const para = 'aaaaaeeeeiiiiooooouuuuc';
  final b = StringBuffer();
  for (final c in s.toLowerCase().split('')) {
    final i = de.indexOf(c);
    b.write(i >= 0 ? para[i] : c);
  }
  return b.toString().trim();
}

/// Separador mais provável: tabulação (copiado do Excel), ponto e vírgula
/// (CSV do Excel em português) ou vírgula.
String _separador(String linha) {
  if (linha.contains('\t')) return '\t';
  return ';'.allMatches(linha).length >= ','.allMatches(linha).length
      ? ';'
      : ',';
}

/// Divide uma linha respeitando campos entre aspas ("Copo, 300ml").
List<String> _campos(String linha, String sep) {
  final campos = <String>[];
  final atual = StringBuffer();
  var aspas = false;
  for (var i = 0; i < linha.length; i++) {
    final c = linha[i];
    if (c == '"') {
      if (aspas && i + 1 < linha.length && linha[i + 1] == '"') {
        atual.write('"');
        i++;
      } else {
        aspas = !aspas;
      }
    } else if (c == sep && !aspas) {
      campos.add(atual.toString().trim());
      atual.clear();
    } else {
      atual.write(c);
    }
  }
  campos.add(atual.toString().trim());
  return campos;
}

/// Lê o texto colado ou o conteúdo de um arquivo CSV.
///
/// [codigosExistentes] (em minúsculas) evita duplicar produtos já
/// cadastrados; códigos repetidos dentro da própria planilha também são
/// recusados.
List<LinhaImportacao> lerPlanilhaProdutos(
  String texto, {
  Set<String> codigosExistentes = const {},
}) {
  final linhas = texto
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .where((l) => l.trim().isNotEmpty)
      .toList();
  if (linhas.isEmpty) return const [];
  final sep = _separador(linhas.first);

  // Cabeçalho: se a primeira linha tiver "nome" (ou sinônimo), as colunas
  // são mapeadas pelo nome; senão usa a ordem padrão.
  var ordem = colunasImportacao;
  var inicio = 0;
  final primeira = _campos(linhas.first, sep).map(_semAcento).toList();
  final mapeada = [for (final c in primeira) _sinonimos[c] ?? c];
  if (mapeada.contains('nome')) {
    ordem = mapeada;
    inicio = 1;
  }

  final vistos = <String>{};
  final resultado = <LinhaImportacao>[];
  for (var i = inicio; i < linhas.length; i++) {
    final campos = _campos(linhas[i], sep);
    String campo(String nome) {
      final idx = ordem.indexOf(nome);
      return idx >= 0 && idx < campos.length ? campos[idx] : '';
    }

    final numero = i + 1;
    LinhaImportacao erro(String msg) =>
        LinhaImportacao(numero: numero, erro: msg);

    final nome = campo('nome');
    final codigo = campo('codigo');
    if (nome.isEmpty) {
      resultado.add(erro('Sem nome'));
      continue;
    }
    if (nome.length > 160) {
      resultado.add(erro('Nome com mais de 160 caracteres'));
      continue;
    }
    if (codigo.isEmpty) {
      resultado.add(erro('Sem código'));
      continue;
    }
    final chave = codigo.toLowerCase();
    if (codigosExistentes.contains(chave)) {
      resultado.add(erro('Código já cadastrado na loja'));
      continue;
    }
    if (!vistos.add(chave)) {
      resultado.add(erro('Código repetido na planilha'));
      continue;
    }
    final preco = lerValor(campo('preco'));
    if (preco == null || preco < 0) {
      resultado.add(erro('Preço inválido'));
      continue;
    }
    final textoCusto = campo('custo');
    final custo = textoCusto.isEmpty ? 0.0 : lerValor(textoCusto);
    if (custo == null || custo < 0) {
      resultado.add(erro('Custo inválido'));
      continue;
    }
    // Aceita "1.200" (milhar) e "12,0"; recusa fração ("12,5") e negativos.
    int? inteiro(String nomeCampo) {
      final t = campo(nomeCampo);
      if (t.isEmpty) return 0;
      final v = t.contains(',')
          ? lerValor(t)
          : double.tryParse(t.replaceAll('.', ''));
      if (v == null || v < 0 || v != v.roundToDouble()) return null;
      return v.toInt();
    }

    final estoque = inteiro('estoque');
    final minimo = inteiro('minimo');
    if (estoque == null) {
      resultado.add(erro('Estoque inválido (use número inteiro)'));
      continue;
    }
    if (minimo == null) {
      resultado.add(erro('Mínimo inválido (use número inteiro)'));
      continue;
    }
    final categoria = campo('categoria');
    final unidade = campo('unidade');
    resultado.add(
      LinhaImportacao(
        numero: numero,
        estoqueInicial: estoque,
        produto: Produto(
          nome: nome,
          codigo: codigo,
          categoria: categoria.isEmpty ? 'Geral' : categoria,
          preco: (preco * 100).roundToDouble() / 100,
          custo: (custo * 10000).roundToDouble() / 10000,
          estoqueMinimo: minimo,
          unidade: unidade.isEmpty ? 'un' : unidade,
        ),
      ),
    );
  }
  return resultado;
}
