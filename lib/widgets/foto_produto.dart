import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

final _cache = <String, Uint8List>{};

Uint8List? bytesDaFoto(String base64Foto) {
  if (base64Foto.isEmpty) return null;
  return _cache.putIfAbsent(base64Foto, () => base64Decode(base64Foto));
}

/// Inicial do nome em um quadrado colorido, ou a imagem em base64
/// quando houver (usado na logo da loja; produtos não têm foto).
class FotoProduto extends StatelessWidget {
  final String foto;
  final String nome;
  final double tamanho;
  final double raio;

  const FotoProduto({
    super.key,
    this.foto = '',
    required this.nome,
    this.tamanho = 44,
    this.raio = 8,
  });

  @override
  Widget build(BuildContext context) {
    final bytes = bytesDaFoto(foto);
    final cores = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(raio),
      child: SizedBox(
        width: tamanho,
        height: tamanho,
        child: bytes != null
            ? Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true)
            : ColoredBox(
                color: cores.primaryContainer,
                child: Center(
                  child: Text(
                    nome.isEmpty ? '?' : nome.characters.first.toUpperCase(),
                    style: TextStyle(
                      fontSize: tamanho * 0.42,
                      fontWeight: FontWeight.bold,
                      color: cores.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
