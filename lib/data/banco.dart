import 'package:cloud_firestore/cloud_firestore.dart';

/// Ponto único de acesso ao Firestore.
///
/// O app é multiloja: todos os dados de uma loja ficam em
/// `lojas/{lojaId}/{colecao}`, e as regras do Firestore só liberam a loja
/// para os membros dela. A loja em uso é escolhida no login.
class Banco {
  static final db = FirebaseFirestore.instance;

  static String? _lojaId;

  static String get lojaId =>
      _lojaId ?? (throw StateError('Nenhuma loja selecionada.'));

  static bool get temLoja => _lojaId != null;

  static void selecionarLoja(String? id) => _lojaId = id;

  static CollectionReference<Map<String, dynamic>> get lojas =>
      db.collection('lojas');

  /// Documento da loja em uso.
  static DocumentReference<Map<String, dynamic>> get loja => lojas.doc(lojaId);

  /// Coleção da loja em uso (produtos, vendas, caixas...).
  static CollectionReference<Map<String, dynamic>> col(String nome) =>
      loja.collection(nome);

  /// Dados do sistema (dono do sistema, migração).
  static DocumentReference<Map<String, dynamic>> get sistema =>
      db.collection('config').doc('sistema');

  /// E-mail → uid das contas já criadas (para ligar uma pessoa a outra loja).
  static CollectionReference<Map<String, dynamic>> get contas =>
      db.collection('contas');
}
