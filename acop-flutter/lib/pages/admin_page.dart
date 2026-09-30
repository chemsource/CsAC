import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  bool _isAdmin = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _checkAdmin();
  }

  Future<void> _checkAdmin() async {
    final state = context.read<AppState>();
    final result = await state.apiClient.post('admin/check', {});
    if (mounted) {
      setState(() {
        _isAdmin = result['is_admin'] == true;
        _checking = false;
      });
    }
  }

  void _showAdminLogin() {
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('管理员登录'),
        content: SizedBox(
          width: 300,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('请输入管理员对应的 CsAC 账号密码', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: userCtrl,
              decoration: const InputDecoration(labelText: 'CsAC 用户名'),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: passCtrl,
              decoration: const InputDecoration(labelText: 'CsAC 密码'),
              obscureText: true,
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final state = context.read<AppState>();
              final result = await state.apiClient.post('admin/login', {
                'csac_username': userCtrl.text.trim(),
                'csac_password': passCtrl.text.trim(),
              });
              if (!mounted) return;
              if (result['success'] == true) {
                Navigator.pop(ctx);
                _checkAdmin();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('登录失败: ${result['message'] ?? ''}')),
                );
              }
            },
            child: const Text('登录'),
          ),
        ],
      ),
    );
  }

  Future<void> _logoutAdmin() async {
    final state = context.read<AppState>();
    await state.apiClient.post('admin/logout', {});
    setState(() => _isAdmin = false);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('管理员面板')),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.admin_panel_settings, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text('需要管理员权限', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text('请使用管理员 CsAC 账号登录', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _showAdminLogin,
              icon: const Icon(Icons.login),
              label: const Text('管理员登录'),
            ),
          ]),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('管理员面板'),
        actions: [
          TextButton.icon(
            onPressed: _logoutAdmin,
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('退出管理员'),
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(icon: Icon(Icons.security), text: '权限申请'),
            Tab(icon: Icon(Icons.description), text: 'ACR 审核'),
            Tab(icon: Icon(Icons.library_books), text: 'AJL 库审核'),
            Tab(icon: Icon(Icons.widgets), text: 'EMA 审核'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: const [
          _PermTab(),
          _AcrTab(),
          _LibTab(),
          _EmaTab(),
        ],
      ),
    );
  }
}

// ===== Tab 1: 权限申请审核 =====

class _PermTab extends StatefulWidget {
  const _PermTab();

  @override
  State<_PermTab> createState() => _PermTabState();
}

class _PermTabState extends State<_PermTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final state = context.read<AppState>();
    final result = await state.adminService.permPending();
    if (!mounted) return;
    if (result['success'] == true) {
      final data = result['data'];
      setState(() {
        _items = data != null ? List<Map<String, dynamic>>.from(data as List) : [];
        _error = null;
      });
    } else {
      setState(() { _error = result['message']?.toString() ?? '加载失败'; });
    }
    setState(() => _loading = false);
  }

  Future<void> _handle(int requestId, String action) async {
    final state = context.read<AppState>();
    final result = await state.adminService.permHandle(requestId: requestId, action: action);
    if (!mounted) return;
    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(action == 'approve' ? '已通过权限申请' : '已拒绝权限申请')),
      );
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败: ${result['message'] ?? ''}')),
      );
    }
  }

  String _permLabel(String type) {
    return switch (type) {
      'notify' => '发送通知',
      'http' => 'HTTP请求',
      _ => type,
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline, size: 48, color: cs.error),
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: cs.error, fontSize: 14)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ]),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle_outline, size: 48, color: cs.outline),
          const SizedBox(height: 8),
          Text('没有待处理的权限申请', style: TextStyle(color: cs.onSurfaceVariant)),
        ]),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        itemBuilder: (_, i) {
          final item = _items[i];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.security, size: 18, color: cs.primary),
                    const SizedBox(width: 8),
                    Text('权限申请 #${item['id']}',
                        style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('待审核', style: TextStyle(fontSize: 11, color: Colors.orange.shade700)),
                    ),
                  ]),
                  const Divider(height: 16),
                  _InfoRow('Bot', item['bot_name']?.toString() ?? ''),
                  _InfoRow('BotID', '${item['bot_id']}'),
                  _InfoRow('权限类型', _permLabel(item['perm_type']?.toString() ?? '')),
                  _InfoRow('开发者', item['dev_name']?.toString() ?? ''),
                  _InfoRow('邮箱', item['email']?.toString() ?? ''),
                  _InfoRow('申请时间', item['created_at']?.toString() ?? ''),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('申请理由', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      Text(item['reason']?.toString() ?? '',
                          style: TextStyle(fontSize: 13, color: cs.onSurface)),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    OutlinedButton.icon(
                      onPressed: () => _handle((item['id'] as num).toInt(), 'reject'),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('拒绝'),
                      style: OutlinedButton.styleFrom(foregroundColor: cs.error),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => _handle((item['id'] as num).toInt(), 'approve'),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('通过'),
                    ),
                  ]),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ===== Tab 2: ACR 脚本审核 =====

class _AcrTab extends StatefulWidget {
  const _AcrTab();

