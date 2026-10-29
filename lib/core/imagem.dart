import 'dart:convert';

import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// Escolhe uma imagem (galeria/arquivo ou câmera), reduz para no máximo
/// [lado] pixels e devolve um JPEG em base64, pequeno o bastante para ficar
/// dentro do documento do Firestore (e disponível offline).
Future<String?> escolherImagem({
  bool camera = false,
  int lado = 360,
  bool png = false,
}) async {
  final arquivo = await ImagePicker().pickImage(
    source: camera ? ImageSource.camera : ImageSource.gallery,
  );
  if (arquivo == null) return null;
  final bytes = await arquivo.readAsBytes();
  final original = img.decodeImage(bytes);
  if (original == null) {
    throw const FormatException('Use uma imagem JPG, PNG ou WEBP.');
  }
  final reduzida = original.width >= original.height
      ? (original.width > lado
            ? img.copyResize(original, width: lado)
            : original)
      : (original.height > lado
            ? img.copyResize(original, height: lado)
            : original);
  final saida = png
      ? img.encodePng(reduzida)
      : img.encodeJpg(reduzida, quality: 72);
  return base64Encode(saida);
}
