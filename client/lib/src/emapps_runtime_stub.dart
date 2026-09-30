import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pointycastle/export.dart';

import 'emapps_client.dart';

class EmAppRuntimeException implements Exception {
  const EmAppRuntimeException(this.message);

  final String message;

  @override
  String toString() => message;
}

class EmAppRuntimeLogEntry {
  const EmAppRuntimeLogEntry({
    required this.kind,
    required this.message,
    required this.time,
  });

  final String kind;
  final String message;
  final DateTime time;
}

class EmAppLaunchResult {
  const EmAppLaunchResult({
    required this.package,
    required this.url,
    required this.logs,
    required this.close,
    this.htmlContent = '',
    this.unsupported = false,
  });

  final EmAppPackage package;
  final Uri url;
  final List<EmAppRuntimeLogEntry> logs;
  final Future<void> Function() close;
  final String htmlContent;
  final bool unsupported;
}

class EmAppRuntime {
  EmAppRuntime({required EmAppsClient client, bool persistLogs = false})
    : _client = client,
      _persistLogs = persistLogs;

  final EmAppsClient _client;
  final bool _persistLogs;
  final _logs = <EmAppRuntimeLogEntry>[];

  Future<EmAppLaunchResult> open(String appId) async {
    _logs.clear();
    _log('EMAPPS', 'Opening $appId');
    final info = await _client.info(appId);
    _log('NET', 'Loaded package info ${info.appId} v${info.version}');
    final key = await _client.publicKey();
    _log('CRYPTO', 'Loaded public key ${key.algorithm}/${key.bits}');
    final bytes = await _client.download(
      info.appId,
      downloadUrl: info.downloadUrl,
    );
    _log('NET', 'Downloaded ${bytes.length} bytes');
    await _verifyPackage(info, key, bytes);
    final htmlContent = _buildInlineHtml(bytes, info);
    final blob = html.Blob([htmlContent], 'text/html');
    final blobUrl = html.Url.createObjectUrlFromBlob(blob);
    _log('HTTP', 'Blob URL ready (${htmlContent.length} bytes HTML)');

    return EmAppLaunchResult(
      package: info,
      url: Uri.parse(blobUrl),
      htmlContent: htmlContent,
      logs: List<EmAppRuntimeLogEntry>.unmodifiable(_logs),
      close: () async {
        html.Url.revokeObjectUrl(blobUrl);
        _log('EMAPPS', 'Closed ${info.appId}');
      },
    );
  }

  Future<List<EmAppRuntimeLogEntry>> loadStoredLogs() async {
    return const <EmAppRuntimeLogEntry>[];
  }

  Future<void> clearStoredData() async {}

  Future<void> _verifyPackage(
    EmAppPackage info,
    EmAppPublicKey key,
    Uint8List bytes,
  ) async {
    final hash = await emAppPackageSha256Hex(bytes);
    if (info.fileHash.trim().isNotEmpty &&
        hash.toLowerCase() != info.fileHash.trim().toLowerCase()) {
      _log('CRYPTO', 'SHA-256 mismatch local=$hash expected=${info.fileHash}');
      throw const EmAppRuntimeException('Package hash verification failed.');
    }
    if (key.pem.trim().isEmpty || info.signature.trim().isEmpty) {
      throw const EmAppRuntimeException('Package signature is missing.');
    }
    final ok = _verifyRsaSha256(key.pem, bytes, info.signature);
    if (!ok) {
      _log('CRYPTO', 'RSA signature verification failed');
      throw const EmAppRuntimeException(
        'Package signature verification failed.',
      );
    }
    _log('CRYPTO', 'Package signature verified');
  }