  @override
  State<_AcrTab> createState() => _AcrTabState();
}

class _AcrTabState extends State<_AcrTab> {
  List<Map<String, dynamic>> _items = [];
  Map<int, String> _previews = {};
  Set<int> _loadingPreview = {};
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final state = context.read<AppState>();
    final result = await state.adminService.acrPending();
    if (!mounted) return;
    if (result['success'] == true) {
      final data = result['data'];
      setState(() {
        _items = data != null ? List<Map<String, dynamic>>.from(data as List) : [];
        _previews.clear();
        _error = null;
      });
    } else {
      setState(() { _error = result['message']?.toString() ?? '加载失败'; });
    }
    setState(() => _loading = false);
  }

  Future<void> _loadPreview(int uploadId) async {
    if (_previews.containsKey(uploadId) || _loadingPreview.contains(uploadId)) return;
    setState(() => _loadingPreview.add(uploadId));
    final state = context.read<AppState>();
    final result = await state.adminService.acrRead(uploadId);
    if (result['success'] == true) {
      setState(() => _previews[uploadId] = result['content']?.toString() ?? '');
    }
    setState(() => _loadingPreview.remove(uploadId));
  }

  Future<void> _review(int uploadId, String action) async {
    final state = context.read<AppState>();
    final result = await state.adminService.acrReview(uploadId: uploadId, action: action);
    if (!mounted) return;
    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(action == 'approve' ? '已通过ACR脚本' : '已拒绝ACR脚本')),
      );
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败: ${result['message'] ?? ''}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline, size: 48, color: cs.error),
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: cs.error, fontSize: 14)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ]),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle_outline, size: 48, color: cs.outline),
          const SizedBox(height: 8),
          Text('没有待审核的ACR脚本', style: TextStyle(color: cs.onSurfaceVariant)),
        ]),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        itemBuilder: (_, i) {
          final item = _items[i];
          final uploadId = (item['id'] as num).toInt();
          final hasPreview = _previews.containsKey(uploadId);
          final isLoadingPreview = _loadingPreview.contains(uploadId);

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.description, size: 18, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(item['file_name']?.toString() ?? '',
                          style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('待审核', style: TextStyle(fontSize: 11, color: Colors.orange.shade700)),
                    ),
                  ]),
                  const Divider(height: 16),
                  _InfoRow('文件类型', (item['file_type']?.toString() ?? '').toUpperCase()),
                  _InfoRow('开发者', item['dev_name']?.toString() ?? ''),
                  _InfoRow('邮箱', item['email']?.toString() ?? ''),
                  _InfoRow('上传时间', item['created_at']?.toString() ?? ''),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () {
                      if (hasPreview) {
                        setState(() => _previews.remove(uploadId));
                      } else {
                        _loadPreview(uploadId);
                      }
                    },
                    child: Row(children: [
                      Icon(
                        hasPreview ? Icons.expand_less : Icons.expand_more,
                        size: 18, color: cs.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isLoadingPreview ? '加载中...' : (hasPreview ? '收起脚本内容' : '查看脚本内容'),
                        style: TextStyle(fontSize: 12, color: cs.primary),
                      ),
                    ]),
                  ),
                  if (hasPreview) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 300),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          _previews[uploadId] ?? '',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: Color(0xFFD4D4D4),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    OutlinedButton.icon(
                      onPressed: () => _review(uploadId, 'reject'),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('拒绝'),
                      style: OutlinedButton.styleFrom(foregroundColor: cs.error),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => _review(uploadId, 'approve'),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('通过'),
                    ),
                  ]),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ===== Tab 3: AJL 库审核 =====

class _LibTab extends StatefulWidget {
  const _LibTab();

  @override
  State<_LibTab> createState() => _LibTabState();
}

class _LibTabState extends State<_LibTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final state = context.read<AppState>();
    final result = await state.adminLibService.pending();
    if (!mounted) return;
    if (result['success'] == true) {
      final data = result['data'];
      setState(() {
        _items = data != null ? List<Map<String, dynamic>>.from(data as List) : [];
        _error = null;
      });
    } else {
      setState(() { _error = result['message']?.toString() ?? '加载失败'; });
    }
    setState(() => _loading = false);
  }

  Future<void> _review(int libId, String action) async {
    final state = context.read<AppState>();
    final result = await state.adminLibService.review(libId: libId, action: action);
    if (!mounted) return;
    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(action == 'approve' ? '已通过AJL库' : '已拒绝AJL库')),
      );
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败: ${result['message'] ?? ''}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline, size: 48, color: cs.error),
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: cs.error, fontSize: 14)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ]),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle_outline, size: 48, color: cs.outline),
          const SizedBox(height: 8),
          Text('没有待审核的AJL库', style: TextStyle(color: cs.onSurfaceVariant)),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        itemBuilder: (_, i) {
          final item = _items[i];
          final libId = (item['id'] as num).toInt();
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.library_books, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item['name']?.toString() ?? '',
                      style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('待审核', style: TextStyle(fontSize: 11, color: Colors.orange.shade700)),
                  ),
                ]),
                const Divider(height: 16),
                _InfoRow('版本', item['version']?.toString() ?? ''),
                _InfoRow('作者', item['author']?.toString() ?? ''),
                _InfoRow('描述', item['desc']?.toString() ?? ''),
                _InfoRow('开发者', item['dev_name']?.toString() ?? ''),
                _InfoRow('提交时间', item['created_at']?.toString() ?? ''),
                if ((item['content']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 200),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        item['content']?.toString() ?? '',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFD4D4D4), height: 1.5),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  OutlinedButton.icon(
                    onPressed: () => _review(libId, 'reject'),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('拒绝'),
                    style: OutlinedButton.styleFrom(foregroundColor: cs.error),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => _review(libId, 'approve'),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('通过'),
                  ),
                ]),
              ]),
            ),
          );
        },
      ),
    );
  }
}

