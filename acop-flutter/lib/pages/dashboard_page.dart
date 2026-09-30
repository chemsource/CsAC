import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/models.dart';
import 'admin_page.dart';
import 'api_ref_page.dart';
import 'bot_detail_page.dart';

enum _BotFilter { all, online, offline, disabled }

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  int _section = 0;
  _BotFilter _filter = _BotFilter.all;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<BotInfo> _filteredBots(List<BotInfo> bots) {
    final q = _searchCtrl.text.trim().toLowerCase();
    return bots.where((bot) {
      final matchesQuery =
          q.isEmpty ||
          bot.botName.toLowerCase().contains(q) ||
          bot.botDesc.toLowerCase().contains(q) ||
          bot.uid.toString().contains(q) ||
          bot.botId.toString().contains(q);
      final matchesFilter = switch (_filter) {
        _BotFilter.all => true,
        _BotFilter.online => bot.isOnline,
        _BotFilter.offline => !bot.isOnline,
        _BotFilter.disabled => !bot.isActive,
      };
      return matchesQuery && matchesFilter;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final dev = state.devInfo;
    final filteredBots = _filteredBots(state.bots);
    final onlineCount = state.bots.where((b) => b.isOnline).length;
    final activeCount = state.bots.where((b) => b.isActive).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('CsAC Open Platform'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => state.refreshBots(),
            tooltip: '刷新',
          ),
          IconButton(
            icon: const Icon(Icons.menu_book_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ApiRefPage()),
            ),
            tooltip: 'API 参考',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle_rounded),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'admin', child: Text('管理员面板')),
              PopupMenuItem(value: 'profile', child: Text('开发者信息')),
              PopupMenuItem(value: 'logout', child: Text('退出登录')),
            ],
            onSelected: (value) {
              if (value == 'logout') {
                state.logout();
              } else if (value == 'profile') {
                _showProfileDialog(context, dev);
              } else if (value == 'admin') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminPage()),
                );
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1024;
          final content = RefreshIndicator(
            onRefresh: state.refreshBots,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
              children: [
                _PlatformHeader(
                  dev: dev,
                  totalBots: state.bots.length,
                  activeBots: activeCount,
                  onlineBots: onlineCount,
                  onCreate: () => _showCreateBotDialog(context),
                  onProfile: () => _showProfileDialog(context, dev),
                ),
                const SizedBox(height: 18),
                _SectionTabs(
                  section: _section,
                  onChanged: (value) => setState(() => _section = value),
                ),
                const SizedBox(height: 16),
                if (_section == 0)
                  _OverviewSection(
                    bots: filteredBots,
                    onCreate: () => _showCreateBotDialog(context),
                    onOpenApi: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ApiRefPage()),
                    ),
                    onOpenBot: (bot) => _openBot(context, bot),
                  )
                else
                  _ManageSection(
                    searchCtrl: _searchCtrl,
                    filter: _filter,
                    onSearchChanged: () => setState(() {}),
                    onFilterChanged: (value) => setState(() => _filter = value),
                    bots: filteredBots,
                    onCreate: () => _showCreateBotDialog(context),
                    onOpenBot: (bot) => _openBot(context, bot),
                  ),
              ],
            ),
          );

          if (!wide) {
            return content;
          }

          return Row(
            children: [
              _Sidebar(
                section: _section,
                onSectionChanged: (value) => setState(() => _section = value),
                onRefresh: () => state.refreshBots(),
                onOpenApi: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ApiRefPage()),
                ),
                onCreateBot: () => _showCreateBotDialog(context),
                onProfile: () => _showProfileDialog(context, dev),
                onLogout: () => state.logout(),
                onOpenAdmin: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminPage()),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: content),
            ],
          );
        },
      ),
    );
  }

  void _openBot(BuildContext context, BotInfo bot) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BotDetailPage(botId: bot.botId, botName: bot.botName),
      ),
    );
  }

  void _showCreateBotDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('创建 Bot'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Bot 名称 *',
                  hintText: '例如：群公告助手',
                  prefixIcon: Icon(Icons.smart_toy_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Bot 描述',
                  hintText: '写一句它负责做什么，方便团队识别',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '创建后会自动生成 Bot UID 和 Token，可在详情页管理脚本与权限。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('请先填写 Bot 名称')));
                return;
              }
              Navigator.pop(dialogContext);
              final state = context.read<AppState>();
              final result = await state.botService.create(
                botName: name,
                botDesc: descCtrl.text.trim(),
              );
              if (!context.mounted) return;
              if (result['success'] == true) {
                final token = result['data']?['bot_token']?.toString() ?? '';
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      token.isEmpty ? 'Bot 创建成功' : 'Bot 创建成功，Token 已生成',
                    ),
                    action: token.isEmpty
                        ? null
                        : SnackBarAction(
                            label: '复制 Token',
                            onPressed: () =>
                                Clipboard.setData(ClipboardData(text: token)),
                          ),
                  ),
                );
                await state.refreshBots();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(result['message']?.toString() ?? '创建失败'),
                  ),
                );
              }
            },
            icon: const Icon(Icons.add_rounded),
            label: const Text('创建'),
          ),
        ],
      ),
    );
  }

  void _showProfileDialog(BuildContext context, DevInfo? dev) {
    if (dev == null) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('开发者信息'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ProfileRow(label: 'ID', value: '${dev.devId}'),
              _ProfileRow(label: '名称', value: dev.devName),
              _ProfileRow(label: '邮箱', value: dev.email),
              _ProfileRow(label: 'API Key', value: dev.apiKey, monospace: true),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: dev.apiKey));
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('API Key 已复制')));
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('复制 API Key'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

class _PlatformHeader extends StatelessWidget {
  const _PlatformHeader({
    required this.dev,
    required this.totalBots,
    required this.activeBots,
    required this.onlineBots,
    required this.onCreate,
    required this.onProfile,
  });

  final DevInfo? dev;
  final int totalBots;
  final int activeBots;
  final int onlineBots;
  final VoidCallback onCreate;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final name = dev?.devName.trim().isNotEmpty == true ? dev!.devName : '开发者';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 720;
            final intro = Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.apps_rounded, color: colorScheme.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '开放平台控制台',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$name，你可以在这里管理 Bot、脚本、权限和运行数据。',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
            final stats = Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _HeaderStat(label: '总 Bot', value: '$totalBots'),
                _HeaderStat(label: '正常', value: '$activeBots'),
                _HeaderStat(label: '在线', value: '$onlineBots'),
              ],
            );
            final actions = Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('创建 Bot'),
                ),
                OutlinedButton.icon(
                  onPressed: onProfile,
                  icon: const Icon(Icons.badge_rounded),
                  label: const Text('开发者信息'),
                ),
              ],
            );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  intro,
                  const SizedBox(height: 16),
                  stats,
                  const SizedBox(height: 16),
                  actions,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: intro),
                const SizedBox(width: 20),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [stats, const SizedBox(height: 14), actions],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.section,
    required this.onSectionChanged,
    required this.onRefresh,
    required this.onOpenApi,
    required this.onCreateBot,
    required this.onProfile,
    required this.onLogout,
    required this.onOpenAdmin,
  });

  final int section;
  final ValueChanged<int> onSectionChanged;
  final VoidCallback onRefresh;
  final VoidCallback onOpenApi;
  final VoidCallback onCreateBot;
  final VoidCallback onProfile;
  final VoidCallback onLogout;
  final VoidCallback onOpenAdmin;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 248,
      color: Colors.white,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BrandBlock(onCreateBot: onCreateBot),
          const SizedBox(height: 18),
          _NavItem(
            icon: Icons.dashboard_rounded,
            label: '概览',
            selected: section == 0,
            onTap: () => onSectionChanged(0),
          ),
          _NavItem(
            icon: Icons.smart_toy_rounded,
            label: 'Bot 管理',
            selected: section == 1,
            onTap: () => onSectionChanged(1),
          ),
          const Divider(height: 28),
          _SideAction(
            icon: Icons.refresh_rounded,
            label: '刷新 Bot',
            onTap: onRefresh,
          ),
          _SideAction(
            icon: Icons.menu_book_rounded,
            label: 'API 参考',
            onTap: onOpenApi,
          ),
          _SideAction(
            icon: Icons.badge_rounded,
            label: '开发者信息',
            onTap: onProfile,
          ),
          _SideAction(
            icon: Icons.admin_panel_settings_rounded,
            label: '管理员面板',
            onTap: onOpenAdmin,
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: onCreateBot,
            icon: const Icon(Icons.add_rounded),
            label: const Text('创建 Bot'),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: onLogout,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('退出登录'),
          ),
        ],
      ),
    );
  }
}

