import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// ---------------------------------------------------------------------------
// MethodChannel — talks to Kotlin VmManager via MainActivity
// ---------------------------------------------------------------------------

const _channel = MethodChannel('com.ai2th.stardial/vm');

Future<void> startVm()   => _channel.invokeMethod('startVm');
Future<void> stopVm()    => _channel.invokeMethod('stopVm');
Future<void> restartVm() => _channel.invokeMethod('restartVm');

Future<String> getVmStatus() async =>
    await _channel.invokeMethod<String>('getVmStatus') ?? 'unknown';

Future<bool> checkHealth() async =>
    await _channel.invokeMethod<bool>('checkHealth') ?? false;

Future<Map<String, dynamic>> vmExec(String cmd) async {
  final result = await _channel.invokeMethod<Map>('vmExec', {'cmd': cmd});
  return Map<String, dynamic>.from(result ?? {});
}

// ---------------------------------------------------------------------------
// API helpers (all HTTP goes through the Kotlin MethodChannel → OkHttp)
// ---------------------------------------------------------------------------

Future<dynamic> _apiGet(String path) async {
  final raw = await _channel.invokeMethod<String>('apiGet', {'path': path});
  if (raw == null || raw.isEmpty) return null;
  return jsonDecode(raw);
}

Future<dynamic> _apiPost(String path, Map<String, dynamic> body) async {
  final raw = await _channel.invokeMethod<String>('apiPost', {
    'path': path,
    'body': jsonEncode(body),
  });
  if (raw == null || raw.isEmpty) return null;
  return jsonDecode(raw);
}

Future<dynamic> _apiDelete(String path) async {
  final raw = await _channel.invokeMethod<String>('apiDelete', {'path': path});
  if (raw == null || raw.isEmpty) return null;
  return jsonDecode(raw);
}

Future<String> _apiGetText(String path) async =>
    await _channel.invokeMethod<String>('apiGet', {'path': path}) ?? '';

// ---------------------------------------------------------------------------
// VmState — ChangeNotifier polled by UI
// ---------------------------------------------------------------------------

enum VmStatus { unknown, running, stopped, error }

class SipEndpoints {
  final String ws;
  final String wss;
  SipEndpoints({required this.ws, required this.wss});
}

class Extension {
  final String name;
  final String context;
  final bool hasAuth;
  final bool webrtc;

  Extension({
    required this.name,
    required this.context,
    required this.hasAuth,
    required this.webrtc,
  });

  factory Extension.fromJson(Map<String, dynamic> j) => Extension(
        name:     j['name']     as String? ?? '',
        context:  j['context']  as String? ?? 'from-internal',
        hasAuth:  j['has_auth'] as bool?   ?? false,
        webrtc:   j['webrtc']   as bool?   ?? false,
      );
}

class ActiveCall {
  final String channel;
  final String exten;
  final String state;
  final String duration;

  ActiveCall({
    required this.channel,
    required this.exten,
    required this.state,
    required this.duration,
  });

  factory ActiveCall.fromJson(Map<String, dynamic> j) => ActiveCall(
        channel:  j['channel']  as String? ?? '',
        exten:    j['exten']    as String? ?? '',
        state:    j['state']    as String? ?? '',
        duration: j['duration'] as String? ?? '',
      );
}

class VmState extends ChangeNotifier {
  VmStatus status = VmStatus.unknown;
  String asteriskVersion = '';
  String wsEndpoint  = 'ws://127.0.0.1:8088/asterisk/sip';
  String wssEndpoint = 'wss://127.0.0.1:8089/asterisk/sip';
  String certFingerprint = '';

  List<Extension> extensions = [];
  List<ActiveCall> activeCalls = [];
  String logs = '';

  Timer? _timer;

  void startPolling() {
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
    _poll();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final health = await _apiGet('/health') as Map?;
      if (health == null) {
        status = VmStatus.stopped;
      } else {
        final s = health['status'] as String? ?? '';
        status = s == 'running' ? VmStatus.running : VmStatus.stopped;
        asteriskVersion = health['version'] as String? ?? '';
        wsEndpoint  = health['ws']  as String? ?? wsEndpoint;
        wssEndpoint = health['wss'] as String? ?? wssEndpoint;
      }
    } catch (_) {
      status = VmStatus.stopped;
    }
    notifyListeners();
  }

  Future<void> refreshExtensions() async {
    try {
      final data = await _apiGet('/extensions') as List?;
      extensions = (data ?? [])
          .map((e) => Extension.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refreshCalls() async {
    try {
      final data = await _apiGet('/calls') as List?;
      activeCalls = (data ?? [])
          .map((e) => ActiveCall.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refreshLogs() async {
    try {
      logs = await _apiGetText('/logs?tail=300');
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refreshCertFingerprint() async {
    try {
      final data = await _apiGet('/cert/fingerprint') as Map?;
      certFingerprint = data?['raw'] as String? ?? '';
      notifyListeners();
    } catch (_) {}
  }

  Future<bool> createExtension({
    required String name,
    required String password,
    String context = 'from-internal',
    bool webrtc = true,
  }) async {
    try {
      await _apiPost('/extensions', {
        'name': name,
        'password': password,
        'context': context,
        'webrtc': webrtc,
      });
      await refreshExtensions();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteExtension(String name) async {
    try {
      await _apiDelete('/extensions/$name');
      await refreshExtensions();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> hangupCall(String channel) async {
    try {
      await _apiPost('/calls/hangup', {'channel': channel});
      await refreshCalls();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> reloadAsterisk() async {
    try {
      await _apiPost('/asterisk/reload', {});
    } catch (_) {}
  }
}
