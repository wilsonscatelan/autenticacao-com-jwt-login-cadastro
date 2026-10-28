import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

class Notificacao {
  final String titulo;
  final String mensagem;

  Notificacao({required this.titulo, required this.mensagem});

  factory Notificacao.fromJson(Map<String, dynamic> json) {
    return Notificacao(
      titulo: (json['titulo'] ?? 'Notificação').toString(),
      mensagem: (json['mensagem'] ?? '').toString(),
    );
  }
}

class NotificacaoService {
  /// true = servidor na nuvem | false = servidor local
  static const bool usarNuvem = true;

  static const String _urlNuvem =
      'wss://api-produtos-mobile.onrender.com/ws/notificacoes';
  static const String _urlAndroidEmulador =
      'ws://10.0.2.2:8000/ws/notificacoes';
  static const String _urlLocal = 'ws://localhost:8000/ws/notificacoes';

  WebSocket? _socket;
  StreamSubscription? _subscription;
  Timer? _timerReconexao;
  bool _encerrado = false;

  final StreamController<Notificacao> _controller =
      StreamController<Notificacao>.broadcast();

  /// Stream com as notificações recebidas do servidor.
  Stream<Notificacao> get notificacoes => _controller.stream;

  String get _url {
    if (usarNuvem) return _urlNuvem;
    if (!kIsWeb && Platform.isAndroid) return _urlAndroidEmulador;
    return _urlLocal;
  }

  Future<void> conectar() async {
    _encerrado = false;
    try {
      // O Render (plano gratuito) pode demorar a "acordar": timeout generoso.
      _socket = await WebSocket.connect(_url)
          .timeout(const Duration(seconds: 60));

      _subscription = _socket!.listen(
        _aoReceber,
        onError: (_) => _agendarReconexao(),
        onDone: _agendarReconexao,
        cancelOnError: true,
      );
    } catch (_) {
      _agendarReconexao();
    }
  }

  void _aoReceber(dynamic dado) {
    try {
      final json = jsonDecode(dado as String) as Map<String, dynamic>;
      _controller.add(Notificacao.fromJson(json));
    } catch (_) {
      // Mensagem fora do formato esperado (ex.: ping): ignora.
    }
  }

  void _agendarReconexao() {
    if (_encerrado) return;
    _timerReconexao?.cancel();
    _timerReconexao = Timer(const Duration(seconds: 5), conectar);
  }

  /// Fecha a conexão de forma limpa. Chamar no dispose().
  Future<void> desconectar() async {
    _encerrado = true;
    _timerReconexao?.cancel();
    await _subscription?.cancel();
    await _socket?.close();
    await _controller.close();
  }
}