class _BrandBlock extends StatelessWidget {
  const _BrandBlock({required this.onCreateBot});

  final VoidCallback onCreateBot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.smart_toy_rounded, color: Colors.white),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'ACOP',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '开放平台控制台',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: onCreateBot,
            icon: const Icon(Icons.add_rounded),
            label: const Text('新建 Bot'),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        selected: selected,
        selectedTileColor: Theme.of(
          context,
        ).colorScheme.primary.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(
          icon,
          color: selected ? Theme.of(context).colorScheme.primary : null,
        ),
        title: Text(label),
        onTap: onTap,
      ),
    );
  }
}

class _SideAction extends StatelessWidget {
  const _SideAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _SectionTabs extends StatelessWidget {
  const _SectionTabs({required this.section, required this.onChanged});

  final int section;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        ChoiceChip(
          label: const Text('概览'),
          selected: section == 0,
          onSelected: (_) => onChanged(0),
        ),
        ChoiceChip(
          label: const Text('Bot 管理'),
          selected: section == 1,
          onSelected: (_) => onChanged(1),
        ),
      ],
    );
  }
}

class _OverviewSection extends StatelessWidget {
  const _OverviewSection({
    required this.bots,
    required this.onCreate,
    required this.onOpenApi,
    required this.onOpenBot,
  });

