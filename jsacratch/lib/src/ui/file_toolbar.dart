import 'package:flutter/material.dart';

import '../l10n.dart';

class FileToolbar extends StatelessWidget {
  const FileToolbar({
    required this.projectName,
    required this.editMode,
    required this.scriptType,
    required this.hasScripts,
    required this.isLoggedIn,
    required this.botName,
    this.onNewScript,
    this.onExportAcr,
    this.onExportAcrg,
    this.onUpload,
    this.onToggleMode,
    this.onToggleScriptType,
    this.onRename,
    this.onLogin,
    this.onLogout,
    this.onSelectBot,
    this.onManageScripts,
    this.onSaveProject,
    this.onSaveScript,
    this.onOpen,
    this.onPreview,
    this.previewRunning = false,
    this.onBrowseLibs,
    super.key,
  });

  final String projectName;
  final String editMode;
  final String scriptType;
  final bool hasScripts;
  final bool isLoggedIn;
  final String botName;
  final VoidCallback? onNewScript;
  final VoidCallback? onExportAcr;
  final VoidCallback? onExportAcrg;
  final VoidCallback? onUpload;
  final VoidCallback? onToggleMode;
  final VoidCallback? onToggleScriptType;
  final ValueChanged<String>? onRename;
  final VoidCallback? onLogin;
  final VoidCallback? onLogout;
  final VoidCallback? onSelectBot;
  final VoidCallback? onManageScripts;
  final VoidCallback? onSaveProject;
  final VoidCallback? onSaveScript;
  final VoidCallback? onOpen;
  final VoidCallback? onPreview;
  final bool previewRunning;
  final VoidCallback? onBrowseLibs;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = JsacratchStrings.of(context);

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          // File operations
          _ToolButton(icon: Icons.folder_open, tooltip: s.text('open_file'), onTap: onOpen),
          _ToolButton(icon: Icons.save, tooltip: s.text('save_project'), onTap: onSaveProject),
          if (scriptType != 'acr' && scriptType != 'miniapp')
            _ToolButton(icon: Icons.save_outlined, tooltip: s.text('save_script'), onTap: onSaveScript),
          const SizedBox(width: 4),

