import 'package:flutter/material.dart';

import 'auth_service.dart';
import 'login_page.dart';
import 'main.dart' show TelaListaProdutos;

/// Tela inicial: decide se vai para o Login ou direto para a tela principal
/// (já existe token salvo no aparelho).
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _verificarSessao();
  }

  Future<void> _verificarSessao() async {
    final token = await AuthService.obterToken();
    if (!mounted) return;
    final destino = (token != null && token.isNotEmpty)
        ? const TelaListaProdutos()
        : const LoginPage();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => destino),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