  final List<BotInfo> bots;
  final VoidCallback onCreate;
  final VoidCallback onOpenApi;
  final ValueChanged<BotInfo> onOpenBot;

  @override
  Widget build(BuildContext context) {
    final total = bots.length;
    final online = bots.where((b) => b.isOnline).length;
    final active = bots.where((b) => b.isActive).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.count(
          crossAxisCount: MediaQuery.of(context).size.width >= 960 ? 3 : 1,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 3.2,
          children: [
            _MetricCard(
              label: '总 Bot',
              value: '$total',
              icon: Icons.smart_toy_rounded,
            ),
            _MetricCard(
              label: '正常 Bot',
              value: '$active',
              icon: Icons.verified_rounded,
            ),
            _MetricCard(
              label: '在线 Bot',
              value: '$online',
              icon: Icons.wifi_rounded,
            ),
          ],
        ),
        const SizedBox(height: 18),
        _QuickActions(onCreate: onCreate, onOpenApi: onOpenApi, onOpenLibs: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LibManagePage()))),
        const SizedBox(height: 18),
        _SimpleSection(
          title: '最近 Bot',
          subtitle: '快速查看最近创建或更新的机器人',
          child: bots.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('暂无 Bot')),
                )
              : Column(
                  children: bots
                      .take(5)
                      .map(
                        (bot) =>
                            _BotListCard(bot: bot, onTap: () => onOpenBot(bot)),
                      )
                      .toList(),
                ),
        ),
      ],
    );
  }
}

class _ManageSection extends StatelessWidget {
  const _ManageSection({
    required this.searchCtrl,
    required this.filter,
    required this.onSearchChanged,
    required this.onFilterChanged,
    required this.bots,
    required this.onCreate,
    required this.onOpenBot,
  });