// ===== Tab 4: EMA 小程序审核 =====

class _EmaTab extends StatefulWidget {
  const _EmaTab();

  @override
  State<_EmaTab> createState() => _EmaTabState();
}

class _EmaTabState extends State<_EmaTab> {
  List<Map<String, dynamic>> _items = [];
  Map<int, String> _previews = {};
  Set<int> _loadingPreview = {};
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final state = context.read<AppState>();
    final result = await state.adminService.emaPending();
    if (!mounted) return;
    if (result['success'] == true) {
      final data = result['data'];
      setState(() {
        _items = data != null ? List<Map<String, dynamic>>.from(data as List) : [];
        _previews.clear();
        _error = null;
      });
    } else {
      setState(() { _error = result['message']?.toString() ?? '加载失败'; });
    }
    setState(() => _loading = false);
  }

  Future<void> _loadPreview(int uploadId) async {
    if (_previews.containsKey(uploadId) || _loadingPreview.contains(uploadId)) return;
    setState(() => _loadingPreview.add(uploadId));
    final state = context.read<AppState>();
    final result = await state.adminService.emaRead(uploadId);
    if (result['success'] == true) {
      setState(() => _previews[uploadId] = result['content']?.toString() ?? '');
    }
    setState(() => _loadingPreview.remove(uploadId));
  }

  Future<void> _review(int uploadId, String action) async {
    final state = context.read<AppState>();
    final result = await state.adminService.emaReview(uploadId: uploadId, action: action);
    if (!mounted) return;
    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(action == 'approve' ? 'EMA审核已通过' : 'EMA审核已拒绝')),
      );
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败: ${result['message'] ?? ''}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline, size: 48, color: cs.error),
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: cs.error, fontSize: 14)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ]),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle_outline, size: 48, color: cs.outline),
          const SizedBox(height: 8),
          Text('没有待审核的EMA小程序', style: TextStyle(color: cs.onSurfaceVariant)),
        ]),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        itemBuilder: (_, i) {
          final item = _items[i];
          final uploadId = (item['id'] as num).toInt();
          final status = (item['status'] as num?)?.toInt() ?? 0;
          final isPending = status == 0;
          final isApproved = status == 1;
          final hasPreview = _previews.containsKey(uploadId);
          final isLoadingPreview = _loadingPreview.contains(uploadId);

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.widgets, size: 18, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(item['file_name']?.toString() ?? '',
                          style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface)),
                    ),
                    if (isPending)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('待审核', style: TextStyle(fontSize: 11, color: Colors.orange.shade700)),
                      ),
                    if (isApproved)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('已通过', style: TextStyle(fontSize: 11, color: Colors.green.shade700)),
                      ),
                    if (!isPending && !isApproved)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('已拒绝', style: TextStyle(fontSize: 11, color: Colors.red.shade700)),
                      ),
                  ]),
                  const Divider(height: 16),
                  _InfoRow('开发者', item['dev_name']?.toString() ?? ''),
                  _InfoRow('邮箱', item['email']?.toString() ?? ''),
                  _InfoRow('文件大小', '${item['file_size'] ?? 0} B'),
                  _InfoRow('上传时间', item['created_at']?.toString() ?? ''),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () {
                      if (hasPreview) {
                        setState(() => _previews.remove(uploadId));
                      } else {
                        _loadPreview(uploadId);
                      }
                    },
                    child: Row(children: [
                      Icon(
                        hasPreview ? Icons.expand_less : Icons.expand_more,
                        size: 18, color: cs.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isLoadingPreview ? '加载中...' : (hasPreview ? '收起内容' : '查看EMA源内容'),
                        style: TextStyle(fontSize: 12, color: cs.primary),
                      ),
                    ]),
                  ),
                  if (hasPreview) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 300),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          _previews[uploadId] ?? '',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: Color(0xFFD4D4D4),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (isPending)
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      OutlinedButton.icon(
                        onPressed: () => _review(uploadId, 'reject'),
                        icon: const Icon(Icons.close, size: 16),
                        label: const Text('拒绝'),
                        style: OutlinedButton.styleFrom(foregroundColor: cs.error),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () => _review(uploadId, 'approve'),
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('通过'),
                      ),
                    ]),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(
          width: 70,
          child: Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ),
        Expanded(child: Text(value, style: TextStyle(fontSize: 13, color: cs.onSurface))),
      ]),
    );
  }
}
