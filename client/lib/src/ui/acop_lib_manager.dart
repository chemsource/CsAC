import 'package:flutter/material.dart';

import '../acop_client.dart';

/// JSLibs 库管理页面
class AcopLibManagerPage extends StatefulWidget {
  const AcopLibManagerPage({super.key, required this.apiClient});

  final AcopApiClient apiClient;

  @override
  State<AcopLibManagerPage> createState() => _AcopLibManagerPageState();
}

class _AcopLibManagerPageState extends State<AcopLibManagerPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<AcopLibUpload> myLibs = [];
  List<AcopLibUpload> publicLibs = [];
  bool loading = true;
  String? error;

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
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final results = await Future.wait([
        widget.apiClient.getMyLibs(),
        widget.apiClient.getLibList(),
      ]);
      if (!mounted) return;
      setState(() {
        myLibs = results[0];
        publicLibs = results[1];
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = e.toString();
      });
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
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '库名 *', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: versionCtrl,
                decoration: const InputDecoration(labelText: '版本号 *', hintText: '1.0.0', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descCtrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '描述', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: contentCtrl,
                maxLines: 8,
                decoration: const InputDecoration(labelText: 'JavaScript 代码 *', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('上传')),
        ],
      ),
    );
    nameCtrl.dispose();
    versionCtrl.dispose();
    contentCtrl.dispose();
    descCtrl.dispose();
    if (result != true) return;
    try {
      final resp = await widget.apiClient.uploadLib(
        name: nameCtrl.text.trim(),
        version: versionCtrl.text.trim(),
        content: contentCtrl.text,
        description: descCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            resp['success'] == true ? '上传成功，等待审核' : (resp['message'] ?? '上传失败'),
          ),
        ),
      );
      loadLibs();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('上传失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('JSLibs 库管理'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '我的库', icon: Icon(Icons.person_outlined)),
            Tab(text: '公共库', icon: Icon(Icons.public_outlined)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: uploadLib,
        icon: const Icon(Icons.upload),
        label: const Text('上传库'),
      ),
      body: Builder(
        builder: (context) {
          if (loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (error != null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 8),
                  Text(error!, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  FilledButton(onPressed: loadLibs, child: const Text('重试')),
                ],
              ),
            );
          }
          return TabBarView(
            controller: _tabController,
            children: [
              _LibList(libs: myLibs, emptyText: '暂无上传的库', isOwner: true),
              _LibList(libs: publicLibs, emptyText: '暂无公共库', isOwner: false),
            ],
          );
        },
      ),
    );
  }
}

class _LibList extends StatelessWidget {
  const _LibList({required this.libs, required this.emptyText, required this.isOwner});

  final List<AcopLibUpload> libs;
  final String emptyText;
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    if (libs.isEmpty) {
      return Center(
        child: Text(emptyText, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }
    return ListView.builder(
      itemCount: libs.length,
      itemBuilder: (context, index) {
        final lib = libs[index];
        final cs = Theme.of(context).colorScheme;
        final statusColor = lib.status == 1 ? Colors.green : lib.status == 2 ? Colors.red : Colors.orange;
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            leading: const Icon(Icons.library_books),
            title: Text('${lib.name} v${lib.version}'),
            subtitle: lib.description.isNotEmpty
                ? Text(lib.description, maxLines: 2, overflow: TextOverflow.ellipsis)
                : null,
            trailing: isOwner
                ? Chip(
                    label: Text(lib.statusText, style: TextStyle(color: statusColor, fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(color: statusColor.withValues(alpha: 0.5)),
                  )
                : null,
          ),
        );
      },
    );
  }
}