  final TextEditingController searchCtrl;
  final _BotFilter filter;
  final VoidCallback onSearchChanged;
  final ValueChanged<_BotFilter> onFilterChanged;
  final List<BotInfo> bots;
  final VoidCallback onCreate;
  final ValueChanged<BotInfo> onOpenBot;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SimpleSection(
          title: 'Bot 管理',
          subtitle: '搜索、筛选和打开 Bot 详情',
          trailing: FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded),
            label: const Text('创建 Bot'),
          ),
          child: Column(
            children: [
              TextField(
                controller: searchCtrl,
                onChanged: (_) => onSearchChanged(),
                decoration: InputDecoration(
                  hintText: '搜索 Bot 名称、描述、UID 或 ID',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: searchCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            searchCtrl.clear();
                            onSearchChanged();
                          },
                          icon: const Icon(Icons.clear_rounded),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _FilterChip(
                    label: '全部',
                    selected: filter == _BotFilter.all,
                    onTap: () => onFilterChanged(_BotFilter.all),
                  ),
                  _FilterChip(
                    label: '在线',
                    selected: filter == _BotFilter.online,
                    onTap: () => onFilterChanged(_BotFilter.online),
                  ),
                  _FilterChip(
                    label: '离线',
                    selected: filter == _BotFilter.offline,
                    onTap: () => onFilterChanged(_BotFilter.offline),
                  ),
                  _FilterChip(
                    label: '已禁用',
                    selected: filter == _BotFilter.disabled,
                    onTap: () => onFilterChanged(_BotFilter.disabled),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (bots.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: Text('没有匹配的 Bot')),
                )
              else
                Column(
                  children: bots
                      .map(
                        (bot) =>
                            _BotListCard(bot: bot, onTap: () => onOpenBot(bot)),
                      )
                      .toList(),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onCreate, required this.onOpenApi, required this.onOpenLibs});

  final VoidCallback onCreate;
  final VoidCallback onOpenApi;
  final VoidCallback onOpenLibs;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _ActionCard(
          icon: Icons.add_rounded,
          title: '新建 Bot',
          subtitle: '创建一个新的机器人账号',
          onTap: onCreate,
        ),
        _ActionCard(
          icon: Icons.menu_book_rounded,
          title: 'API 参考',
          subtitle: '查看常用接口与字段说明',
          onTap: onOpenApi,
        ),
        _ActionCard(
          icon: Icons.library_books_rounded,
          title: 'JSLibs 库管理',
          subtitle: '上传和管理 AJL 库文件',
          onTap: onOpenLibs,
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SimpleSection extends StatelessWidget {
  const _SimpleSection({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: selected,
      label: Text(label),
      onSelected: (_) => onTap(),
    );
  }
}

class _BotListCard extends StatelessWidget {
  const _BotListCard({required this.bot, required this.onTap});

  final BotInfo bot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _BotAvatar(bot: bot, size: 48),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              bot.botName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _StatusTag(
                            text: bot.isOnline ? '在线' : '离线',
                            color: bot.isOnline
                                ? const Color(0xFF16A34A)
                                : const Color(0xFF64748B),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        bot.botDesc.isEmpty ? '暂无描述' : bot.botDesc,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _MiniTag(text: 'UID ${bot.uid}'),
                          _MiniTag(text: bot.canNotify == 1 ? '通知已开' : '通知未开'),
                          _MiniTag(
                            text: bot.canHttp == 1 ? 'HTTP 已开' : 'HTTP 未开',
                          ),
                          if (!bot.isActive) const _MiniTag(text: '已禁用'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BotAvatar extends StatelessWidget {
  const _BotAvatar({required this.bot, required this.size});

  final BotInfo bot;
  final double size;

  @override
  Widget build(BuildContext context) {
    final avatar = bot.botAvatar.trim();
    if (avatar.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(
          _avatarUrl(avatar),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _fallback(context),
        ),
      );
    }
    return _fallback(context);
  }

  Widget _fallback(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(Icons.smart_toy_rounded, color: colorScheme.primary),
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
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.label,
    required this.value,
    this.monospace = false,
  });

  final String label;
  final String value;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(fontFamily: monospace ? 'monospace' : null),
            ),
          ),
        ],
      ),
    );
  }
}

