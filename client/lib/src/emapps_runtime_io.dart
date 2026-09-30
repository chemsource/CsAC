import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
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
    final tempRoot = await _createRuntimeDirectory(info);
    await _extractPackage(bytes, tempRoot);
    final server = await _EmAppFileServer.start(
      root: tempRoot,
      entryPage: info.entryPage,
      onLog: _log,
    );
    _log('HTTP', 'Serving ${server.url}');
    return EmAppLaunchResult(
      package: info,
      url: server.url,
      logs: List<EmAppRuntimeLogEntry>.unmodifiable(_logs),
      close: () async {
        await server.close();
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
        _log('EMAPPS', 'Closed ${info.appId}');
      },
    );
  }

  Future<List<EmAppRuntimeLogEntry>> loadStoredLogs() async {
    final file = await _logFile();
    if (!await file.exists()) {
      return const <EmAppRuntimeLogEntry>[];
    }
    final lines = await file.readAsLines();
    return [
      for (final line in lines.reversed.take(300).toList().reversed)
        _parseLogLine(line),
    ].whereType<EmAppRuntimeLogEntry>().toList();
  }

  Future<void> clearStoredData() async {
    final support = await getApplicationSupportDirectory();
    final cache = Directory(p.join(support.path, 'emapps'));
    if (await cache.exists()) {
      await cache.delete(recursive: true);
    }
    final logs = Directory(p.join(support.path, 'logs'));
    if (await logs.exists()) {
      await for (final entity in logs.list()) {
        if (entity is File && p.basename(entity.path).startsWith('emapps_')) {
          await entity.delete();
        }
      }
    }
  }

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

  Future<Directory> _createRuntimeDirectory(EmAppPackage info) async {
    final temp = await getTemporaryDirectory();
    final suffix = DateTime.now().microsecondsSinceEpoch;
    final random = Random().nextInt(1 << 32);
    final dir = Directory(
      p.join(temp.path, 'csac_emapp_${_safeName(info.appId)}_$suffix$random'),
    );
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> _extractPackage(Uint8List bytes, Directory root) async {
    if (_looksLikeZip(bytes)) {
      await _extractZip(bytes, root);
      return;
    }
    await _extractEma(bytes, root);
  }

  Future<void> _extractZip(Uint8List bytes, Directory root) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    var htmlCount = 0;
    for (final file in archive.files) {
      if (!file.isFile) {
        continue;
      }
      final target = _safeChild(root, file.name);
      await Directory(p.dirname(target.path)).create(recursive: true);
      await target.writeAsBytes(file.content as List<int>);
      if (p.extension(file.name).toLowerCase() == '.html') {
        htmlCount++;
      }
    }
    if (htmlCount == 0) {
      throw const EmAppRuntimeException('Package does not contain HTML.');
    }
    _log('EMAPPS', 'Extracted ZIP package with $htmlCount HTML file(s)');
  }

  Future<void> _extractEma(Uint8List bytes, Directory root) async {
    final text = utf8.decode(bytes, allowMalformed: false);
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const EmAppRuntimeException('Invalid EMA package.');
    }
    final files = decoded['files'];
    var written = 0;
    if (files is List && files.isNotEmpty) {
      for (final item in files.whereType<Map>()) {
        final filename = item['filename']?.toString() ?? '';
        final content = item['content']?.toString() ?? '';
        if (filename.trim().isEmpty) {
          continue;
        }
        final target = _safeChild(root, filename);
        await Directory(p.dirname(target.path)).create(recursive: true);
        await target.writeAsString(content, encoding: utf8);
        written++;
      }
    } else {
      final appName = decoded['name']?.toString() ?? 'eMApp';
      final html =
          '''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>${htmlEscape.convert(appName)}</title></head>
<body><h1>${htmlEscape.convert(appName)}</h1><p>Empty eMApp package.</p></body>
</html>
''';
      await File(p.join(root.path, 'index.html')).writeAsString(html);
      written = 1;
    }
    if (written == 0) {
      throw const EmAppRuntimeException('EMA package does not contain files.');
    }
    _log('EMAPPS', 'Extracted EMA package with $written file(s)');
  }

  void _log(String kind, String message) {
    final entry = EmAppRuntimeLogEntry(
      kind: kind,
      message: message,
      time: DateTime.now(),
    );
    _logs.add(entry);
    if (_persistLogs) {
      unawaited(_appendLog(entry));
    }
  }
}

class _EmAppFileServer {
  const _EmAppFileServer({
    required this.server,
    required this.root,
    required this.entryPage,
    required this.url,
    required this.onLog,
  });

  final HttpServer server;
  final Directory root;
  final String entryPage;
  final Uri url;
  final void Function(String kind, String message) onLog;