  String _buildInlineHtml(Uint8List bytes, EmAppPackage info) {
    final files = _parsePackage(bytes);
    final entryPage = info.entryPage.trim().isEmpty
        ? 'index.html'
        : info.entryPage.trim();
    var htmlSource = files[entryPage] ?? '';
    final entryLower = entryPage.toLowerCase();

    // Collect CSS and JS for inlining
    final cssBuffer = StringBuffer();
    final jsBuffer = StringBuffer();
    for (final entry in files.entries) {
      final ext = entry.key.split('.').last.toLowerCase();
      final keyLower = entry.key.toLowerCase();
      if (ext == 'css' && keyLower != entryLower) {
        cssBuffer.writeln(entry.value);
      } else if (ext == 'js' && keyLower != entryLower) {
        jsBuffer.writeln(entry.value);
      }
    }

    // Replace external CSS references with inline <style>
    final cssRegex = RegExp(
      r'''<link[^>]*\brel\s*=\s*["']stylesheet["'][^>]*\bhref\s*=\s*["']([^"']+)["'][^>]*\s*/?\s*>''',
      caseSensitive: false,
    );
    htmlSource = htmlSource.replaceAllMapped(cssRegex, (match) {
      final href = match.group(1) ?? '';
      final resolved = _resolveFile(files, href);
      return '<style>\n$resolved\n</style>';
    });

    // Replace external JS references (<script src="..."></script>)
    final jsRegex = RegExp(
      r'''<script\b[^>]*\bsrc\s*=\s*["']([^"']+)["'][^>]*>\s*</script>''',
      caseSensitive: false,
    );
    htmlSource = htmlSource.replaceAllMapped(jsRegex, (match) {
      final src = match.group(1) ?? '';
      final resolved = _resolveFile(files, src);
      return '<script>\n$resolved\n</script>';
    });

    // Replace self-closing <script src="..." />
    final jsSelfCloseRegex = RegExp(
      r'''<script\b[^>]*\bsrc\s*=\s*["']([^"']+)["'][^>]*\s*/\s*>''',
      caseSensitive: false,
    );
    htmlSource = htmlSource.replaceAllMapped(jsSelfCloseRegex, (match) {
      final src = match.group(1) ?? '';
      final resolved = _resolveFile(files, src);
      return '<script>\n$resolved\n</script>';
    });

    if (htmlSource.trim().isEmpty) {
      final name =
          info.name.trim().isNotEmpty ? info.name.trim() : 'eMApp';
      htmlSource = '<!DOCTYPE html>\n<html>\n'
          '<head><meta charset="utf-8"><title>${_htmlEscape(name)}</title>\n'
          '<style>\n${cssBuffer.toString()}\n</style>\n</head>\n'
          '<body>\n<h1>${_htmlEscape(name)}</h1>\n</body>\n'
          '<script>\n${jsBuffer.toString()}\n</script>\n'
          '</html>\n';
    }

    // Inject bridge script before </body> or </html>
    if (htmlSource.contains('</body>')) {
      htmlSource = htmlSource.replaceFirst(
        '</body>',
        '$_emAppsBridgeScriptWeb\n</body>',
      );
    } else if (htmlSource.contains('</html>')) {
      htmlSource = htmlSource.replaceFirst(
        '</html>',
        '$_emAppsBridgeScriptWeb\n</html>',
      );
    } else {
      htmlSource = '$htmlSource\n$_emAppsBridgeScriptWeb';
    }

    _log('EMAPPS', 'Built inline HTML (${htmlSource.length} bytes)');
    return htmlSource;
  }

  Map<String, String> _parsePackage(Uint8List bytes) {
    if (_looksLikeZip(bytes)) {
      return _parseZip(bytes);
    }
    return _parseEma(bytes);
  }

  Map<String, String> _parseZip(Uint8List bytes) {
    final result = <String, String>{};
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final name = file.name.replaceAll('\\', '/');
      final content = utf8.decode(file.content as List<int>,
          allowMalformed: true);
      result[name] = content;
      // Also index by basename for relative references
      final basename = name.split('/').last;
      if (basename != name && !result.containsKey(basename)) {
        result[basename] = content;
      }
    }
    _log('EMAPPS', 'Parsed ZIP with ${result.length} file(s)');
    return result;
  }

  Map<String, String> _parseEma(Uint8List bytes) {
    final result = <String, String>{};
    final text = utf8.decode(bytes, allowMalformed: true);
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const EmAppRuntimeException('Invalid EMA package.');
    }
    final fileList = decoded['files'];
    if (fileList is List && fileList.isNotEmpty) {
      for (final item in fileList.whereType<Map>()) {
        final name = item['filename']?.toString().trim() ?? '';
        final content = item['content']?.toString() ?? '';
        if (name.isNotEmpty) {
          result[name] = content;
        }
      }
    }
    _log('EMAPPS', 'Parsed EMA with ${result.length} file(s)');
    return result;
  }

  String _resolveFile(Map<String, String> files, String ref) {
    // Try exact match
    if (files.containsKey(ref)) return files[ref]!;
    // Try without leading ./
    final noDot = ref.replaceFirst(RegExp(r'^\.\/'), '');
    if (noDot != ref && files.containsKey(noDot)) return files[noDot]!;
    // Try basename match
    final basename = ref.split('/').last;
    if (basename != ref && files.containsKey(basename)) {
      return files[basename]!;
    }
    return '';
  }

  void _log(String kind, String message) {
    _logs.add(EmAppRuntimeLogEntry(
      kind: kind,
      message: message,
      time: DateTime.now(),
    ));
  }

  static String _htmlEscape(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }
}

