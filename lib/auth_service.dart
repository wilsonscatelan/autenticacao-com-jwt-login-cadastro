import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Erro de negócio com mensagem amigável para mostrar na tela.
class AuthException implements Exception {
  final String mensagem;
  final int? statusCode;
  AuthException(this.mensagem, {this.statusCode});

  @override
  String toString() => mensagem;
}

/// Concentra TODA a comunicação com /auth/* e o armazenamento do token.
class AuthService {
  static const String _baseUrl = 'https://api-produtos-mobile.onrender.com';
  static const String _chaveToken = 'access_token';
  static const Duration _timeout = Duration(seconds: 45); // Render "acordando"

  // Nomes dos campos JSON. Se o tutorial da API usar outros nomes,
  // basta ajustar aqui.
  static const String _campoUsuario = 'username';
  static const String _campoSenha = 'senha';
  static const String _campoNome = 'nome_completo';

  static final Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  // ---------------------------------------------------------------- Token --
  static Future<String?> obterToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_chaveToken);
  }

  static Future<void> _salvarToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chaveToken, token);
  }

  /// Logout: apenas remove o token do aparelho.
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_chaveToken);
  }

  // ---------------------------------------------------------------- Login --
  /// POST /auth/login -> salva o access_token. Lança [AuthException] em erro.
  static Future<void> login(String usuario, String senha) async {
    final resposta = await _enviar(
      () => http
          .post(
            Uri.parse('$_baseUrl/auth/login'),
            headers: _jsonHeaders,
            body: jsonEncode({_campoUsuario: usuario, _campoSenha: senha}),
          )
          .timeout(_timeout),
    );

    if (resposta.statusCode == 200) {
      final json = _decodificar(resposta);
      final token = json['access_token'];
      if (token is! String || token.isEmpty) {
        throw AuthException('Resposta inesperada do servidor (sem token).');
      }
      await _salvarToken(token);
      return;
    }
    if (resposta.statusCode == 401) {
      throw AuthException('Usuário ou senha incorretos.', statusCode: 401);
    }
    throw AuthException(_mensagemDoServidor(resposta),
        statusCode: resposta.statusCode);
  }

  // ------------------------------------------------------------- Cadastro --
  /// POST /auth/cadastrar. Lança [AuthException] em erro (ex.: 400).
  static Future<void> cadastrar({
    required String nomeCompleto,
    required String usuario,
    required String senha,
  }) async {
    final resposta = await _enviar(
      () => http
          .post(
            Uri.parse('$_baseUrl/auth/cadastrar'),
            headers: _jsonHeaders,
            body: jsonEncode({
              _campoNome: nomeCompleto,
              _campoUsuario: usuario,
              _campoSenha: senha,
            }),
          )
          .timeout(_timeout),
    );

    if (resposta.statusCode == 200 || resposta.statusCode == 201) return;
    if (resposta.statusCode == 400) {
      throw AuthException('Este nome de usuário já está em uso.',
          statusCode: 400);
    }
    throw AuthException(_mensagemDoServidor(resposta),
        statusCode: resposta.statusCode);
  }

  // ------------------------------------------------------------------ Me --
  /// GET /auth/me com Authorization: Bearer <token>. Retorna o nome a exibir.
  /// Lança [AuthException] com statusCode 401 se o token for inválido/expirado.
  static Future<String> nomeDoUsuarioLogado() async {
    final token = await obterToken();
    if (token == null) {
      throw AuthException('Sessão não encontrada.', statusCode: 401);
    }

    final resposta = await _enviar(
      () => http.get(
        Uri.parse('$_baseUrl/auth/me'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      ).timeout(_timeout),
    );

    if (resposta.statusCode == 200) {
      final json = _decodificar(resposta);
      final nome = json[_campoNome] ?? json['nome'] ?? json['username'] ?? json['usuario'];
      return (nome ?? 'usuário').toString();
    }
    if (resposta.statusCode == 401) {
      throw AuthException('Sessão expirada. Faça login novamente.',
          statusCode: 401);
    }
    throw AuthException(_mensagemDoServidor(resposta),
        statusCode: resposta.statusCode);
  }

  // ------------------------------------------------------------- Helpers --
  /// Executa a requisição traduzindo falhas de rede em mensagens amigáveis.
  static Future<http.Response> _enviar(
      Future<http.Response> Function() requisicao) async {
    try {
      return await requisicao();
    } on TimeoutException {
      throw AuthException(
          'O servidor demorou a responder. Tente novamente em instantes.');
    } on SocketException {
      throw AuthException('Sem conexão. Verifique sua internet.');
    } on http.ClientException {
      throw AuthException('Não foi possível conectar ao servidor.');
    }
  }

  static Map<String, dynamic> _decodificar(http.Response r) {
    try {
      return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw AuthException('Resposta inválida do servidor.');
    }
  }

  /// Tenta ler o campo "detail" (padrão do FastAPI).
  static String _mensagemDoServidor(http.Response r) {
  try {
    final json = jsonDecode(utf8.decode(r.bodyBytes));
    final detail = json is Map ? json['detail'] : null;
    if (detail is String) return detail;
    if (detail is List && detail.isNotEmpty) {
      return detail.map((e) {
        if (e is Map) {
          final loc = e['loc'];
          final campo = loc is List && loc.isNotEmpty ? loc.last : '';
          return '$campo: ${e['msg']}';
        }
        return '$e';
      }).join('\n');
    }
  } catch (_) {}
  return 'Erro no servidor (HTTP ${r.statusCode}).';
}
}
