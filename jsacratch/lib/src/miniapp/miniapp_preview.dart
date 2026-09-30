// Copyright (c) Chemsource Studio. All rights reserved.
// CsAC jsacratch - MiniApp Preview (Python HTTP server)

import 'dart:async';
import 'dart:io';

import 'miniapp_plugin.dart';

/// 小程序本地预览管理器
/// 将小程序文件写入临时目录，启动 Python HTTP 服务，在浏览器预览
class MiniAppPreview {
  Process? _server;
  String? _tempDir;
  int _port = 0;

  bool get isRunning => _server != null;
  int get port => _port;
  String? get url => isRunning ? 'http://127.0.0.1:$_port/index.html' : null;

  /// 查找 Python 可执行文件路径，找不到返回 null
  static Future<String?> _findPython() async {
    final candidates = ['python', 'python3', 'py'];
    for (final name in candidates) {
      try {
        final result = await Process.run(name, ['--version'],
            runInShell: true);
        if (result.exitCode == 0) return name;
      } catch (_) {}
    }

    // 检查 Windows 常见安装路径
    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null) {
        final programsDir = Directory(
            '$localAppData\\Programs\\Python');
        if (await programsDir.exists()) {
          await for (final entity in programsDir.list()) {
            if (entity is Directory) {
              final pythonExe = File('${entity.path}\\python.exe');
              if (await pythonExe.exists()) return pythonExe.path;
            }
          }
        }
      }
      // 检查 C:\ 根目录
      for (final root in ['C:\\', 'D:\\']) {
        final rootDir = Directory('$root\\Python');
        // Try Python3x patterns
        try {
          final python3dirs = Directory(root)
              .listSync()
              .whereType<Directory>()
              .where((d) {
            final name = d.path.split('\\').last;
            return name.startsWith('Python3');
          });
          for (final d in python3dirs) {
            final exe = File('${d.path}\\python.exe');
            if (exe.existsSync()) return exe.path;
          }
        } catch (_) {}
      }
      // Try Microsoft Store Python
      try {
        final msDir = Directory(
            '${Platform.environment['LOCALAPPDATA']}\\Microsoft\\WindowsApps');
        if (await msDir.exists()) {
          final msPy = File('${msDir.path}\\python3.exe');
          if (await msPy.exists()) return msPy.path;
          final msPy2 = File('${msDir.path}\\python.exe');
          if (await msPy2.exists()) return msPy2.path;
        }
      } catch (_) {}
    }

    return null;
  }

  /// 启动预览：写入文件 → 启动 Python HTTP 服务 → 返回 URL
  Future<PreviewResult> start(MiniAppProject project) async {
    if (_server != null) {
      return PreviewResult.error('预览已在运行中，请先关闭当前预览');
    }

    // 1. 查找 Python
    final pythonPath = await _findPython();
    if (pythonPath == null) {
      return PreviewResult.error(
        '未找到 Python。请安装 Python 3 并添加到 PATH。\n'
        '下载地址: https://www.python.org/downloads/',
      );
    }

    // 2. 创建临时目录并写入文件
    try {
      _tempDir = (await Directory.systemTemp
              .createTemp('jsacratch_preview_'))
          .path;
      final dir = Directory(_tempDir!);
      for (final file in project.files) {
        final filePath = '${dir.path}/${file.filename}';
        // 确保父目录存在（处理子目录如 css/style.css）
        final parent = File(filePath).parent;
        if (!await parent.exists()) {
          await parent.create(recursive: true);
        }
        await File(filePath).writeAsString(file.content);
      }
    } catch (e) {
      return PreviewResult.error('写入临时文件失败: $e');
    }

    // 3. 找一个空闲端口
    _port = await _findFreePort();
    if (_port == 0) {
      await _cleanup();
      return PreviewResult.error('无法分配端口');
    }

    // 4. 启动 Python HTTP 服务
    try {
      _server = await Process.start(
        pythonPath,
        ['-m', 'http.server', _port.toString()],
        workingDirectory: _tempDir,
        mode: ProcessStartMode.normal,
      );

      // 监听 stderr 检查启动是否成功
      _server!.stderr.transform(const SystemEncoding().decoder).listen((data) {
        // Python http.server 正常输出在 stderr
      });

      // 等待 HTTP 服务完全启动
      await Future.delayed(const Duration(milliseconds: 1500));

      // 检查进程是否还活着
      if (_server!.exitCode is Future) {
        // 进程仍在运行，说明启动成功
        return PreviewResult.ok(url: url!, tempDir: _tempDir!);
      }

      await _cleanup();
      return PreviewResult.error('Python HTTP 服务启动失败');
    } catch (e) {
      await _cleanup();
      return PreviewResult.error('启动 Python 失败: $e');
    }
  }

  /// 停止预览，清理临时目录
  Future<void> stop() async {
    if (_server != null) {
      try {
        _server!.kill(ProcessSignal.sigterm);
      } catch (_) {}
      _server = null;
    }
    await _cleanup();
    _port = 0;
  }

  Future<void> _cleanup() async {
    if (_tempDir != null) {
      try {
        final dir = Directory(_tempDir!);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (_) {}
      _tempDir = null;
    }
  }

  /// 查找一个空闲端口
  Future<int> _findFreePort() async {
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      await server.close();
      return port;
    } catch (_) {
      return 0;
    }
  }
}

/// 预览启动结果
class PreviewResult {
  final bool success;
  final String? error;
  final String? baseUrl;
  final String? tempDir;

  PreviewResult._({required this.success, this.error, this.baseUrl, this.tempDir});

  factory PreviewResult.ok({required String url, required String tempDir}) {
    return PreviewResult._(success: true, baseUrl: url, tempDir: tempDir);
  }

  factory PreviewResult.error(String msg) {
    return PreviewResult._(success: false, error: msg);
  }
}
