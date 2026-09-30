import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../api/api_services.dart';
import '../models/models.dart';

class AppState extends ChangeNotifier {
  final ApiClient apiClient;
  late final DevService devService;
  late final BotService botService;
  late final ScriptService scriptService;
  late final LogService logService;
  late final PermService permService;
  late final LibService libService;
  late final AdminLibService adminLibService;
  late final AdminService adminService;

  bool _initialized = false;
  bool _loggedIn = false;
  DevInfo? _devInfo;
  List<BotInfo> _bots = [];
  bool _loading = false;
  String? _error;

  AppState({String? baseUrl})
      : apiClient = ApiClient(url: baseUrl ?? '') {
    devService = DevService(apiClient);
    botService = BotService(apiClient);
    scriptService = ScriptService(apiClient);
    logService = LogService(apiClient);
    permService = PermService(apiClient);
    libService = LibService(apiClient);
    adminLibService = AdminLibService(apiClient);
    adminService = AdminService(apiClient);
  }

  bool get initialized => _initialized;
  bool get loggedIn => _loggedIn;
  DevInfo? get devInfo => _devInfo;
  List<BotInfo> get bots => _bots;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> init() async {
    await apiClient.loadSession();
    if (apiClient.isLoggedIn) {
      final result = await devService.getInfo();
      if (result['success'] == true && result['data'] != null) {
        _devInfo = DevInfo.fromJson(result['data'] as Map<String, dynamic>);
        _loggedIn = true;
        await refreshBots();
      }
    }
    _initialized = true;
    notifyListeners();
  }

  Future<bool> login(String email, String pwd) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await devService.login(email: email, pwd: pwd);
      if (result['success'] == true) {
        _loggedIn = true;
        final infoResult = await devService.getInfo();
        if (infoResult['success'] == true && infoResult['data'] != null) {
          _devInfo = DevInfo.fromJson(infoResult['data'] as Map<String, dynamic>);
        }
        await refreshBots();
        _loading = false;
        notifyListeners();
        return true;
      } else {
        _error = result['message'] as String? ?? '登录失败';
        _loading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = '网络错误: $e';
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register(String email, String pwd, String devName, String code, String csacUsername, String csacPassword) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await devService.register(email: email, pwd: pwd, devName: devName, code: code, csacUsername: csacUsername, csacPassword: csacPassword);
      if (result['success'] == true) {
        // 注册后自动登录
        return await login(email, pwd);
      } else {
        _error = result['message'] as String? ?? '注册失败';
        _loading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = '网络错误: $e';
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> loginByCode(String email, String code) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await devService.loginByCode(email: email, code: code);
      if (result['success'] == true) {
        _loggedIn = true;
        final infoResult = await devService.getInfo();
        if (infoResult['success'] == true && infoResult['data'] != null) {
          _devInfo = DevInfo.fromJson(infoResult['data'] as Map<String, dynamic>);
        }
        await refreshBots();
        _loading = false;
        notifyListeners();
        return true;
      } else {
        _error = result['message'] as String? ?? '验证码登录失败';
        _loading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = '网络错误: $e';
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  Future<Map<String, dynamic>> sendCode(String email, String purpose) async {
    return await devService.sendCode(email: email, purpose: purpose);
  }

  Future<void> logout() async {
    await devService.logout();
    _loggedIn = false;
    _devInfo = null;
    _bots = [];
    notifyListeners();
  }

  Future<void> refreshBots() async {
    final result = await botService.list();
    if (result['success'] == true && result['data'] != null) {
      final list = result['data'] as List;
      _bots = list.map((e) => BotInfo.fromJson(e as Map<String, dynamic>)).toList();
    }
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
