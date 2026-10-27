/// Todo cálculo de venda é feito em centavos inteiros, como no servidor do
/// sistema original, para evitar erros de arredondamento com double.
int centavos(num valor) => (valor * 100).round();
double deCentavos(int c) => c / 100;