          if (scriptType != 'acr' && scriptType != 'miniapp')
            IconButton(
              icon: Icon(editMode == 'acratch' ? Icons.grid_view : Icons.code, size: 20),
              tooltip: editMode == 'acratch' ? s.text('switch_to_js') : s.text('switch_to_acratch'),
              onPressed: onToggleMode,
            ),
          if (onRename != null)
            Expanded(
              child: GestureDetector(
                onTap: () => _showRenameDialog(context, onRename!, s),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        projectName,
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: cs.onSurface),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.edit, size: 14, color: cs.onSurfaceVariant),
                  ],
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(projectName, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: cs.onSurface)),
            ),
          const Spacer(),

          // Script type chip
          ActionChip(
            avatar: Icon(
              scriptType == 'acr' ? Icons.javascript : scriptType == 'miniapp' ? Icons.widgets : Icons.smart_toy,
              size: 16,
              color: cs.primary,
            ),
            label: Text(
              scriptType == 'acr' ? s.text('script_type_acr') : scriptType == 'miniapp' ? s.text('script_type_miniapp') : s.text('script_type_bot'),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.primary),
            ),
            tooltip: s.text('switch_script_type'),
            onPressed: onToggleScriptType,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 4),
          ),

          const SizedBox(width: 4),

          // Bot selector / login (BotJS mode) or login only (ACR/MiniApp mode)
          if (scriptType == 'miniapp') ...[
            if (isLoggedIn)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.cloud_done, size: 16, color: cs.primary),
                const SizedBox(width: 4),
                Text(s.text('logged_in'), style: TextStyle(fontSize: 11, color: cs.primary)),
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(Icons.logout, size: 16, color: cs.onSurfaceVariant),
                  tooltip: s.text('logout'),
                  onPressed: onLogout,
                  splashRadius: 12,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ])
            else
              ActionChip(
                avatar: const Icon(Icons.login, size: 16),
                label: Text(s.text('login'), style: const TextStyle(fontSize: 11)),
                onPressed: onLogin,
                visualDensity: VisualDensity.compact,
              ),
            const SizedBox(width: 4),
          ] else if (scriptType != 'acr') ...[
            if (isLoggedIn)
              _BotChip(botName: botName, onTap: onSelectBot, onLogout: onLogout, s: s, onManage: onManageScripts)
            else
              ActionChip(
                avatar: const Icon(Icons.login, size: 16),
                label: Text(s.text('login'), style: const TextStyle(fontSize: 11)),
                onPressed: onLogin,
                visualDensity: VisualDensity.compact,
              ),
            const SizedBox(width: 4),
          ] else ...[
            // ACR mode: login / logout
            if (isLoggedIn)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.cloud_done, size: 16, color: cs.primary),
                const SizedBox(width: 4),
                Text(s.text('logged_in'), style: TextStyle(fontSize: 11, color: cs.primary)),
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(Icons.logout, size: 16, color: cs.onSurfaceVariant),
                  tooltip: s.text('logout'),
                  onPressed: onLogout,
                  splashRadius: 12,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ])
            else
              ActionChip(
                avatar: const Icon(Icons.login, size: 16),
                label: Text(s.text('login'), style: const TextStyle(fontSize: 11)),
                onPressed: onLogin,
                visualDensity: VisualDensity.compact,
              ),
            const SizedBox(width: 4),
          ],

          const SizedBox(width: 4),
          _ToolButton(icon: Icons.add, tooltip: s.text('new_script'), onTap: onNewScript),
          if (hasScripts && scriptType == 'acr') ...[
            _ToolButton(icon: Icons.description, tooltip: s.text('export_acr'), onTap: onExportAcr),
            _ToolButton(icon: Icons.folder, tooltip: s.text('export_acrg'), onTap: onExportAcrg),
          ],
          if (scriptType == 'script')
            _ToolButton(icon: Icons.library_books, tooltip: 'AJL 签名库', onTap: onBrowseLibs),
          if (scriptType == 'miniapp')
            _ToolButton(
              icon: previewRunning ? Icons.stop : Icons.play_arrow,
              tooltip: previewRunning ? '停止预览' : '预览小程序',
              onTap: onPreview,
            ),
          _ToolButton(icon: Icons.cloud_upload, tooltip: s.text('upload'), onTap: onUpload),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context, ValueChanged<String> onRename, JsacratchStrings s) {
    final controller = TextEditingController(text: projectName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.text('rename_project')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: s.text('project_name')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.text('cancel'))),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) onRename(controller.text.trim());
              Navigator.pop(ctx);
            },
            child: Text(s.text('ok')),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.tooltip, this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      onPressed: onTap,
      splashRadius: 18,
    );
  }
}

class _BotChip extends StatelessWidget {
  const _BotChip({required this.botName, this.onTap, this.onLogout, this.onManage, required this.s});
  final String botName;
  final VoidCallback? onTap;
  final VoidCallback? onLogout;
  final VoidCallback? onManage;
  final JsacratchStrings s;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (botName.isNotEmpty && onManage != null)
          IconButton(
            icon: const Icon(Icons.cloud, size: 16),
            tooltip: 'Scripts',
            onPressed: onManage,
            splashRadius: 12,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ActionChip(
          avatar: const Icon(Icons.smart_toy, size: 16),
          label: Text(
            botName.isEmpty ? s.text('no_bot_selected') : botName,
            style: TextStyle(fontSize: 11, color: botName.isEmpty ? cs.error : cs.primary),
          ),
          onPressed: onTap,
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          icon: Icon(Icons.logout, size: 16, color: cs.onSurfaceVariant),
          tooltip: s.text('logout'),
          onPressed: onLogout,
          splashRadius: 12,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
      ],
    );
  }
}