Future<String> emAppPackageSha256Hex(Uint8List bytes) async {
  final digest = Digest('SHA-256').process(bytes);
  return digest.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

bool _verifyRsaSha256(String pem, Uint8List bytes, String signatureBase64) {
  final key = _parseRsaPublicKey(pem);
  final signature = RSASignature(base64Decode(signatureBase64.trim()));
  final verifier = Signer('SHA-256/RSA')
    ..init(false, PublicKeyParameter<RSAPublicKey>(key));
  return verifier.verifySignature(bytes, signature);
}

RSAPublicKey _parseRsaPublicKey(String pem) {
  final normalized = pem
      .replaceAll(RegExp(r'-----BEGIN [A-Z ]+-----'), '')
      .replaceAll(RegExp(r'-----END [A-Z ]+-----'), '')
      .replaceAll(RegExp(r'\s+'), '');
  final der = base64Decode(normalized);
  final parser = _Asn1Parser(der);
  final sequence = parser.readSequence();
  if (sequence.length >= 2 &&
      sequence[0] is BigInt &&
      sequence[1] is BigInt) {
    return RSAPublicKey(sequence[0] as BigInt, sequence[1] as BigInt);
  }
  if (sequence.length >= 2 && sequence[1] is Uint8List) {
    final nested = _Asn1Parser(sequence[1] as Uint8List).readSequence();
    if (nested.length >= 2 &&
        nested[0] is BigInt &&
        nested[1] is BigInt) {
      return RSAPublicKey(nested[0] as BigInt, nested[1] as BigInt);
    }
  }
  throw const EmAppRuntimeException('Unsupported RSA public key format.');
}

class _Asn1Parser {
  _Asn1Parser(this.bytes);

  final Uint8List bytes;
  int offset = 0;

  List<Object> readSequence() {
    final tag = _readByte();
    if (tag != 0x30) {
      throw const EmAppRuntimeException('Invalid ASN.1 sequence.');
    }
    final length = _readLength();
    final end = offset + length;
    final values = <Object>[];
    while (offset < end) {
      values.add(_readObject());
    }
    return values;
  }

  Object _readObject() {
    final tag = _readByte();
    final length = _readLength();
    final value = bytes.sublist(offset, offset + length);
    offset += length;
    switch (tag) {
      case 0x02:
        return _decodeInteger(value);
      case 0x03:
        if (value.isEmpty) return Uint8List(0);
        return Uint8List.fromList(value.sublist(1));
      case 0x30:
        return _Asn1Parser(
          Uint8List.fromList([tag, ..._encodeLength(length), ...value]),
        ).readSequence();
      default:
        return value;
    }
  }

  int _readByte() {
    if (offset >= bytes.length) {
      throw const EmAppRuntimeException('Unexpected ASN.1 end.');
    }
    return bytes[offset++];
  }

  int _readLength() {
    final first = _readByte();
    if ((first & 0x80) == 0) return first;
    final count = first & 0x7f;
    var value = 0;
    for (var i = 0; i < count; i++) {
      value = (value << 8) | _readByte();
    }
    return value;
  }
}

BigInt _decodeInteger(Uint8List b) {
  var value = BigInt.zero;
  for (final byte in b) {
    value = (value << 8) | BigInt.from(byte);
  }
  return value;
}

List<int> _encodeLength(int length) {
  if (length < 0x80) return [length];
  final bytes = <int>[];
  var value = length;
  while (value > 0) {
    bytes.insert(0, value & 0xff);
    value >>= 8;
  }
  return [0x80 | bytes.length, ...bytes];
}

bool _looksLikeZip(Uint8List bytes) {
  return bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4b &&
      bytes[2] == 0x03 &&
      bytes[3] == 0x04;
}

/// Web bridge script using postMessage (injected into iframe HTML)
const _emAppsBridgeScriptWeb = '''
<script>
(function() {
  if (window.__emapps_bridge && window.__emapps_bridge.__installed) return;
  var pending = {};
  var serial = 1;
  window.__emapps_bridge = {
    __installed: true,
    call: function(method, args) {
      return new Promise(function(resolve, reject) {
        var id = String(serial++);
        pending[id] = { resolve: resolve, reject: reject };
        parent.postMessage(JSON.stringify({
          id: id,
          method: method,
          args: args || {}
        }), '*');
      });
    },
    __complete: function(payload) {
      var item = pending[payload.id];
      if (!item) return;
      delete pending[payload.id];
      if (payload.success) item.resolve(payload.value);
      else item.reject(payload.value);
    }
  };
  window.chat = window.chat || {};
  window.chat.openChat = function(uid) {
    return window.__emapps_bridge.call('chat.openChat', { uid: uid });
  };
  window.chat.sendMessage = function(text) {
    return window.__emapps_bridge.call('chat.sendMessage', { text: text });
  };
})();
</script>
''';
