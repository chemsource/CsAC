// Copyright (c) Chemsource Studio. All rights reserved.
// CsAC jsacratch - eMApps Mini-App IDE Plugin
//
// 小程序项目包含：HTML/CSS/JS 子文件 + app.json 配置
// 上传流程：导出 .ema (JSON) → ACOP upload_ema → 管理员审核 → ACOP通知eMApps签名保存

import 'dart:convert';

/// 小程序项目模型
class MiniAppProject {
  String appId;
  String name;
  String desc;
  String version;
  List<MiniAppFile> files;

  MiniAppProject({
    this.appId = '',
    this.name = 'Untitled MiniApp',
    this.desc = '',
    this.version = '1.0.0',
    List<MiniAppFile>? files,
  }) : files = files ?? [MiniAppFile('index.html', '<!DOCTYPE html>\n<html><body><h1>Hello MiniApp</h1></body></html>')];

  Map<String, dynamic> toJson() => {
    'appId': appId,
    'name': name,
    'desc': desc,
    'version': version,
    'files': files.map((f) => f.toJson()).toList(),
  };

  factory MiniAppProject.fromJson(Map<String, dynamic> json) {
    return MiniAppProject(
      appId: json['appId'] ?? '',
      name: json['name'] ?? 'Untitled',
      desc: json['desc'] ?? '',
      version: json['version'] ?? '1.0.0',
      files: (json['files'] as List?)
          ?.map((f) => MiniAppFile.fromJson(f))
          .toList() ?? [],
    );
  }

  /// 导出为 .ema 格式 JSON（上传到ACOP审核，不含签名）
  String exportEma() {
    return const JsonEncoder.withIndent('  ').convert({
      'appId': appId,
      'name': name,
      'version': version,
      'desc': desc,
      'entryPage': 'index.html',
      'files': files.map((f) => {
        'filename': f.filename,
        'content': f.content,
      }).toList(),
    });
  }

  /// 序列化为 JSON 字符串（存入 .jap）
  String toJsonString() => const JsonEncoder().convert(toJson());

  /// 从 JSON 字符串反序列化
  static MiniAppProject fromJsonString(String jsonStr) {
    return MiniAppProject.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
  }
}

/// 小程序文件
class MiniAppFile {
  String filename;
  String content;

  MiniAppFile(this.filename, this.content);

  Map<String, dynamic> toJson() => {'filename': filename, 'content': content};
  factory MiniAppFile.fromJson(Map<String, dynamic> json) =>
      MiniAppFile(json['filename'] ?? '', json['content'] ?? '');
}
