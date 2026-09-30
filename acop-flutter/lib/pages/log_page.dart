import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models/models.dart';

class LogPage extends StatefulWidget {
  final int botId;
  final String botName;
  const LogPage({super.key, required this.botId, required this.botName});

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  List<LogEntry> _logs = [];
  bool _loading = true;
  String _levelFilter = '';

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _loading = true);
    final state = context.read<AppState>();
    final result = await state.logService.list(
      botId: widget.botId,
      level: _levelFilter.isEmpty ? null : _levelFilter,
      limit: 100,
    );
    if (result['success'] == true && result['data'] != null) {
      final list = result['data'] as List;
      _logs = list.map((e) => LogEntry.fromJson(e as Map<String, dynamic>)).toList();
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.botName} - 日志'),
        actions: [
          PopupMenuButton<String>(
            itemBuilder: (_) => [
              const PopupMenuItem(value: '', child: Text('全部')),
              const PopupMenuItem(value: 'log', child: Text('Log')),
              const PopupMenuItem(value: 'error', child: Text('Error')),
              const PopupMenuItem(value: 'warn', child: Text('Warn')),
            ],
            onSelected: (v) {
              _levelFilter = v;
              _loadLogs();
            },
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadLogs),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _logs.isEmpty
              ? const Center(child: Text('暂无日志'))
              : ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (_, i) {
                    final log = _logs[i];
                    return _logTile(log);
                  },
                ),
    );
  }

  Widget _logTile(LogEntry log) {
    Color color;
    IconData icon;
    switch (log.level) {
      case 'error':
        color = Colors.red;
        icon = Icons.error;
        break;
      case 'warn':
        color = Colors.orange;
        icon = Icons.warning;
        break;
      default:
        color = Colors.blue;
        icon = Icons.info;
    }

    final time = DateTime.fromMillisecondsSinceEpoch(log.createdAt * 1000);
    final timeStr = '${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';

    return ListTile(
      dense: true,
      leading: Icon(icon, color: color, size: 18),
      title: Text(
        log.content,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: log.level == 'error' ? Colors.red : null,
          fontFamily: 'monospace',
          fontSize: 13,
        ),
      ),
      subtitle: Text(
        '$timeStr${log.scriptId > 0 ? '  Script#${log.scriptId}' : ''}',
        style: const TextStyle(fontSize: 11),
      ),
    );
  }
}