// v2.2.1: JSLibs 库管理页面
class LibManagePage extends StatefulWidget {
  const LibManagePage({super.key});

  @override
  State<LibManagePage> createState() => _LibManagePageState();
}

class _LibManagePageState extends State<LibManagePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> myLibs = [];
  List<Map<String, dynamic>> publicLibs = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    loadLibs();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> loadLibs() async {
    setState(() { loading = true; });
    final state = context.read<AppState>();
    try {
      final results = await Future.wait([
        state.libService.myLibs(),
        state.libService.list(),
      ]);
      if (!mounted) return;
      setState(() {
        myLibs = (results[0]['libs'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        publicLibs = (results[1]['libs'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { loading = false; });
    }
  }

  Future<void> uploadLib() async {
    final nameCtrl = TextEditingController();
    final versionCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('上传 AJL 库'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '库名 *', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: versionCtrl, decoration: const InputDecoration(labelText: '版本号 *', hintText: '1.0.0', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: descCtrl, maxLines: 2, decoration: const InputDecoration(labelText: '描述', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: contentCtrl, maxLines: 8, decoration: const InputDecoration(labelText: 'JavaScript 代码 *', border: OutlineInputBorder())),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('上传')),
        ],
      ),
    );
    nameCtrl.dispose(); versionCtrl.dispose(); contentCtrl.dispose(); descCtrl.dispose();
    if (result != true) return;
    final state = context.read<AppState>();
    final resp = await state.libService.upload(
      name: nameCtrl.text.trim(),
      version: versionCtrl.text.trim(),
      content: contentCtrl.text,
      description: descCtrl.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(resp['success'] == true ? '上传成功，等待审核' : (resp['message'] ?? '上传失败'))),
    );
    loadLibs();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('JSLibs 库管理'),
        bottom: TabBar(controller: _tabController, tabs: const [
          Tab(text: '我的库', icon: Icon(Icons.person_rounded)),
          Tab(text: '公共库', icon: Icon(Icons.public_rounded)),
        ]),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: uploadLib,
        icon: const Icon(Icons.upload_rounded),
        label: const Text('上传库'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(controller: _tabController, children: [
              _LibList(libs: myLibs, emptyText: '暂无上传的库', isOwner: true, onRefresh: loadLibs),
              _LibList(libs: publicLibs, emptyText: '暂无公共库', isOwner: false, onRefresh: loadLibs),
            ]),
    );
  }
}

class _LibList extends StatelessWidget {
  const _LibList({required this.libs, required this.emptyText, required this.isOwner, required this.onRefresh});
  final List<Map<String, dynamic>> libs;
  final String emptyText;
  final bool isOwner;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    if (libs.isEmpty) {
      return Center(child: Text(emptyText));
    }
    return ListView.builder(
      itemCount: libs.length,
      itemBuilder: (context, index) {
        final lib = libs[index];
        final name = lib['name'] ?? '';
        final version = lib['version'] ?? '';
        final desc = lib['description'] ?? '';
        final status = lib['status'] ?? 0;
        final statusText = status == 1 ? '已通过' : status == 2 ? '已拒绝' : '待审核';
        final statusColor = status == 1 ? Colors.green : status == 2 ? Colors.red : Colors.orange;
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            leading: const Icon(Icons.library_books_rounded),
            title: Text('$name v$version'),
            subtitle: desc.isNotEmpty ? Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis) : null,
            trailing: isOwner
                ? Chip(label: Text(statusText, style: TextStyle(color: statusColor, fontSize: 12)), visualDensity: VisualDensity.compact)
                : null,
          ),
        );
      },
    );
  }
}