  static Future<_EmAppFileServer> start({
    required Directory root,
    required String entryPage,
    required void Function(String kind, String message) onLog,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final instance = _EmAppFileServer(
      server: server,
      root: root,
      entryPage: entryPage.trim().isEmpty ? 'index.html' : entryPage.trim(),
      url: Uri.parse('http://127.0.0.1:${server.port}/'),
      onLog: onLog,
    );
    unawaited(instance._serve());
    return instance;
  }

  Future<void> close() async {
    await server.close(force: true);
  }

  Future<void> _serve() async {
    await for (final request in server) {
      await _handle(request);
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final requested = request.uri.path == '/'
        ? entryPage
        : Uri.decodeComponent(
            request.uri.path.replaceFirst(RegExp(r'^/+'), ''),
          );
    try {
      final file = _safeChild(root, requested);
      if (!await file.exists()) {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('404 Not Found');
        onLog('HTTP', '404 ${request.uri.path}');
      } else {
        request.response.headers.contentType = _contentType(file.path);
        await request.response.addStream(file.openRead());
        onLog('HTTP', '200 ${request.uri.path}');
      }
    } on EmAppRuntimeException {
      request.response.statusCode = HttpStatus.forbidden;
      request.response.write('403 Forbidden');
      onLog('HTTP', '403 ${request.uri.path}');
    } catch (err) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('500 $err');
      onLog('HTTP', '500 ${request.uri.path}: $err');
    } finally {
      await request.response.close();
    }
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
  final bytes = base64Decode(normalized);
  final parser = _Asn1Parser(bytes);
  final sequence = parser.readSequence();
  if (sequence.length >= 2 && sequence[0] is BigInt && sequence[1] is BigInt) {
    return RSAPublicKey(sequence[0] as BigInt, sequence[1] as BigInt);
  }
  if (sequence.length >= 2 && sequence[1] is Uint8List) {
    final nested = _Asn1Parser(sequence[1] as Uint8List).readSequence();
    if (nested.length >= 2 && nested[0] is BigInt && nested[1] is BigInt) {
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
        if (value.isEmpty) {
          return Uint8List(0);
        }
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
    if ((first & 0x80) == 0) {
      return first;
    }
    final count = first & 0x7f;
    var value = 0;
    for (var i = 0; i < count; i++) {
      value = (value << 8) | _readByte();
    }
    return value;
  }
}

BigInt _decodeInteger(Uint8List bytes) {
  var value = BigInt.zero;
  for (final byte in bytes) {
    value = (value << 8) | BigInt.from(byte);
  }
  return value;
}

List<int> _encodeLength(int length) {
  if (length < 0x80) {
    return [length];
  }
  final bytes = <int>[];
  var value = length;
  while (value > 0) {
    bytes.insert(0, value & 0xff);
    value >>= 8;
  }
  return [0x80 | bytes.length, ...bytes];
}

File _safeChild(Directory root, String relativePath) {
  final normalized = p.normalize(relativePath).replaceAll('\\', '/');
  if (normalized.startsWith('../') ||
      normalized == '..' ||
      p.isAbsolute(normalized)) {
    throw const EmAppRuntimeException('Illegal package path.');
  }
  final target = File(p.join(root.path, normalized));
  final rootPath = p.canonicalize(root.path);
  final targetPath = p.canonicalize(target.path);
  if (targetPath != rootPath && !p.isWithin(rootPath, targetPath)) {
    throw const EmAppRuntimeException('Illegal package path.');
  }
  return target;
}

ContentType _contentType(String path) {
  switch (p.extension(path).toLowerCase()) {
    case '.html':
    case '.htm':
      return ContentType.html;
    case '.css':
      return ContentType('text', 'css', charset: 'utf-8');
    case '.js':
      return ContentType('application', 'javascript', charset: 'utf-8');
    case '.json':
      return ContentType.json;
    case '.png':
      return ContentType('image', 'png');
    case '.jpg':
    case '.jpeg':
      return ContentType('image', 'jpeg');
    case '.gif':
      return ContentType('image', 'gif');
    case '.svg':
      return ContentType('image', 'svg+xml');
    case '.ico':
      return ContentType('image', 'x-icon');
    case '.woff2':
      return ContentType('font', 'woff2');
    case '.woff':
      return ContentType('font', 'woff');
    case '.ttf':
      return ContentType('font', 'ttf');
    default:
      return ContentType.binary;
  }
}

bool _looksLikeZip(Uint8List bytes) {
  return bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4b &&
      bytes[2] == 0x03 &&
      bytes[3] == 0x04;
}

String _safeName(String value) {
  return value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
}

Future<File> _logFile() async {
  final support = await getApplicationSupportDirectory();
  final dir = Directory(p.join(support.path, 'logs'));
  await dir.create(recursive: true);
  final now = DateTime.now();
  final name =
      'emapps_debug_${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.log';
  await _cleanupOldLogs(dir);
  return File(p.join(dir.path, name));
}

Future<void> _appendLog(EmAppRuntimeLogEntry entry) async {
  final file = await _logFile();
  await file.writeAsString(
    '${entry.time.toIso8601String()} ${entry.kind} ${entry.message}\n',
    mode: FileMode.append,
    flush: false,
  );
}

Future<void> _cleanupOldLogs(Directory dir) async {
  final cutoff = DateTime.now().subtract(const Duration(days: 7));
  await for (final entity in dir.list()) {
    if (entity is! File || !p.basename(entity.path).startsWith('emapps_')) {
      continue;
    }
    final stat = await entity.stat();
    if (stat.modified.isBefore(cutoff)) {
      await entity.delete();
    }
  }
}

EmAppRuntimeLogEntry? _parseLogLine(String line) {
  final firstSpace = line.indexOf(' ');
  if (firstSpace <= 0) {
    return null;
  }
  final secondSpace = line.indexOf(' ', firstSpace + 1);
  if (secondSpace <= firstSpace) {
    return null;
  }
  final time = DateTime.tryParse(line.substring(0, firstSpace));
  if (time == null) {
    return null;
  }
  return EmAppRuntimeLogEntry(
    kind: line.substring(firstSpace + 1, secondSpace),
    message: line.substring(secondSpace + 1),
    time: time,
  );
}
