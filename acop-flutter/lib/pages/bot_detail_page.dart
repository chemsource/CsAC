import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models/models.dart';
import 'script_editor_page.dart';
import 'log_page.dart';

class BotDetailPage extends StatefulWidget {
  final int botId;
  final String botName;
  const BotDetailPage({super.key, required this.botId, required this.botName});

  @override
  State<BotDetailPage> createState() => _BotDetailPageState();
}

class _BotDetailPageState extends State<BotDetailPage> {
  final _imagePicker = ImagePicker();
  BotInfo? _botInfo;
  List<ScriptInfo> _scripts = [];
  List<PermRequest> _permRequests = [];
  bool _loading = true;
  bool _infoExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final state = context.read<AppState>();
    final infoResult = await state.botService.getInfo(widget.botId);
    final scriptResult = await state.scriptService.list(widget.botId);
    final permResult = await state.permService.list(widget.botId);

    if (infoResult['success'] == true && infoResult['data'] != null) {
      _botInfo = BotInfo.fromJson(infoResult['data'] as Map<String, dynamic>);
    }
    if (scriptResult['success'] == true && scriptResult['data'] != null) {
      final list = scriptResult['data'] as List;
      _scripts = list
          .map((e) => ScriptInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (permResult['success'] == true && permResult['data'] != null) {
      final list = permResult['data'] as List;
      _permRequests = list
          .map((e) => PermRequest.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.botName),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: '刷新',
          ),
          PopupMenuButton(
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'set_avatar', child: Text('设置头像')),
              const PopupMenuItem(value: 'reset_token', child: Text('重置Token')),
              const PopupMenuItem(
                value: 'delete',
                child: Text('删除Bot', style: TextStyle(color: Colors.red)),
              ),
            ],
            onSelected: (v) {
              if (v == 'set_avatar') _setAvatar();
              if (v == 'reset_token') _resetToken();
              if (v == 'delete') _deleteBot();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Bot信息
                  _buildInfoCard(),
                  const SizedBox(height: 16),
                  // 权限状态
                  _buildPermCard(),
                  const SizedBox(height: 16),
                  // 脚本列表
                  _buildScriptsSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoCard() {
    final bot = _botInfo;
    if (bot == null) return const SizedBox.shrink();

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: _botAvatar(bot, 46),
            title: Text(bot.botName),
            subtitle: Text(
              bot.botAvatar.isEmpty
                  ? 'UID: ${bot.uid}'
                  : 'UID: ${bot.uid} · 已设置头像',
            ),
            trailing: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: _setAvatar,
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: const Text('头像'),
                ),
                Chip(
                  label: Text(bot.isOnline ? '在线' : '离线'),
                  avatar: CircleAvatar(
                    radius: 4,
                    backgroundColor: bot.isOnline ? Colors.green : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          if (bot.botAvatar.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SelectableText(
                bot.botAvatar,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ),
          if (_infoExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow('Bot ID', '${bot.botId}'),
                  _infoRow('UID', '${bot.uid}'),
                  _infoRow('Token', bot.botToken ?? '***'),
                  _infoRow('描述', bot.botDesc),
                  _infoRow('状态', bot.isActive ? '正常' : '禁用'),
                  _infoRow('通知权限', bot.canNotify == 1 ? '已开启' : '未开启'),
                  _infoRow('HTTP权限', bot.canHttp == 1 ? '已开启' : '未开启'),
                ],
              ),
            ),
          ],
          TextButton(
            onPressed: () => setState(() => _infoExpanded = !_infoExpanded),
            child: Text(_infoExpanded ? '收起' : '查看详情'),
          ),
        ],
      ),
    );
  }

  Widget _botAvatar(BotInfo bot, double size) {
    final avatar = bot.botAvatar.trim();
    if (avatar.isEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: bot.isOnline
            ? Colors.green.shade100
            : Colors.grey.shade200,
        child: Icon(
          Icons.smart_toy,
          color: bot.isOnline ? Colors.green : Colors.grey,
          size: size * 0.52,
        ),
      );
    }
    return ClipOval(
      child: Image.network(
        _avatarUrl(avatar),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => CircleAvatar(
          radius: size / 2,
          backgroundColor: Colors.orange.shade100,
          child: Icon(
            Icons.broken_image_outlined,
            color: Colors.orange.shade700,
          ),
        ),
      ),
    );
  }

  String _avatarUrl(String avatar) {
    if (avatar.startsWith('http://') ||
        avatar.startsWith('https://') ||
        avatar.startsWith('/')) {
      return avatar;
    }
    return '/$avatar';
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermCard() {
    final bot = _botInfo;
    if (bot == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('权限', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                _permChip('通知', bot.canNotify == 1, 'notify'),
                const SizedBox(width: 8),
                _permChip('HTTP', bot.canHttp == 1, 'http'),
              ],
            ),
            if (_permRequests.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Text(
                '申请记录',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 4),
              ..._permRequests.map(
                (r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(
                        r.status == 1
                            ? Icons.check_circle
                            : (r.status == 2 ? Icons.cancel : Icons.schedule),
                        size: 14,
                        color: r.status == 1
                            ? Colors.green
                            : (r.status == 2 ? Colors.red : Colors.orange),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${r.permType} - ${r.statusText}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (r.adminReply != null && r.adminReply!.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Text(
                          '(回复: ${r.adminReply})',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _permChip(String label, bool granted, String permType) {
    return ActionChip(
      avatar: Icon(
        granted ? Icons.check_circle : Icons.cancel,
        size: 16,
        color: granted ? Colors.green : Colors.grey,
      ),
      label: Text('$label${granted ? ' (已授权)' : ' (未授权)'}'),
      onPressed: granted ? null : () => _requestPerm(permType, label),
    );
  }

  Future<void> _requestPerm(String permType, String label) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('申请$label权限'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(labelText: '申请理由'),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('提交'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final state = context.read<AppState>();
    final result = await state.permService.request(
      botId: widget.botId,
      permType: permType,
      reason: reasonCtrl.text.trim(),
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result['message'] ?? '申请失败')));
    }
  }

  Widget _buildScriptsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('脚本', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            FilledButton.tonal(
              onPressed: _createScript,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 18),
                  SizedBox(width: 4),
                  Text('新建脚本'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_scripts.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('暂无脚本')),
            ),
          )
        else
          ..._scripts.map((s) => _scriptCard(s)),
        const SizedBox(height: 16),
        // 日志入口
        FilledButton.tonalIcon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    LogPage(botId: widget.botId, botName: widget.botName),
              ),
            );
          },
          icon: const Icon(Icons.article, size: 18),
          label: const Text('查看日志'),
        ),
      ],
    );
  }

  Widget _scriptCard(ScriptInfo script) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          script.isEnabled ? Icons.play_circle : Icons.pause_circle,
          color: script.isEnabled ? Colors.green : Colors.grey,
        ),
        title: Text(script.scriptName),
        subtitle: Text('v${script.version}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: script.isEnabled,
              onChanged: (v) => _toggleScript(script, v),
            ),
            IconButton(
              icon: const Icon(Icons.delete, size: 20),
              onPressed: () => _deleteScript(script),
            ),
          ],
        ),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ScriptEditorPage(
                scriptId: script.scriptId,
                scriptName: script.scriptName,
              ),
            ),
          );
          _loadData();
        },
      ),
    );
  }

  Future<void> _toggleScript(ScriptInfo script, bool enabled) async {
    final state = context.read<AppState>();
    await state.scriptService.toggle(script.scriptId, enabled ? 1 : 0);
    _loadData();
  }

  Future<void> _createScript() async {
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建脚本'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: '脚本名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return;
    final state = context.read<AppState>();
    final result = await state.scriptService.create(
      botId: widget.botId,
      scriptName: nameCtrl.text.trim(),
    );
    if (mounted) {
      if (result['success'] == true) {
        _loadData();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result['message'] ?? '创建失败')));
      }
    }
  }

  Future<void> _deleteScript(ScriptInfo script) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除脚本 "${script.scriptName}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final state = context.read<AppState>();
    await state.scriptService.delete(script.scriptId);
    _loadData();
  }

  Future<void> _setAvatar() async {
    final bot = _botInfo;
    if (bot == null) return;
    bool uploading = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('设置 Bot 头像'),
          content: Text(
            uploading
                ? '头像上传中，请稍候...'
                : '选择本地图片上传为 Bot 头像。支持 png、jpg、gif、webp，最大 5MB。',
          ),
          actions: [
            TextButton(
              onPressed: uploading ? null : () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            if (bot.botAvatar.isNotEmpty)
              TextButton(
                onPressed: uploading
                    ? null
                    : () async {
                        setDialogState(() => uploading = true);
                        final state = context.read<AppState>();
                        final update = await state.botService.update(
                          botId: widget.botId,
                          botAvatar: '',
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        await _handleAvatarUpdate(update, state);
                      },
                child: const Text('清空头像'),
              ),
            FilledButton(
              onPressed: uploading
                  ? null
                  : () async {
                      final picked = await _pickAvatarImage();
                      if (picked == null) return;
                      setDialogState(() => uploading = true);
                      final state = context.read<AppState>();
                      final update = await state.botService.uploadAvatar(
                        botId: widget.botId,
                        filename: picked.name,
                        bytes: picked.bytes,
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      await _handleAvatarUpdate(update, state);
                    },
              child: Text(uploading ? '上传中...' : '选择图片'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAvatarUpdate(
    Map<String, dynamic> update,
    AppState state,
  ) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          update['message'] ?? (update['success'] == true ? '头像已更新' : '头像更新失败'),
        ),
      ),
    );
    if (update['success'] == true) {
      await _loadData();
      state.refreshBots();
    }
  }

  Future<_PickedAvatar?> _pickAvatarImage() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('头像不能超过5MB')));
      }
      return null;
    }
    return _PickedAvatar(picked.name, bytes);
  }

  Future<void> _resetToken() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置Token'),
        content: const Text('重置后旧Token将立即失效，确定继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认重置'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final state = context.read<AppState>();
    final result = await state.botService.resetToken(widget.botId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['success'] == true
                ? '新Token: ${result['bot_token']}'
                : (result['message'] ?? '重置失败'),
          ),
        ),
      );
      _loadData();
    }
  }

  Future<void> _deleteBot() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除Bot'),
        content: Text('确定要删除 "${widget.botName}" 吗？此操作不可恢复！'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final state = context.read<AppState>();
    final result = await state.botService.delete(widget.botId);
    if (mounted) {
      if (result['success'] == true) {
        Navigator.pop(context);
        state.refreshBots();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result['message'] ?? '删除失败')));
      }
    }
  }
}

class _PickedAvatar {
  final String name;
  final Uint8List bytes;

  const _PickedAvatar(this.name, this.bytes);
}
