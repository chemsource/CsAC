part of '../../main.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.state});

  final CsacAppState state;

  @override
  Widget build(BuildContext context) {
    final user = state.user;
    final counts = state.notificationCounts;
    final strings = context.strings;
    final colors = Theme.of(context).colorScheme;

    List<Widget> separatedTiles(List<Widget> tiles) {
      return [
        for (var i = 0; i < tiles.length; i++) ...[
          tiles[i],
          if (i != tiles.length - 1) const Divider(height: 1),
        ],
      ];
    }

    Widget actionTile({
      required IconData icon,
      required String title,
      required VoidCallback? onTap,
      Color? color,
    }) {
      return ListTile(
        enabled: onTap != null,
        leading: Icon(icon, color: color),
        title: Text(
          title,
          style: color == null ? null : TextStyle(color: color),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(strings.text('Me'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            if (state.sessionExpired)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: MaterialBanner(
                  content: Text(
                    strings.text(
                      'Session expired. Log in again to sync latest data.',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => confirmLogout(context, state),
                      child: Text(strings.text('Login')),
                    ),
                  ],
                ),
              ),
            Card(
              elevation: 0,
              child: _RoundedInkClip(
                child: ListTile(
                  leading: _Avatar(
                    url: state.currentUserAvatar,
                    fallback: Icons.person_rounded,
                  ),
                  title: Text(user?.nickname ?? strings.text('Not logged in')),
                  subtitle: Text(
                    [
                      if (user?.username.isNotEmpty == true)
                        '@${user!.username}',
                      if (user != null) 'UID ${user.uid}',
                      if (user?.onlineStatus.isNotEmpty == true)
                        user!.onlineStatus,
                    ].join(' | '),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: user == null
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  AccountSettingsScreen(state: state),
                            ),
                          );
                        },
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              child: _RoundedInkClip(
                child: Column(
                  children: separatedTiles([
                    actionTile(
                      icon: Icons.settings_outlined,
                      title: strings.text('Settings'),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => SettingsScreen(state: state),
                          ),
                        );
                      },
                    ),
                    actionTile(
                      icon: Icons.qr_code_2_outlined,
                      title: strings.text('My QR code'),
                      onTap: user == null
                          ? null
                          : () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => UserQrScreen(state: state),
                                ),
                              );
                            },
                    ),
                    actionTile(
                      icon: Icons.apps_outlined,
                      title: strings.text('eMApps'),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => EmAppsScreen(state: state),
                          ),
                        );
                      },
                    ),
                    actionTile(
                      icon: Icons.sync,
                      title: strings.text('Refresh all'),
                      onTap: () => unawaited(state.refreshHome()),
                    ),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.notifications_none),
                    title: Text(strings.text('Unread notices')),
                    trailing: Badge(label: Text('${counts.notices}')),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.alternate_email),
                    title: Text(strings.text('Mentions and replies')),
                    trailing: Badge(label: Text('${counts.mentions}')),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.manage_accounts_outlined),
                    title: Text(strings.text('Friend changes')),
                    trailing: Badge(label: Text('${counts.friendChanges}')),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.person_add_alt),
                    title: Text(strings.text('Friend requests')),
                    trailing: Badge(label: Text('${counts.friendRequests}')),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.group_add_outlined),
                    title: Text(strings.text('Group reviews')),
                    trailing: Badge(label: Text('${counts.groupApplications}')),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              child: _RoundedInkClip(
                child: Column(
                  children: separatedTiles([
                    actionTile(
                      icon: Icons.logout,
                      title: strings.text('Logout'),
                      color: colors.error,
                      onTap: () => confirmLogout(context, state),
                    ),
                  ]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key, required this.state});

  final CsacAppState state;

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final imagePicker = ImagePicker();
  bool updatingNickname = false;
  bool updatingAvatar = false;
  bool updatingPassword = false;
  bool updatingPatAction = false;
  bool deletingAccount = false;

  Future<void> editNickname() async {
    final current = widget.state.user?.nickname ?? '';
    final nickname = await showDialog<String>(
      context: context,
      builder: (context) => _NicknameDialog(initialNickname: current),
    );
    if (nickname == null || !mounted) {
      return;
    }
    final trimmed = nickname.trim();
    if (trimmed.isEmpty) {
      showSnack(context.strings.text('Please enter a nickname.'));
      return;
    }
    if (trimmed == current.trim()) {
      return;
    }
    setState(() => updatingNickname = true);
    try {
      await widget.state.updateNickname(trimmed);
      if (!mounted) {
        return;
      }
      showSnack(context.strings.text('Nickname updated.'));
      setState(() {});
    } catch (err) {
      if (mounted) {
        showSnack(
          context.strings.format('Update failed: {error}', {'error': err}),
        );
      }
    } finally {
      if (mounted) {
        setState(() => updatingNickname = false);
      }
    }
  }

  Future<void> changeAvatar() async {
    if (updatingAvatar) {
      return;
    }
    final picked = await imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (picked == null || !mounted) {
      return;
    }
    final bytes = await picked.readAsBytes();
    if (!mounted) {
      return;
    }
    setState(() => updatingAvatar = true);
    try {
      await widget.state.updateAvatar(bytes, picked.name);
      if (!mounted) {
        return;
      }
      showSnack(context.strings.text('Avatar updated.'));
      setState(() {});
    } catch (err) {
      if (mounted) {
        showSnack(
          context.strings.format('Update failed: {error}', {'error': err}),
        );
      }
    } finally {
      if (mounted) {
        setState(() => updatingAvatar = false);
      }
    }
  }

  Future<void> changePassword() async {
    final result = await showDialog<_PasswordChange>(
      context: context,
      builder: (context) => const _PasswordChangeDialog(),
    );
    if (result == null || !mounted) {
      return;
    }
    if (result.oldPassword.isEmpty ||
        result.newPassword.isEmpty ||
        result.confirmPassword.isEmpty) {
      showSnack(context.strings.text('Please fill all password fields.'));
      return;
    }
    if (result.newPassword.length < 6) {
      showSnack(
        context.strings.text('New password must be at least 6 characters.'),
      );
      return;
    }
    if (result.newPassword != result.confirmPassword) {
      showSnack(context.strings.text('Passwords do not match.'));
      return;
    }
    setState(() => updatingPassword = true);
    try {
      await widget.state.updatePassword(
        result.oldPassword,
        result.newPassword,
        result.confirmPassword,
      );
      if (!mounted) {
        return;
      }
      showSnack(context.strings.text('Password updated.'));
    } catch (err) {
      if (mounted) {
        showSnack(
          context.strings.format('Update failed: {error}', {'error': err}),
        );
      }
    } finally {
      if (mounted) {
        setState(() => updatingPassword = false);
      }
    }
  }

  Future<void> editPatAction() async {
    final current = widget.state.user?.patAction ?? defaultPatAction;
    final action = await showDialog<String>(
      context: context,
      builder: (context) => _PatActionDialog(initialAction: current),
    );
    if (action == null || !mounted) {
      return;
    }
    final trimmed = action.trim();
    if (trimmed.isEmpty) {
      showSnack(context.strings.text('Please enter a pat action.'));
      return;
    }
    if (trimmed == current.trim()) {
      return;
    }
    setState(() => updatingPatAction = true);
    try {
      await widget.state.updatePatAction(trimmed);
      if (!mounted) {
        return;
      }
      showSnack(context.strings.text('Pat action updated.'));
      setState(() {});
    } catch (err) {
      if (mounted) {
        showSnack(
          context.strings.format('Update failed: {error}', {'error': err}),
        );
      }
    } finally {
      if (mounted) {
        setState(() => updatingPatAction = false);
      }
    }
  }

  Future<void> deleteAccount() async {
    final strings = context.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const _DeleteAccountDialog(),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => deletingAccount = true);
    try {
      final coolingDays = await widget.state.deleteAccount();
      if (!mounted) {
        return;
      }
      navigator.popUntil((route) => route.isFirst);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            strings.format(
              'Account deletion started. You can restore it within {days} days.',
              {'days': coolingDays},
            ),
          ),
        ),
      );
    } catch (err) {
      if (mounted) {
        showSnack(
          context.strings.format('Delete failed: {error}', {'error': err}),
        );
      }
    } finally {
      if (mounted) {
        setState(() => deletingAccount = false);
      }
    }
  }

  void showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget progressOrChevron(bool loading) {
    if (!loading) {
      return const Icon(Icons.chevron_right);
    }
    return const SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.state.user;
    final strings = context.strings;
    final hiddenConversationCount = widget.state.conversations
        .where((conversation) => conversation.hidden)
        .length;
    return Scaffold(
      appBar: AppBar(title: Text(strings.text('Account settings'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _Avatar(
                      url: widget.state.currentUserAvatar,
                      fallback: Icons.person_rounded,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.nickname ?? strings.text('Not logged in'),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            [
                              if (user?.username.isNotEmpty == true)
                                '@${user!.username}',
                              if (user != null) 'UID ${user.uid}',
                            ].join(' | '),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              child: _RoundedInkClip(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.badge_outlined),
                      title: Text(strings.text('Change nickname')),
                      subtitle: Text(user?.nickname ?? ''),
                      trailing: progressOrChevron(updatingNickname),
                      onTap: updatingNickname ? null : editNickname,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.add_a_photo_outlined),
                      title: Text(strings.text('Change avatar')),
                      subtitle: Text(
                        strings.text('Choose a new profile image'),
                      ),
                      trailing: progressOrChevron(updatingAvatar),
                      onTap: updatingAvatar ? null : changeAvatar,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.qr_code_2_outlined),
                      title: Text(strings.text('My QR code')),
                      subtitle: Text(
                        strings.text('Share your profile link as a QR code'),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: user == null
                          ? null
                          : () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      UserQrScreen(state: widget.state),
                                ),
                              );
                            },
                    ),
                    const Divider(height: 1),
                    if (hiddenConversationCount > 0) ...[
                      ListTile(
                        leading: const Icon(Icons.visibility_off_outlined),
                        title: Text(strings.text('Hidden conversations')),
                        subtitle: Text(
                          strings.text('Manage conversations hidden from Home'),
                        ),
                        trailing: Badge(
                          label: Text('$hiddenConversationCount'),
                          child: const Icon(Icons.chevron_right),
                        ),
                        onTap: () {
                          unawaited(
                            Navigator.of(context)
                                .push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => HiddenConversationsScreen(
                                      state: widget.state,
                                    ),
                                  ),
                                )
                                .then((_) {
                                  if (mounted) {
                                    setState(() {});
                                  }
                                }),
                          );
                        },
                      ),
                      const Divider(height: 1),
                    ],
                    ListTile(
                      leading: const Icon(Icons.waving_hand_outlined),
                      title: Text(strings.text('Pat action')),
                      subtitle: Text(user?.patAction ?? defaultPatAction),
                      trailing: progressOrChevron(updatingPatAction),
                      onTap: updatingPatAction ? null : editPatAction,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.lock_reset_outlined),
                      title: Text(strings.text('Change password')),
                      subtitle: Text(
                        strings.text('Update your login password'),
                      ),
                      trailing: progressOrChevron(updatingPassword),
                      onTap: updatingPassword ? null : changePassword,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              strings.text('Danger zone'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              child: _RoundedInkClip(
                child: ListTile(
                  leading: Icon(
                    Icons.delete_forever_outlined,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    strings.text('Delete account'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  subtitle: Text(
                    strings.text(
                      'Start account deletion with a 14-day restore period.',
                    ),
                  ),
                  trailing: deletingAccount
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: deletingAccount ? null : deleteAccount,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PasswordChange {
  const _PasswordChange(
    this.oldPassword,
    this.newPassword,
    this.confirmPassword,
  );

  final String oldPassword;
  final String newPassword;
  final String confirmPassword;
}

class HiddenConversationsScreen extends StatefulWidget {
  const HiddenConversationsScreen({super.key, required this.state});

  final CsacAppState state;

  @override
  State<HiddenConversationsScreen> createState() =>
      _HiddenConversationsScreenState();
}

class _HiddenConversationsScreenState extends State<HiddenConversationsScreen> {
  bool refreshing = false;
  final Set<String> updating = <String>{};

  List<Conversation> get hiddenConversations => widget.state.conversations
      .where((conversation) => conversation.hidden)
      .toList(growable: false);

  String conversationKey(Conversation conversation) {
    return '${conversation.type.name}:${conversation.id}';
  }

  Future<void> refresh() async {
    setState(() => refreshing = true);
    try {
      await widget.state.loadConversations();
    } finally {
      if (mounted) {
        setState(() => refreshing = false);
      }
    }
  }

  Future<void> openConversation(Conversation conversation) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ChatScreen(state: widget.state, conversation: conversation),
      ),
    );
    if (mounted) {
      await refresh();
    }
  }

  Future<void> unhideConversation(Conversation conversation) async {
    final key = conversationKey(conversation);
    setState(() => updating.add(key));
    try {
      final update = await widget.state.toggleConversationHidden(conversation);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            update.message.trim().isNotEmpty
                ? update.message
                : context.strings.text('Conversation unhidden.'),
          ),
        ),
      );
    } catch (err) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(err.toString())));
    } finally {
      if (mounted) {
        setState(() => updating.remove(key));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final conversations = hiddenConversations;
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.text('Hidden conversations')),
        actions: [
          IconButton(
            tooltip: strings.text('Refresh'),
            onPressed: refreshing ? null : refresh,
            icon: refreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: refresh,
          child: conversations.isEmpty
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(16, 48, 16, 24),
                  children: [
                    _EmptyPanel(
                      message: strings.text('No hidden conversations.'),
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: conversations.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final conversation = conversations[index];
                    final key = conversationKey(conversation);
                    final isUpdating = updating.contains(key);
                    final fallbackSubtitle = strings.text(
                      conversation.type == ConversationType.group
                          ? 'Group chat'
                          : 'Private chat',
                    );
                    final subtitle =
                        conversation.statusSubtitle.trim().isNotEmpty
                        ? conversation.statusSubtitle.trim()
                        : conversation.subtitle.trim().isNotEmpty
                        ? conversation.subtitle.trim()
                        : fallbackSubtitle;
                    return Card(
                      elevation: 0,
                      margin: EdgeInsets.zero,
                      child: _RoundedInkClip(
                        child: ListTile(
                          leading: _ConversationAvatarHero(
                            conversation: conversation,
                            radius: 22,
                            enabled: false,
                          ),
                          title: Text(
                            conversation.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () =>
                              unawaited(openConversation(conversation)),
                          trailing: isUpdating
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : IconButton(
                                  tooltip: strings.text('Unhide conversation'),
                                  onPressed: () => unawaited(
                                    unhideConversation(conversation),
                                  ),
                                  icon: const Icon(Icons.visibility_outlined),
                                ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController()..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final canDelete = controller.text.trim() == 'DELETE';
    return AlertDialog(
      title: Text(strings.text('Delete account?')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            strings.text(
              'This starts account deletion. Your account stays restorable for 14 days before permanent deletion.',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: strings.text('Type DELETE to confirm'),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(strings.text('Cancel')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: canDelete ? () => Navigator.of(context).pop(true) : null,
          child: Text(strings.text('Delete account')),
        ),
      ],
    );
  }
}

class _NicknameDialog extends StatefulWidget {
  const _NicknameDialog({required this.initialNickname});

  final String initialNickname;

  @override
  State<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends State<_NicknameDialog> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialNickname);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() {
    Navigator.of(context).pop(controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AlertDialog(
      title: Text(strings.text('Change nickname')),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 16,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: strings.text('New nickname'),
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.text('Cancel')),
        ),
        FilledButton(onPressed: submit, child: Text(strings.text('Save'))),
      ],
    );
  }
}

class _PatActionDialog extends StatefulWidget {
  const _PatActionDialog({required this.initialAction});

  final String initialAction;

  @override
  State<_PatActionDialog> createState() => _PatActionDialogState();
}

class _PatActionDialogState extends State<_PatActionDialog> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialAction);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() {
    Navigator.of(context).pop(controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AlertDialog(
      title: Text(strings.text('Pat action')),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 16,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: strings.text('Pat action'),
          helperText: strings.text('Used in double-tap avatar pats'),
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.text('Cancel')),
        ),
        FilledButton(onPressed: submit, child: Text(strings.text('Save'))),
      ],
    );
  }
}

class _PasswordChangeDialog extends StatefulWidget {
  const _PasswordChangeDialog();

  @override
  State<_PasswordChangeDialog> createState() => _PasswordChangeDialogState();
}

class _PasswordChangeDialogState extends State<_PasswordChangeDialog> {
  final oldPassword = TextEditingController();
  final newPassword = TextEditingController();
  final confirmPassword = TextEditingController();

  @override
  void dispose() {
    oldPassword.dispose();
    newPassword.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  void submit() {
    Navigator.of(context).pop(
      _PasswordChange(oldPassword.text, newPassword.text, confirmPassword.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AlertDialog(
      title: Text(strings.text('Change password')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: oldPassword,
                obscureText: true,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: strings.text('Old password'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newPassword,
                obscureText: true,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: strings.text('New password'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmPassword,
                obscureText: true,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: strings.text('Confirm password'),
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => submit(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.text('Cancel')),
        ),
        FilledButton(onPressed: submit, child: Text(strings.text('Save'))),
      ],
    );
  }
}

class _ThemeColorOption {
  const _ThemeColorOption(this.label, this.color);

  final String label;
  final Color color;
}

class _LanguageOptionTile extends StatelessWidget {
  const _LanguageOptionTile({
    required this.label,
    required this.selected,
    required this.progress,
    required this.summaryBuilder,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Future<TranslationProgress> progress;
  final String Function(TranslationProgress progress) summaryBuilder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: selected ? const Icon(Icons.check) : const SizedBox(width: 24),
      title: Text(label),
      subtitle: FutureBuilder<TranslationProgress>(
        future: progress,
        builder: (context, snapshot) {
          final value = snapshot.data;
          if (value == null) {
            return const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(minHeight: 4),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${value.percentLabel} · ${summaryBuilder(value)}'),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: value.fraction,
                    minHeight: 5,
                  ),
                ),
              ],
            ),
          );
        },
      ),
      onTap: onTap,
    );
  }
}

class _CacheMetric {
  const _CacheMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
}

class _ThemeColorDot extends StatelessWidget {
  const _ThemeColorDot({required this.color, this.selected = false});

  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 3 : 1,
        ),
      ),
      child: selected
          ? Icon(
              Icons.check,
              size: 16,
              color:
                  ThemeData.estimateBrightnessForColor(color) == Brightness.dark
                  ? Colors.white
                  : Colors.black,
            )
          : null,
    );
  }
}

class _ThemeColorButton extends StatelessWidget {
  const _ThemeColorButton({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _ThemeColorOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.strings.text(option.label),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: _ThemeColorDot(color: option.color, selected: selected),
        ),
      ),
    );
  }
}

class _FollowThemeColorButton extends StatelessWidget {
  const _FollowThemeColorButton({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: context.strings.text('Follow theme'),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [colors.primaryContainer, colors.surfaceContainerHigh],
              ),
              border: Border.all(
                color: selected ? colors.primary : colors.outlineVariant,
                width: selected ? 3 : 1,
              ),
            ),
            child: selected
                ? Icon(Icons.check, size: 16, color: colors.onPrimaryContainer)
                : null,
          ),
        ),
      ),
    );
  }
}

class _ChatBubbleColorTrailing extends StatelessWidget {
  const _ChatBubbleColorTrailing({
    required this.colorValue,
    required this.fallback,
  });

  final int colorValue;
  final Color fallback;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ThemeColorDot(
          color: colorValue == defaultChatBubbleColorValue
              ? fallback
              : Color(colorValue),
        ),
        const SizedBox(width: 12),
        const Icon(Icons.chevron_right),
      ],
    );
  }
}

class _ChatBubbleThemePreview extends StatelessWidget {
  const _ChatBubbleThemePreview({required this.preferences});

  final CsacPreferences preferences;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.forum_outlined, color: colors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                strings.text('Chat bubble theme'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _PreviewBubble(
          text: strings.text('Preview message'),
          mine: false,
          preferences: preferences,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: _PreviewBubble(
            text: strings.text('Preview message'),
            mine: true,
            preferences: preferences,
          ),
        ),
      ],
    );
  }
}

class _PreviewBubble extends StatelessWidget {
  const _PreviewBubble({
    required this.text,
    required this.mine,
    required this.preferences,
  });

  final String text;
  final bool mine;
  final CsacPreferences preferences;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final fallback = mine
        ? colors.primaryContainer
        : colors.surfaceContainerHighest;
    final colorValue = mine
        ? preferences.ownChatBubbleColorValue
        : preferences.otherChatBubbleColorValue;
    final color =
        (colorValue == defaultChatBubbleColorValue
                ? fallback
                : Color(colorValue))
            .withValues(alpha: preferences.chatBubbleOpacity);
    final solidTextSource = Color.alphaBlend(
      color,
      theme.scaffoldBackgroundColor,
    );
    final textColor =
        ThemeData.estimateBrightnessForColor(solidTextSource) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: chatBubbleBorderRadius(
          preferences.chatBubbleCornerStyle,
          mine,
        ),
        border: Border.all(color: textColor.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(text, style: TextStyle(color: textColor)),
      ),
    );
  }
}

class _CacheMetricTile extends StatelessWidget {
  const _CacheMetricTile({required this.metric});

  final _CacheMetric metric;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 168,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(metric.icon, size: 20, color: colors.primary),
              const SizedBox(height: 10),
              Text(
                metric.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              Text(
                metric.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                metric.detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _csacAppName = 'CsAC';
const _csacAppBranch = csacClientBranch;
const _csacSourceUrl =
    'https://github.com/Leonmmcoset/csac-terminal/tree/main/flutter/csac';
const _csacAuthorUrl = 'https://github.com/Leonmmcoset';
const _csacCommunityTranslationUrl =
    'https://zh.crowdin.com/project/csac-flutter';

class AppInfoScreen extends StatefulWidget {
  const AppInfoScreen({super.key});

  @override
  State<AppInfoScreen> createState() => _AppInfoScreenState();
}

class _AppInfoScreenState extends State<AppInfoScreen> {
  int appNameTapCount = 0;
  DateTime? lastAppNameTap;

  Future<void> copySourceUrl(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final copiedText = context.strings.text('Source link copied.');
    await Clipboard.setData(const ClipboardData(text: _csacSourceUrl));
    if (context.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(copiedText)));
    }
  }

  Future<void> openSourceUrl(BuildContext context) async {
    final url = Uri.parse(_csacSourceUrl);
    final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      await copySourceUrl(context);
    }
  }

  Future<void> openAuthorUrl(BuildContext context) async {
    final url = Uri.parse(_csacAuthorUrl);
    final messenger = ScaffoldMessenger.of(context);
    final copiedText = context.strings.text('Author link copied.');
    final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      await Clipboard.setData(const ClipboardData(text: _csacAuthorUrl));
      messenger.showSnackBar(SnackBar(content: Text(copiedText)));
    }
  }

  Future<void> openCommunityTranslationUrl(BuildContext context) async {
    final url = Uri.parse(_csacCommunityTranslationUrl);
    final messenger = ScaffoldMessenger.of(context);
    final copiedText = context.strings.text('Link copied.');
    final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      await Clipboard.setData(
        const ClipboardData(text: _csacCommunityTranslationUrl),
      );
      messenger.showSnackBar(SnackBar(content: Text(copiedText)));
    }
  }

  void handleAppNameTap(BuildContext context) {
    final now = DateTime.now();
    final previous = lastAppNameTap;
    if (previous == null ||
        now.difference(previous) > const Duration(seconds: 2)) {
      appNameTapCount = 0;
    }
    lastAppNameTap = now;
    appNameTapCount++;
    if (appNameTapCount >= 5) {
      appNameTapCount = 0;
      unawaited(openAuthorUrl(context));
    }
  }

  Widget infoTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: SelectableText(value),
      trailing: trailing,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(title: Text(strings.text('App information'))),
      body: SafeArea(
        child: FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (context, snapshot) {
            final packageInfo = snapshot.data;
            final version = packageInfo?.version ?? '-';
            final buildNumber = packageInfo?.buildNumber ?? '-';
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Card(
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primaryContainer,
                          child: Icon(
                            Icons.chat_bubble_outline,
                            color: Theme.of(
                              context,
                            ).colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => handleAppNameTap(context),
                                child: Text(
                                  _csacAppName,
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                strings.text('Third-party CsAC client'),
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  child: _RoundedInkClip(
                    child: Column(
                      children: [
                        infoTile(
                          context,
                          icon: Icons.apps_outlined,
                          title: strings.text('App name'),
                          value: _csacAppName,
                        ),
                        const Divider(height: 1),
                        infoTile(
                          context,
                          icon: Icons.account_tree_outlined,
                          title: strings.text('Branch'),
                          value: _csacAppBranch,
                        ),
                        const Divider(height: 1),
                        infoTile(
                          context,
                          icon: Icons.numbers_outlined,
                          title: strings.text('Version'),
                          value: version,
                        ),
                        const Divider(height: 1),
                        infoTile(
                          context,
                          icon: Icons.build_outlined,
                          title: strings.text('Build number'),
                          value: buildNumber,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  child: _RoundedInkClip(
                    child: Column(
                      children: [
                        infoTile(
                          context,
                          icon: Icons.code,
                          title: strings.text('Source code'),
                          value: _csacSourceUrl,
                          trailing: const Icon(Icons.open_in_new),
                          onTap: () => openSourceUrl(context),
                        ),
                        const Divider(height: 1),
                        infoTile(
                          context,
                          icon: Icons.translate_outlined,
                          title: strings.text('Community translations'),
                          value: _csacCommunityTranslationUrl,
                          trailing: const Icon(Icons.open_in_new),
                          onTap: () => openCommunityTranslationUrl(context),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.copy),
                          title: Text(strings.text('Copy source link')),
                          onTap: () => copySourceUrl(context),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AppInfoSubtitle extends StatelessWidget {
  const _AppInfoSubtitle();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final packageInfo = snapshot.data;
        final version = packageInfo?.version ?? '-';
        return Text('CsAC $version | $_csacAppBranch');
      },
    );
  }
}

class OpenSourceLicensesScreen extends StatefulWidget {
  const OpenSourceLicensesScreen({super.key});

  @override
  State<OpenSourceLicensesScreen> createState() =>
      _OpenSourceLicensesScreenState();
}

class _OpenSourceLicensesScreenState extends State<OpenSourceLicensesScreen> {
  late final Future<List<_LicenseNotice>> licenses = loadLicenses();

  Future<List<_LicenseNotice>> loadLicenses() async {
    final licensesByPackage = <String, Set<String>>{};
    await for (final entry in LicenseRegistry.licenses) {
      final packages = entry.packages
          .map((package) => package.trim())
          .where((package) => package.isNotEmpty)
          .toSet();
      final body = entry.paragraphs
          .map((paragraph) => paragraph.text.trimRight())
          .where((text) => text.trim().isNotEmpty)
          .join('\n\n');
      if (body.trim().isEmpty) {
        continue;
      }
      final packageNames = packages.isEmpty
          ? const <String>{'Unknown package'}
          : packages;
      for (final package in packageNames) {
        licensesByPackage.putIfAbsent(package, () => <String>{}).add(body);
      }
    }
    final notices = licensesByPackage.entries.map((entry) {
      return _LicenseNotice(
        packages: <String>[entry.key],
        body: entry.value.join('\n\n----------\n\n'),
      );
    }).toList();
    notices.sort((a, b) => a.title.compareTo(b.title));
    return notices;
  }

  Future<void> copyLicense(_LicenseNotice license) async {
    await Clipboard.setData(
      ClipboardData(text: '${license.title}\n\n${license.body}'),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.text('License copied.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(title: Text(strings.text('Open-source licenses'))),
      body: SafeArea(
        child: FutureBuilder<List<_LicenseNotice>>(
          future: licenses,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(strings.text('Loading licenses...')),
                  ],
                ),
              );
            }
            if (snapshot.hasError) {
              return _InlineError(
                message: snapshot.error.toString(),
                onRetry: () => setState(() {}),
              );
            }
            final items = snapshot.data ?? const <_LicenseNotice>[];
            if (items.isEmpty) {
              return _EmptyPanel(message: strings.text('No licenses found.'));
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(
                    strings.format('{count} license notices', {
                      'count': items.length,
                    }),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                for (final license in items)
                  Card(
                    elevation: 0,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: _RoundedInkClip(
                      child: ExpansionTile(
                        title: Text(license.title),
                        subtitle: Text(
                          strings.format('{count} packages', {
                            'count': license.packages.length,
                          }),
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          16,
                        ),
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => copyLicense(license),
                              icon: const Icon(Icons.copy),
                              label: Text(strings.text('Copy')),
                            ),
                          ),
                          SelectableText(license.body),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class AppLogsScreen extends StatefulWidget {
  const AppLogsScreen({super.key, required this.state});

  final CsacAppState state;

  @override
  State<AppLogsScreen> createState() => _AppLogsScreenState();
}

class _AppLogsScreenState extends State<AppLogsScreen> {
  late Future<List<AppLogFile>> logs = widget.state.loadAppLogFiles();

  String formatLogBytes(int bytes) {
    if (bytes <= 0) {
      return '0 B';
    }
    const units = <String>['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit += 1;
    }
    final decimals = value >= 10 || unit == 0 ? 0 : 1;
    return '${value.toStringAsFixed(decimals)} ${units[unit]}';
  }

  void refreshLogs() {
    setState(() => logs = widget.state.loadAppLogFiles());
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.text('App logs')),
        actions: [
          IconButton(
            tooltip: strings.text('Refresh'),
            onPressed: refreshLogs,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<List<AppLogFile>>(
          future: logs,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _InlineError(
                message: snapshot.error.toString(),
                onRetry: refreshLogs,
              );
            }
            final items = snapshot.data ?? const <AppLogFile>[];
            if (items.isEmpty) {
              return _EmptyPanel(message: strings.text('No app logs found.'));
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final log = items[index];
                return Card(
                  elevation: 0,
                  child: _RoundedInkClip(
                    child: ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: Text(log.name),
                      subtitle: Text(
                        '${formatLogBytes(log.bytes)} | ${formatLocalDateTime(log.modified)}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => AppLogDetailScreen(
                              state: widget.state,
                              log: log,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class AppLogDetailScreen extends StatefulWidget {
  const AppLogDetailScreen({super.key, required this.state, required this.log});

  final CsacAppState state;
  final AppLogFile log;

  @override
  State<AppLogDetailScreen> createState() => _AppLogDetailScreenState();
}

class _AppLogDetailScreenState extends State<AppLogDetailScreen> {
  late Future<String> content = widget.state.readAppLogFile(widget.log);

  void refreshLog() {
    setState(() => content = widget.state.readAppLogFile(widget.log));
  }

  Future<void> copyLog(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.text('Log copied.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.log.name),
        actions: [
          IconButton(
            tooltip: strings.text('Refresh'),
            onPressed: refreshLog,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<String>(
          future: content,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _InlineError(
                message: snapshot.error.toString(),
                onRetry: refreshLog,
              );
            }
            final text = snapshot.data ?? '';
            if (text.isEmpty) {
              return _EmptyPanel(message: strings.text('This log is empty.'));
            }
            return Column(
              children: [
                Material(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.info_outline),
                    title: SelectableText(widget.log.path),
                    subtitle: Text(
                      strings.text('Showing the latest part of this log.'),
                    ),
                    trailing: IconButton(
                      tooltip: strings.text('Copy'),
                      onPressed: () => copyLog(text),
                      icon: const Icon(Icons.copy),
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      text,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class NetworkDiagnosticsScreen extends StatefulWidget {
  const NetworkDiagnosticsScreen({super.key, required this.state});

  final CsacAppState state;

  @override
  State<NetworkDiagnosticsScreen> createState() =>
      _NetworkDiagnosticsScreenState();
}

class _NetworkDiagnosticsScreenState extends State<NetworkDiagnosticsScreen> {
  late Future<NetworkDiagnosticReport> report = widget.state
      .runNetworkDiagnostics();

  void rerun() {
    setState(() => report = widget.state.runNetworkDiagnostics());
  }

  Future<void> copyReport(NetworkDiagnosticReport value) async {
    final buffer = StringBuffer()
      ..writeln('Server: ${value.serverUrl}')
      ..writeln('Origin: ${value.originUrl}')
      ..writeln(
        'HTTP protocol: ${localizedApiHttpProtocolLabel(context, value.httpProtocol)}',
      )
      ..writeln('Started: ${formatLocalDateTime(value.startedAt)}')
      ..writeln('Total: ${value.totalMs} ms')
      ..writeln();
    for (final check in value.checks) {
      buffer.writeln(
        '[${check.ok ? 'OK' : 'FAIL'}] ${check.name} '
        '${check.elapsedMs} ms ${check.detail}',
      );
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.strings.text('Diagnostic report copied.')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.text('Connection diagnostics')),
        actions: [
          IconButton(
            tooltip: strings.text('Run again'),
            onPressed: rerun,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<NetworkDiagnosticReport>(
          future: report,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(strings.text('Running diagnostics...')),
                  ],
                ),
              );
            }
            if (snapshot.hasError) {
              return _InlineError(
                message: snapshot.error.toString(),
                onRetry: rerun,
              );
            }
            final value = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Card(
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: value.passed
                              ? colors.primaryContainer
                              : colors.errorContainer,
                          child: Icon(
                            value.passed
                                ? Icons.check_rounded
                                : Icons.error_outline,
                            color: value.passed
                                ? colors.onPrimaryContainer
                                : colors.onErrorContainer,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                strings.text(
                                  value.passed
                                      ? 'Connection looks good'
                                      : 'Connection has issues',
                                ),
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                strings.format('Total latency: {ms} ms', {
                                  'ms': value.totalMs,
                                }),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: colors.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: strings.text('Copy'),
                          onPressed: () => copyReport(value),
                          icon: const Icon(Icons.copy),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  child: _RoundedInkClip(
                    child: Column(
                      children: [
                        _DiagnosticInfoTile(
                          icon: Icons.dns_outlined,
                          label: strings.text('Server'),
                          value: value.serverUrl,
                        ),
                        const Divider(height: 1),
                        _DiagnosticInfoTile(
                          icon: Icons.public_outlined,
                          label: strings.text('Image origin'),
                          value: value.originUrl,
                        ),
                        const Divider(height: 1),
                        _DiagnosticInfoTile(
                          icon: Icons.http_outlined,
                          label: strings.text('HTTP protocol'),
                          value: localizedApiHttpProtocolLabel(
                            context,
                            value.httpProtocol,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                for (final check in value.checks)
                  Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(
                        check.ok
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        color: check.ok ? colors.primary : colors.error,
                      ),
                      title: Text(strings.text(check.name)),
                      subtitle: SelectableText(
                        check.detail.isEmpty ? '-' : check.detail,
                      ),
                      trailing: Text('${check.elapsedMs} ms'),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

String localizedApiHttpProtocolLabel(
  BuildContext context,
  ApiHttpProtocol protocol,
) {
  return context.strings.text(apiHttpProtocolLabel(protocol));
}

class _DiagnosticInfoTile extends StatelessWidget {
  const _DiagnosticInfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: SelectableText(value),
    );
  }
}

enum ApiDocMethod { get, post }

class ApiDocParam {
  const ApiDocParam({
    required this.name,
    required this.description,
    this.required = false,
    this.example = '',
  });

  final String name;
  final String description;
  final bool required;
  final String example;
}

class ApiDocEndpoint {
  const ApiDocEndpoint({
    required this.group,
    required this.route,
    required this.method,
    required this.summary,
    required this.description,
    this.params = const <ApiDocParam>[],
    this.runnableInExplorer = true,
  });

  final String group;
  final String route;
  final ApiDocMethod method;
  final String summary;
  final String description;
  final List<ApiDocParam> params;
  final bool runnableInExplorer;

  String get methodLabel => method == ApiDocMethod.post ? 'POST' : 'GET';
}

const apiDocEndpoints = <ApiDocEndpoint>[
  ApiDocEndpoint(
    group: 'Auth',
    route: 'auth/login',
    method: ApiDocMethod.post,
    summary: 'Login',
    description:
        'Log in with username, password and client platform id. v2.1.1 also checks cooling-period and permanently deleted accounts.',
    params: [
      ApiDocParam(name: 'username', description: 'Username', required: true),
      ApiDocParam(name: 'pwd', description: 'Password', required: true),
      ApiDocParam(
        name: 'platform',
        description: 'Client platform id, for example flutter-leon-1.0.0',
        required: true,
      ),
    ],
  ),
  ApiDocEndpoint(
    group: 'Auth',
    route: 'auth/login_by_email',
    method: ApiDocMethod.post,
    summary: 'Email password login',
    description:
        'Log in with email, password and client platform id. Deleted accounts in the cooling period can be restored first.',
    params: [
      ApiDocParam(name: 'email', description: 'Email address', required: true),
      ApiDocParam(name: 'pwd', description: 'Password', required: true),
      ApiDocParam(
        name: 'platform',
        description: 'Client platform id, for example flutter-leon-1.0.0',
        required: true,
      ),
    ],
  ),
  ApiDocEndpoint(
    group: 'Auth',
    route: 'auth/send_login_code',
    method: ApiDocMethod.post,
    summary: 'Send login code',
    description:
        'Send a 6-digit email login code. Codes are valid for about 10 minutes and resend cooldown is normally 60 seconds.',
    params: [
      ApiDocParam(name: 'email', description: 'Email address', required: true),
    ],
  ),
  ApiDocEndpoint(
    group: 'Auth',
    route: 'auth/login_by_code',
    method: ApiDocMethod.post,
    summary: 'Email code login',
    description: 'Log in with email, 6-digit email code and platform id.',
    params: [
      ApiDocParam(name: 'email', description: 'Email address', required: true),
      ApiDocParam(
        name: 'email_code',
        description: '6-digit email login code',
        required: true,
      ),
      ApiDocParam(
        name: 'platform',
        description: 'Client platform id, for example flutter-leon-1.0.0',
        required: true,
      ),
    ],
  ),
  ApiDocEndpoint(
    group: 'Auth',
    route: 'auth/send_register_code',
    method: ApiDocMethod.post,
    summary: 'Send register code',
    description: 'Send a 6-digit email verification code before registration.',
    params: [
      ApiDocParam(name: 'email', description: 'Email address', required: true),
    ],
  ),
  ApiDocEndpoint(
    group: 'Auth',
    route: 'auth/register',
    method: ApiDocMethod.post,
    summary: 'Register account',
    description:
        'Create a new user account after email verification. Avatar uses multipart file field avatar.',
    params: [
      ApiDocParam(name: 'username', description: 'Username', required: true),
      ApiDocParam(name: 'nickname', description: 'Nickname', required: true),
      ApiDocParam(name: 'email', description: 'Email address', required: true),
      ApiDocParam(
        name: 'email_code',
        description: '6-digit email verification code',
        required: true,
      ),
      ApiDocParam(name: 'pwd', description: 'Password', required: true),
      ApiDocParam(
        name: 'confirm_pwd',
        description: 'Confirm password',
        required: true,
      ),
      ApiDocParam(name: 'avatar', description: 'Multipart avatar file'),
    ],
  ),
  ApiDocEndpoint(
    group: 'Auth',
    route: 'auth/send_email_bind_code',
    method: ApiDocMethod.post,
    summary: 'Send email bind code',
    description: 'Send a 6-digit code for old accounts that must bind email.',
    params: [
      ApiDocParam(name: 'email', description: 'Email address', required: true),
    ],
  ),
  ApiDocEndpoint(
    group: 'Auth',
    route: 'auth/verify_email_bind_code',
    method: ApiDocMethod.post,
    summary: 'Verify email bind code',
    description:
        'Bind email for an already logged-in old account. Keep the same session cookie.',
    params: [
      ApiDocParam(name: 'email', description: 'Email address', required: true),
      ApiDocParam(
        name: 'email_code',
        description: '6-digit email verification code',
        required: true,
      ),
    ],
  ),
  ApiDocEndpoint(
    group: 'Auth',
    route: 'auth/logout',
    method: ApiDocMethod.post,
    summary: 'Logout',
    description: 'Clear the current server session.',
  ),
  ApiDocEndpoint(
    group: 'Auth',
    route: 'auth/request_restore',
    method: ApiDocMethod.post,
    summary: 'Request account restore',
    description:
        'Send an account restore token to the registered email for accounts inside the 14-day deletion cooling period.',
    params: [
      ApiDocParam(name: 'email', description: 'Email address', required: true),
    ],
  ),
  ApiDocEndpoint(
    group: 'Auth',
    route: 'auth/restore_account',
    method: ApiDocMethod.post,
    summary: 'Restore account',
    description: 'Restore a deleted account by email and restore token.',
    params: [
      ApiDocParam(name: 'email', description: 'Email address', required: true),
      ApiDocParam(
        name: 'restore_token',
        description: 'Restore token from email',
        required: true,
      ),
    ],
  ),
  ApiDocEndpoint(
    group: 'Admin',
    route: 'admin/restore_account',
    method: ApiDocMethod.post,
    summary: 'Admin restore account',
    description:
        'Admin-only manual restore for an account inside the deletion cooling period.',
    params: [
      ApiDocParam(name: 'uid', description: 'Target user UID', required: true),
    ],
  ),
  ApiDocEndpoint(
    group: 'User',
    route: 'user/get_info',
    method: ApiDocMethod.get,
    summary: 'Get user profile',
    description: 'Get current user profile, or another user by uid.',
    params: [ApiDocParam(name: 'uid', description: 'Target user UID')],
  ),
  ApiDocEndpoint(
    group: 'User',
    route: 'user/update_profile',
    method: ApiDocMethod.post,
    summary: 'Update profile',
    description:
        'Update nickname, password, avatar, privacy, pat action or profile fields.',
    params: [
      ApiDocParam(
        name: 'action',
        description: 'nickname / password / avatar / privacy / pat_action',
        required: true,
        example: 'nickname',
      ),
      ApiDocParam(name: 'nickname', description: 'New nickname'),
      ApiDocParam(name: 'pat_action', description: 'Pat action text'),
      ApiDocParam(name: 'value', description: 'Alias value for action updates'),
      ApiDocParam(name: 'allow_auto_join', description: '0 or 1'),
      ApiDocParam(name: 'old_password', description: 'Current password'),
      ApiDocParam(name: 'new_password', description: 'New password'),
      ApiDocParam(name: 'confirm_password', description: 'Confirm password'),
      ApiDocParam(name: 'avatar', description: 'Multipart avatar file'),
    ],
  ),
  ApiDocEndpoint(
    group: 'User',
    route: 'user/upgrade_password',
    method: ApiDocMethod.post,
    summary: 'Upgrade password hash',
    description:
        'Change password for an account still using the old hash flow.',
    params: [
      ApiDocParam(
        name: 'old_password',
        description: 'Current password, optional for legacy upgrade flow',
      ),
      ApiDocParam(
        name: 'new_password',
        description: 'New password',
        required: true,
      ),
      ApiDocParam(
        name: 'confirm_password',
        description: 'Confirm new password',
        required: true,
      ),
    ],
  ),
  ApiDocEndpoint(
    group: 'User',
    route: 'user/delete_account',
    method: ApiDocMethod.post,
    summary: 'Delete account',
    description:
        'Start account deletion. v2.1.1 keeps data for a 14-day cooling period and returns cooling_period_days.',
  ),
  ApiDocEndpoint(
    group: 'User',
    route: 'user/get_friends',
    method: ApiDocMethod.get,
    summary: 'Friend list',
    description: 'Return accepted friends for current user.',
  ),
  ApiDocEndpoint(
    group: 'User',
    route: 'user/get_groups',
    method: ApiDocMethod.get,
    summary: 'Joined groups',
    description: 'Return groups joined by current user.',
  ),
  ApiDocEndpoint(
    group: 'User',
    route: 'user/get_hide_conv_list',
    method: ApiDocMethod.get,
    summary: 'Hidden conversations',
    description: 'Return hidden group room IDs for the current user.',
  ),
  ApiDocEndpoint(
    group: 'User',
    route: 'user/toggle_hide_conv',
    method: ApiDocMethod.post,
    summary: 'Toggle hidden conversation',
    description: 'Hide a group conversation or restore it when already hidden.',
    params: [
      ApiDocParam(
        name: 'room_id',
        description: 'Group room ID',
        required: true,
      ),
    ],
  ),
  ApiDocEndpoint(
    group: 'User',
    route: 'user/get_notifications',
    method: ApiDocMethod.get,
    summary: 'Notification counters',
    description:
        'Return unread notice, friend request and deleted-friend counts.',
  ),
  ApiDocEndpoint(
    group: 'User',
    route: 'user/get_notice_list',
    method: ApiDocMethod.get,
    summary: 'Notice list',
    description: 'Return system notices for the current user.',
  ),
  ApiDocEndpoint(
    group: 'User',
    route: 'user/mark_notice_read',
    method: ApiDocMethod.post,
    summary: 'Mark notices read',
    description:
        'Mark one notice as read, or all notices when read_all is true.',
    params: [
      ApiDocParam(name: 'notice_id', description: 'Notice ID'),
      ApiDocParam(name: 'read_all', description: '0 or 1', example: '1'),
    ],
  ),
  ApiDocEndpoint(
    group: 'User',
    route: 'user/get_created_groups',
    method: ApiDocMethod.get,
    summary: 'Created groups',
    description: 'Return public groups created by a user.',
    params: [ApiDocParam(name: 'uid', description: 'Target user UID')],
  ),
  ApiDocEndpoint(
    group: 'Friend',
    route: 'friend/send_request',
    method: ApiDocMethod.post,
    summary: 'Send friend request',
    description: 'Request to add a user as friend.',
    params: [
      ApiDocParam(name: 'to_uid', description: 'Target UID', required: true),
      ApiDocParam(name: 'friend_id', description: 'Legacy alias for to_uid'),
      ApiDocParam(name: 'message', description: 'Request message'),
    ],
  ),
  ApiDocEndpoint(
    group: 'Friend',
    route: 'friend/handle_request',
    method: ApiDocMethod.post,
    summary: 'Handle friend request',
    description: 'Accept or reject a friend request.',
    params: [
      ApiDocParam(
        name: 'request_id',
        description: 'Friend request ID',
        required: true,
      ),
      ApiDocParam(
        name: 'action',
        description: 'agree or refuse',
        required: true,
        example: 'agree',
      ),
    ],
  ),
  ApiDocEndpoint(
    group: 'Friend',
    route: 'friend/update_remark',
    method: ApiDocMethod.post,
    summary: 'Update friend remark',
    description: 'Set remark for a friend.',
    params: [
      ApiDocParam(name: 'friend_id', description: 'Friend UID', required: true),
      ApiDocParam(name: 'remark', description: 'Remark text'),
    ],
  ),
  ApiDocEndpoint(
    group: 'Friend',
    route: 'friend/delete_friend',
    method: ApiDocMethod.post,
    summary: 'Delete friend',
    description: 'Remove a friend relation.',
    params: [
      ApiDocParam(name: 'friend_id', description: 'Friend UID', required: true),
    ],
  ),
  ApiDocEndpoint(
    group: 'Friend',
    route: 'friend/block_friend',
    method: ApiDocMethod.post,
    summary: 'Block friend',
    description: 'Block an existing friend relation.',
    params: [
      ApiDocParam(name: 'friend_id', description: 'Friend UID', required: true),
    ],
  ),
  ApiDocEndpoint(
    group: 'Friend',
    route: 'friend/recover_friend',
    method: ApiDocMethod.post,
    summary: 'Recover friend',
    description: 'Recover a deleted friend directly or send a recover request.',
    params: [
      ApiDocParam(name: 'friend_id', description: 'Friend UID', required: true),
      ApiDocParam(name: 'direct', description: '0 or 1'),
      ApiDocParam(name: 'message', description: 'Recover request message'),
    ],
  ),
  ApiDocEndpoint(
    group: 'Friend',
    route: 'friend/get_common_groups',
    method: ApiDocMethod.get,
    summary: 'Common groups',
    description: 'List common groups with a friend.',
    params: [
      ApiDocParam(name: 'friend_id', description: 'Friend UID', required: true),
    ],
  ),
  ApiDocEndpoint(
    group: 'Friend',
    route: 'friend/get_deleted_notices',
    method: ApiDocMethod.get,
    summary: 'Deleted friend notices',
    description: 'Return recently deleted friend relation notices.',
  ),
  ApiDocEndpoint(
    group: 'Friend',
    route: 'friend/get_friend_requests',
    method: ApiDocMethod.get,
    summary: 'Pending friend requests',
    description: 'Return pending friend requests for the current user.',
  ),
  ApiDocEndpoint(
    group: 'Group',
    route: 'group/get_public_list',
    method: ApiDocMethod.get,
    summary: 'Public groups',
    description:
        'List public groups. Groups with allow_search=0 are omitted in v2.1.1.',
  ),
  ApiDocEndpoint(
    group: 'Group',
    route: 'group/get_group_view_info',
    method: ApiDocMethod.get,
    summary: 'Group profile',
    description:
        'Get group profile and membership state. Returns allow_search; when allow_search=0 non-members receive 404.',
    params: [
      ApiDocParam(
        name: 'room_id',
        description: 'Group room ID',
        required: true,
      ),
      ApiDocParam(name: 'rid', description: 'Legacy alias for room_id'),
    ],
  ),
  ApiDocEndpoint(
    group: 'Group',
    route: 'group/get_members',
    method: ApiDocMethod.get,
    summary: 'Group members',
    description: 'List members in a group.',
    params: [
      ApiDocParam(
        name: 'room_id',
        description: 'Group room ID',
        required: true,
      ),
      ApiDocParam(name: 'rid', description: 'Legacy alias for room_id'),
    ],
  ),
  ApiDocEndpoint(
    group: 'Group',
    route: 'group/get_applications',
    method: ApiDocMethod.get,
    summary: 'Join applications',
    description: 'List pending join applications for a group.',
    params: [
      ApiDocParam(
        name: 'room_id',
        description: 'Group room ID',
        required: true,
      ),
      ApiDocParam(name: 'rid', description: 'Legacy alias for room_id'),
    ],
  ),
  ApiDocEndpoint(
    group: 'Group',
    route: 'group/create',
    method: ApiDocMethod.post,
    summary: 'Create group',
    description: 'Create a new group.',
    params: [
      ApiDocParam(name: 'room_name', description: 'Group name', required: true),
      ApiDocParam(name: 'description', description: 'Group description'),
    ],
  ),
  ApiDocEndpoint(
    group: 'Group',
    route: 'group/apply_join',
    method: ApiDocMethod.post,
    summary: 'Apply to join group',
    description:
        'Send a join request or join by invite code. Groups with allow_search=0 reject active join and require member invitation or QR code.',
    params: [
      ApiDocParam(
        name: 'room_id',
        description: 'Group room ID',
        required: true,
      ),
      ApiDocParam(name: 'rid', description: 'Legacy alias for room_id'),
      ApiDocParam(name: 'code', description: 'Invite code if required'),
      ApiDocParam(name: 'answer', description: 'Join question answer'),
    ],
  ),
  ApiDocEndpoint(
    group: 'Group',
    route: 'group/handle_apply',
    method: ApiDocMethod.post,
    summary: 'Handle join application',
    description: 'Approve or refuse a pending group join application.',
    params: [
      ApiDocParam(
        name: 'apply_id',
        description: 'Application ID',
        required: true,
      ),
      ApiDocParam(
        name: 'action',
        description: 'pass or refuse',
        required: true,
        example: 'pass',
      ),
    ],
  ),
  ApiDocEndpoint(
    group: 'Group',
    route: 'group/invite_member',
    method: ApiDocMethod.post,
    summary: 'Invite member',
    description: 'Invite a user into a group.',
    params: [
      ApiDocParam(
        name: 'room_id',
        description: 'Group room ID',
        required: true,
      ),
      ApiDocParam(name: 'rid', description: 'Legacy alias for room_id'),
      ApiDocParam(
        name: 'target_uid',
        description: 'Target UID',
        required: true,
      ),
      ApiDocParam(name: 'uid', description: 'Legacy alias for target_uid'),
    ],
  ),
  ApiDocEndpoint(
    group: 'Group',
    route: 'group/edit_info',
    method: ApiDocMethod.post,
    summary: 'Edit group info',
    description:
        'Update group name, intro, notice or avatar. Avatar uses multipart file field avatar.',
    params: [
      ApiDocParam(
        name: 'room_id',
        description: 'Group room ID',
        required: true,
      ),
      ApiDocParam(
        name: 'action',
        description: 'name / intro / notice / avatar',
        example: 'name',
      ),
      ApiDocParam(name: 'value', description: 'Value used with action'),
      ApiDocParam(name: 'room_name', description: 'Group name'),
      ApiDocParam(name: 'intro', description: 'Group intro'),
      ApiDocParam(name: 'notice', description: 'Group notice'),
      ApiDocParam(
        name: 'avatar',
        description: 'Avatar URL or multipart avatar file field',
      ),
    ],
  ),
  ApiDocEndpoint(
    group: 'Group',
    route: 'group/update_settings',
    method: ApiDocMethod.post,
    summary: 'Update group settings',
    description:
        'Update join mode, invite permissions and group visibility. allow_search=0 hides the group from public list, group ID search and active join.',
    params: [
      ApiDocParam(
        name: 'room_id',
        description: 'Group room ID',
        required: true,
      ),
      ApiDocParam(name: 'join_type', description: '1-4'),
      ApiDocParam(name: 'fixed_code', description: 'Fixed invite code'),
      ApiDocParam(name: 'question', description: 'Join question'),
      ApiDocParam(name: 'answer', description: 'Join answer'),
      ApiDocParam(name: 'show_in_list', description: '0 or 1'),
      ApiDocParam(name: 'allow_invite', description: '0 or 1'),
      ApiDocParam(
        name: 'allow_search',
        description: '1 allows search, 0 hides active join',
      ),
    ],
  ),
  ApiDocEndpoint(
    group: 'Group',
    route: 'group/reset_invite_code',
    method: ApiDocMethod.post,
    summary: 'Reset invite code',
    description: 'Generate a new group invite code.',
    params: [
      ApiDocParam(
        name: 'room_id',
        description: 'Group room ID',
        required: true,
      ),
    ],
  ),
  ApiDocEndpoint(
    group: 'Group',
    route: 'group/transfer',
    method: ApiDocMethod.post,
    summary: 'Transfer group owner',
    description: 'Send a group ownership transfer request.',
    params: [
      ApiDocParam(
        name: 'room_id',
        description: 'Group room ID',
        required: true,
      ),
      ApiDocParam(
        name: 'target_uid',
        description: 'New owner UID',
        required: true,
      ),
      ApiDocParam(
        name: 'new_owner_uid',
        description: 'Legacy alias for target_uid',
      ),
    ],
  ),
  ApiDocEndpoint(
    group: 'Group',
    route: 'group/disband',
    method: ApiDocMethod.post,
    summary: 'Disband group',
    description: 'Mark a group as disbanded.',
    params: [
      ApiDocParam(
        name: 'room_id',
        description: 'Group room ID',
        required: true,
      ),
    ],
  ),
  ApiDocEndpoint(
    group: 'Group',
    route: 'group/leave',
    method: ApiDocMethod.post,
    summary: 'Leave group',
    description: 'Leave a joined group. Owners must transfer or disband first.',
    params: [
      ApiDocParam(
        name: 'room_id',
        description: 'Group room ID',
        required: true,
      ),
      ApiDocParam(name: 'rid', description: 'Legacy alias for room_id'),
    ],
  ),
  ApiDocEndpoint(
    group: 'Group',
    route: 'group/mute_member',
    method: ApiDocMethod.post,
    summary: 'Mute member',
    description: 'Mute or unmute a group member.',
    params: [
      ApiDocParam(
        name: 'room_id',
        description: 'Group room ID',
        required: true,
      ),
      ApiDocParam(
        name: 'target_uid',
        description: 'Target UID',
        required: true,
      ),
      ApiDocParam(
        name: 'action',
        description: 'mute or unmute',
        required: true,
        example: 'mute',
      ),
      ApiDocParam(name: 'minutes', description: '1-43200 when muting'),
    ],
  ),
  ApiDocEndpoint(
    group: 'Group',
    route: 'group/kick_member',
    method: ApiDocMethod.post,
    summary: 'Kick member',
    description: 'Remove a member from a group.',
    params: [
      ApiDocParam(
        name: 'room_id',
        description: 'Group room ID',
        required: true,
      ),
      ApiDocParam(
        name: 'target_uid',
        description: 'Target UID',
        required: true,
      ),
    ],
  ),
  ApiDocEndpoint(
    group: 'Group',
    route: 'group/set_admin',
    method: ApiDocMethod.post,
    summary: 'Set admin',
    description: 'Grant or revoke group admin permission.',
    params: [
      ApiDocParam(
        name: 'room_id',
        description: 'Group room ID',
        required: true,
      ),
      ApiDocParam(
        name: 'target_uid',
        description: 'Target UID',
        required: true,
      ),
      ApiDocParam(
        name: 'action',
        description: 'set or remove',
        required: true,
        example: 'set',
      ),
    ],
  ),
  ApiDocEndpoint(
    group: 'Group',
    route: 'group/set_member_title',
    method: ApiDocMethod.post,
    summary: 'Set member title',
    description: 'Set custom group title and level for a member.',
    params: [
      ApiDocParam(
        name: 'room_id',
        description: 'Group room ID',
        required: true,
      ),
      ApiDocParam(name: 'rid', description: 'Legacy alias for room_id'),
      ApiDocParam(
        name: 'target_uid',
        description: 'Target UID',
        required: true,
      ),
      ApiDocParam(name: 'uid', description: 'Legacy alias for target_uid'),
      ApiDocParam(name: 'title', description: 'Member title'),
      ApiDocParam(name: 'level', description: 'Member level 1-100'),
    ],
  ),
  ApiDocEndpoint(
    group: 'Message',
    route: 'message/get_group_msg',
    method: ApiDocMethod.get,
    summary: 'Group messages',
    description: 'Load group messages with pagination.',
    params: [
      ApiDocParam(
        name: 'room_id',
        description: 'Group room ID',
        required: true,
      ),
      ApiDocParam(name: 'rid', description: 'Legacy alias for room_id'),
      ApiDocParam(name: 'before_id', description: 'Load messages before ID'),
      ApiDocParam(name: 'after_id', description: 'Load messages after ID'),
      ApiDocParam(name: 'limit', description: '20-200', example: '80'),
    ],
  ),
  ApiDocEndpoint(
    group: 'Message',
    route: 'group/get_group_msg',
    method: ApiDocMethod.get,
    summary: 'Group messages alias',
    description: 'Alias of message/get_group_msg.',
    params: [
      ApiDocParam(
        name: 'room_id',
        description: 'Group room ID',
        required: true,
      ),
      ApiDocParam(name: 'rid', description: 'Legacy alias for room_id'),
      ApiDocParam(name: 'before_id', description: 'Load messages before ID'),
      ApiDocParam(name: 'after_id', description: 'Load messages after ID'),
      ApiDocParam(name: 'limit', description: '20-200', example: '80'),
    ],
  ),
  ApiDocEndpoint(
    group: 'Message',
    route: 'message/get_private_msg',
    method: ApiDocMethod.get,
    summary: 'Private messages',
    description: 'Load private messages with pagination.',
    params: [
      ApiDocParam(name: 'friend_id', description: 'Friend UID', required: true),
      ApiDocParam(name: 'last_id', description: 'Alias for after_id'),
      ApiDocParam(name: 'before_id', description: 'Load messages before ID'),
      ApiDocParam(name: 'after_id', description: 'Load messages after ID'),
      ApiDocParam(name: 'limit', description: '20-200', example: '80'),
    ],
  ),
  ApiDocEndpoint(
    group: 'Message',
    route: 'message/send_group_msg',
    method: ApiDocMethod.post,
    summary: 'Send group message',
    description:
        'Send a text or image message to a group. Image uses multipart file field img.',
    params: [
      ApiDocParam(
        name: 'room_id',
        description: 'Group room ID',
        required: true,
      ),
      ApiDocParam(name: 'content', description: 'Message text', required: true),
      ApiDocParam(name: 'reply_to', description: 'Reply message ID'),
      ApiDocParam(name: 'mention_uids', description: 'Comma separated UIDs'),
      ApiDocParam(name: 'img', description: 'Multipart image file'),
    ],
  ),
  ApiDocEndpoint(
    group: 'Message',
    route: 'message/send_private_msg',
    method: ApiDocMethod.post,
    summary: 'Send private message',
    description:
        'Send a text or image message to a friend. Image uses multipart file field img.',
    params: [
      ApiDocParam(name: 'friend_id', description: 'Friend UID', required: true),
      ApiDocParam(name: 'content', description: 'Message text', required: true),
      ApiDocParam(name: 'reply_to', description: 'Reply message ID'),
      ApiDocParam(name: 'img', description: 'Multipart image file'),
    ],
  ),
  ApiDocEndpoint(
    group: 'Message',
    route: 'message/send_voice_msg',
    method: ApiDocMethod.post,
    summary: 'Send voice message',
    description: 'Send a voice message. Voice uses multipart file field voice.',
    params: [
      ApiDocParam(name: 'room_id', description: 'Group room ID'),
      ApiDocParam(name: 'friend_id', description: 'Private friend UID'),
      ApiDocParam(name: 'duration', description: 'Duration in seconds'),
      ApiDocParam(name: 'voice', description: 'Multipart voice file'),
    ],
  ),
  ApiDocEndpoint(
    group: 'Message',
    route: 'message/send_emoji_msg',
    method: ApiDocMethod.post,
    summary: 'Send emoji message',
    description: 'Send a sticker/emoji message to a group or private chat.',
    params: [
      ApiDocParam(name: 'room_id', description: 'Group room ID'),
      ApiDocParam(name: 'friend_id', description: 'Private friend UID'),
      ApiDocParam(
        name: 'abbr',
        description: 'Emoji abbreviation',
        required: true,
      ),
    ],
  ),
  ApiDocEndpoint(
    group: 'Emoji',
    route: 'emoji/get_list',
    method: ApiDocMethod.get,
    summary: 'Emoji list',
    description: 'Return available sticker/emoji metadata.',
  ),
  ApiDocEndpoint(
    group: 'Message',
    route: 'message/mark_read',
    method: ApiDocMethod.post,
    summary: 'Mark read',
    description: 'Mark private chat read or update group last read position.',
    params: [
      ApiDocParam(name: 'friend_id', description: 'Private friend UID'),
      ApiDocParam(name: 'room_id', description: 'Group room ID'),
      ApiDocParam(name: 'last_msg_id', description: 'Group last read message'),
    ],
  ),
  ApiDocEndpoint(
    group: 'Message',
    route: 'message/send_pat_msg',
    method: ApiDocMethod.post,
    summary: 'Send pat',
    description: 'Send a pat system message in group chat.',
    params: [
      ApiDocParam(
        name: 'room_id',
        description: 'Group room ID',
        required: true,
      ),
      ApiDocParam(
        name: 'target_uid',
        description: 'Target UID',
        required: true,
      ),
      ApiDocParam(name: 'rid', description: 'Legacy alias for room_id'),
      ApiDocParam(name: 'uid', description: 'Legacy alias for target_uid'),
    ],
  ),
  ApiDocEndpoint(
    group: 'Message',
    route: 'message/pat',
    method: ApiDocMethod.post,
    summary: 'Send pat alias',
    description: 'Alias of message/send_pat_msg.',
    params: [
      ApiDocParam(
        name: 'room_id',
        description: 'Group room ID',
        required: true,
      ),
      ApiDocParam(
        name: 'target_uid',
        description: 'Target UID',
        required: true,
      ),
      ApiDocParam(name: 'rid', description: 'Legacy alias for room_id'),
      ApiDocParam(name: 'uid', description: 'Legacy alias for target_uid'),
    ],
  ),
  ApiDocEndpoint(
    group: 'Message',
    route: 'message/recall_msg',
    method: ApiDocMethod.post,
    summary: 'Recall message',
    description: 'Recall a group or private message.',
    params: [
      ApiDocParam(name: 'msg_id', description: 'Message ID', required: true),
      ApiDocParam(name: 'room_id', description: 'Group room ID'),
      ApiDocParam(name: 'type', description: 'group or private'),
    ],
  ),
  ApiDocEndpoint(
    group: 'Message',
    route: 'message/get_mentions',
    method: ApiDocMethod.get,
    summary: 'Mention counters',
    description:
        'Return group mention and reply counters for the current user.',
  ),
  ApiDocEndpoint(
    group: 'Space',
    route: 'space/get_list',
    method: ApiDocMethod.get,
    summary: 'Space feed',
    description:
        'List main space posts from the current user and friends. Each item includes replies.',
    params: [
      ApiDocParam(name: 'page', description: 'Page number, default 1'),
      ApiDocParam(
        name: 'page_size',
        description: 'Items per page, default 20, max 50',
      ),
    ],
  ),
  ApiDocEndpoint(
    group: 'Space',
    route: 'space/send',
    method: ApiDocMethod.post,
    summary: 'Publish space post',
    description:
        'Publish a space post. Multipart file field images supports up to 9 images, 5 MB each.',
    params: [
      ApiDocParam(name: 'content', description: 'Text content'),
      ApiDocParam(name: 'images', description: 'Multipart image file field'),
    ],
  ),
  ApiDocEndpoint(
    group: 'Space',
    route: 'space/reply',
    method: ApiDocMethod.post,
    summary: 'Reply to space post',
    description:
        'Reply to a space post. Multipart file field images follows the same image rules.',
    params: [
      ApiDocParam(
        name: 'reply_id',
        description: 'Target space post ID',
        required: true,
      ),
      ApiDocParam(name: 'content', description: 'Reply text content'),
      ApiDocParam(name: 'images', description: 'Multipart image file field'),
    ],
  ),
  ApiDocEndpoint(
    group: 'Space',
    route: 'space/toggle_like',
    method: ApiDocMethod.post,
    summary: 'Toggle space like',
    description:
        'Like or unlike a space post, returning is_liked and likes_num.',
    params: [
      ApiDocParam(
        name: 'cont_id',
        description: 'Space post ID',
        required: true,
      ),
    ],
  ),
  ApiDocEndpoint(
    group: 'Space',
    route: 'space/delete',
    method: ApiDocMethod.post,
    summary: 'Delete space post',
    description:
        'Delete a post owned by the current user. Deleting a main post also deletes its replies.',
    params: [
      ApiDocParam(
        name: 'cont_id',
        description: 'Space post ID',
        required: true,
      ),
    ],
  ),
  ApiDocEndpoint(
    group: 'Essence',
    route: 'essence/get_essence',
    method: ApiDocMethod.get,
    summary: 'Essence messages',
    description: 'Load group essence messages.',
    params: [
      ApiDocParam(
        name: 'room_id',
        description: 'Group room ID',
        required: true,
      ),
    ],
  ),
  ApiDocEndpoint(
    group: 'Essence',
    route: 'essence/get_essence_stats',
    method: ApiDocMethod.get,
    summary: 'Essence stats',
    description: 'Load essence statistics for a group.',
    params: [
      ApiDocParam(
        name: 'room_id',
        description: 'Group room ID',
        required: true,
      ),
      ApiDocParam(name: 'type', description: 'today / week / month / all'),
    ],
  ),
  ApiDocEndpoint(
    group: 'Essence',
    route: 'essence/set_essence',
    method: ApiDocMethod.post,
    summary: 'Toggle essence',
    description: 'Set or unset a group message as essence.',
    params: [
      ApiDocParam(
        name: 'room_id',
        description: 'Group room ID',
        required: true,
      ),
      ApiDocParam(name: 'msg_id', description: 'Message ID', required: true),
    ],
  ),
  ApiDocEndpoint(
    group: 'Report',
    route: 'report/submit_report',
    method: ApiDocMethod.post,
    summary: 'Submit report',
    description: 'Report a user or group.',
    params: [
      ApiDocParam(
        name: 'type',
        description: 'user or group',
        required: true,
        example: 'user',
      ),
      ApiDocParam(name: 'uid', description: 'Reported user UID'),
      ApiDocParam(name: 'rid', description: 'Reported group room ID'),
      ApiDocParam(
        name: 'reason',
        description: 'At least 10 characters',
        required: true,
      ),
      ApiDocParam(name: 'anonymous', description: '0 or 1'),
      ApiDocParam(name: 'nickname', description: 'Reported user nickname'),
      ApiDocParam(name: 'username', description: 'Reported username'),
      ApiDocParam(name: 'room_name', description: 'Reported group name'),
    ],
  ),
  ApiDocEndpoint(
    group: 'Admin',
    route: 'admin/generate_token',
    method: ApiDocMethod.post,
    summary: 'Generate admin token',
    description: 'Generate a short-lived admin token. Admin only.',
  ),
  ApiDocEndpoint(
    group: 'Admin',
    route: 'admin/admin_ban',
    method: ApiDocMethod.get,
    summary: 'Ban list',
    description:
        'List currently banned users and groups. Admin token required.',
    params: [
      ApiDocParam(name: 'token', description: 'Admin token', required: true),
    ],
  ),
  ApiDocEndpoint(
    group: 'Admin',
    route: 'admin/admin_ban',
    method: ApiDocMethod.post,
    summary: 'Manage bans',
    description: 'Ban or unban users and groups. Admin token required.',
    params: [
      ApiDocParam(name: 'token', description: 'Admin token', required: true),
      ApiDocParam(
        name: 'action',
        description: 'ban_user / unban_user / ban_room / unban_room',
        required: true,
        example: 'ban_user',
      ),
      ApiDocParam(name: 'user_id', description: 'User ID for user ban actions'),
      ApiDocParam(
        name: 'room_id',
        description: 'Room ID for group ban actions',
      ),
      ApiDocParam(name: 'ban_days', description: 'Ban duration in days'),
      ApiDocParam(name: 'ban_reason', description: 'Ban reason'),
    ],
  ),
  ApiDocEndpoint(
    group: 'ACOP',
    route: 'diag/test-save',
    method: ApiDocMethod.post,
    summary: 'ACOP save-chain diagnostic',
    description:
        'ACOP gateway diagnostic route. Tests the complete ACR/AJL save chain and ACOP to ServerBot communication. Use the ACOP server address, not the normal CsAC API base URL.',
    params: [
      ApiDocParam(
        name: 'name',
        description: 'Optional test library name, default diag_test',
        example: 'diag_test',
      ),
      ApiDocParam(
        name: 'content',
        description: 'Optional JavaScript library content',
        example: "// DIAG test content\nconsole.log('test');",
      ),
      ApiDocParam(
        name: 'mode',
        description: 'Optional direct or http; empty runs the full path',
        example: 'http',
      ),
    ],
    runnableInExplorer: false,
  ),
  ApiDocEndpoint(
    group: 'ACOP',
    route: 'admin/acr/pending',
    method: ApiDocMethod.post,
    summary: 'Pending ACR uploads',
    description:
        'ACOP admin route. Lists pending ACR uploads and includes content so approval can save directly to ServerBot lib.',
    runnableInExplorer: false,
  ),
  ApiDocEndpoint(
    group: 'ACOP',
    route: 'admin/acr/review',
    method: ApiDocMethod.post,
    summary: 'Review ACR upload',
    description:
        'ACOP admin route. Approve or reject an ACR upload. Approval saves the script to ServerBot lib as AJL.',
    params: [
      ApiDocParam(name: 'id', description: 'ACR upload ID', required: true),
      ApiDocParam(
        name: 'action',
        description: 'approve or reject',
        required: true,
        example: 'approve',
      ),
      ApiDocParam(name: 'admin_note', description: 'Optional admin note'),
    ],
    runnableInExplorer: false,
  ),
  ApiDocEndpoint(
    group: 'ACOP',
    route: 'admin/lib/review',
    method: ApiDocMethod.post,
    summary: 'Review AJL library',
    description:
        'ACOP admin route. Approval notifies ServerBot to sign and save the AJL library to lib/.',
    params: [
      ApiDocParam(name: 'id', description: 'Library upload ID', required: true),
      ApiDocParam(
        name: 'action',
        description: 'approve or reject',
        required: true,
        example: 'approve',
      ),
      ApiDocParam(name: 'admin_note', description: 'Optional admin note'),
    ],
    runnableInExplorer: false,
  ),
  ApiDocEndpoint(
    group: 'ACOP',
    route: 'script/upload_ema',
    method: ApiDocMethod.post,
    summary: 'Upload EMA package',
    description:
        'ACOP developer route. Uploads an EMA JSON package for admin review before it is approved into eMApps.',
    params: [
      ApiDocParam(
        name: 'file_name',
        description: 'EMA file name',
        required: true,
      ),
      ApiDocParam(
        name: 'content',
        description: 'EMA JSON content',
        required: true,
      ),
    ],
    runnableInExplorer: false,
  ),
  ApiDocEndpoint(
    group: 'ACOP',
    route: 'admin/ema/pending',
    method: ApiDocMethod.post,
    summary: 'Pending EMA uploads',
    description:
        'ACOP admin route. Lists pending EMA uploads waiting for eMApps publication approval.',
    runnableInExplorer: false,
  ),
  ApiDocEndpoint(
    group: 'ACOP',
    route: 'admin/ema/review',
    method: ApiDocMethod.post,
    summary: 'Review EMA upload',
    description:
        'ACOP admin route. Approve or reject an EMA upload. Approval calls the eMApps internal approve callback.',
    params: [
      ApiDocParam(name: 'id', description: 'EMA upload ID', required: true),
      ApiDocParam(
        name: 'action',
        description: 'approve or reject',
        required: true,
        example: 'approve',
      ),
      ApiDocParam(name: 'admin_note', description: 'Optional admin note'),
    ],
    runnableInExplorer: false,
  ),
  ApiDocEndpoint(
    group: 'ServerBot',
    route: '/bot/internal/lib/approve',
    method: ApiDocMethod.post,
    summary: 'Approve and save library',
    description:
        'ServerBot internal route. Requires X-Bot-Secret. ACOP calls this after approving ACR/AJL content; it signs, writes lib/name.ajl and reloads libraries.',
    params: [
      ApiDocParam(name: 'id', description: 'Library ID, 0 for diagnostics'),
      ApiDocParam(name: 'name', description: 'Library name', required: true),
      ApiDocParam(
        name: 'version',
        description: 'Library version, default 1.0.0',
      ),
      ApiDocParam(
        name: 'content',
        description: 'JavaScript library source',
        required: true,
      ),
    ],
    runnableInExplorer: false,
  ),
  ApiDocEndpoint(
    group: 'ServerBot',
    route: '/bot/internal/lib/reload',
    method: ApiDocMethod.post,
    summary: 'Reload libraries',
    description:
        'ServerBot internal route. Requires X-Bot-Secret. Reloads all .ajl files from lib/.',
    runnableInExplorer: false,
  ),
  ApiDocEndpoint(
    group: 'eMApps',
    route: '/emapps/public/catalog',
    method: ApiDocMethod.get,
    summary: 'eMApps catalog',
    description:
        'Public eMApps service route. Lists published mini apps. Use the eMApps server address, not the CsAC RPC gateway.',
    params: [ApiDocParam(name: 'kw', description: 'Optional keyword search')],
    runnableInExplorer: false,
  ),
  ApiDocEndpoint(
    group: 'eMApps',
    route: '/emapps/public/info',
    method: ApiDocMethod.post,
    summary: 'eMApps package info',
    description:
        'Public eMApps service route. Returns latest version metadata, SHA-256 hash and RSA signature for one app.',
    params: [
      ApiDocParam(name: 'app_id', description: 'eMApp appId', required: true),
    ],
    runnableInExplorer: false,
  ),
  ApiDocEndpoint(
    group: 'eMApps',
    route: '/emapps/public/key',
    method: ApiDocMethod.get,
    summary: 'eMApps public key',
    description:
        'Public eMApps service route. Returns the RSA public key used by the client to verify packages.',
    runnableInExplorer: false,
  ),
  ApiDocEndpoint(
    group: 'eMApps',
    route: '/emapps/dl/{appId}',
    method: ApiDocMethod.get,
    summary: 'Download eMApp package',
    description:
        'Download route. Returns the signed package bytes for the latest version of an eMApp.',
    runnableInExplorer: false,
  ),
  ApiDocEndpoint(
    group: 'eMApps',
    route: '/emapps/api/pkg/upload',
    method: ApiDocMethod.post,
    summary: 'Developer package upload',
    description:
        'Developer eMApps route. Requires X-Dev-Token and multipart ZIP field pkg_file. Documented here only.',
    params: [
      ApiDocParam(name: 'app_id', description: 'eMApp appId', required: true),
      ApiDocParam(name: 'name', description: 'Display name', required: true),
      ApiDocParam(name: 'desc', description: 'Description'),
      ApiDocParam(name: 'pkg_file', description: 'ZIP package file'),
    ],
    runnableInExplorer: false,
  ),
  ApiDocEndpoint(
    group: 'eMApps',
    route: '/emapps/api/pkg/info',
    method: ApiDocMethod.post,
    summary: 'Developer package info',
    description:
        'Developer eMApps route. Requires X-Dev-Token and returns package metadata for the current developer.',
    params: [
      ApiDocParam(name: 'app_id', description: 'eMApp appId', required: true),
    ],
    runnableInExplorer: false,
  ),
  ApiDocEndpoint(
    group: 'eMApps',
    route: '/emapps/api/pkg/list',
    method: ApiDocMethod.post,
    summary: 'Developer package list',
    description:
        'Developer eMApps route. Requires X-Dev-Token and lists packages uploaded by the current developer.',
    runnableInExplorer: false,
  ),
  ApiDocEndpoint(
    group: 'eMApps',
    route: '/emapps/api/pkg/pubkey',
    method: ApiDocMethod.post,
    summary: 'Developer public key',
    description:
        'Developer eMApps route. Returns the same RSA public key as /emapps/public/key.',
    runnableInExplorer: false,
  ),
  ApiDocEndpoint(
    group: 'eMApps',
    route: '/emapps/internal/approve',
    method: ApiDocMethod.post,
    summary: 'Approve EMA callback',
    description:
        'Internal eMApps route. ACOP calls this after admin approval. Requires X-Bot-Secret.',
    params: [
      ApiDocParam(
        name: 'file_name',
        description: 'EMA file name',
        required: true,
      ),
      ApiDocParam(
        name: 'content',
        description: 'EMA JSON string',
        required: true,
      ),
      ApiDocParam(name: 'source_id', description: 'ACOP review source id'),
    ],
    runnableInExplorer: false,
  ),
  ApiDocEndpoint(
    group: 'eMApps',
    route: '/healthz',
    method: ApiDocMethod.get,
    summary: 'eMApps health check',
    description:
        'Health check route for the eMApps service. Use the eMApps server address.',
    runnableInExplorer: false,
  ),
  ApiDocEndpoint(
    group: 'Utility',
    route: 'utils/upload_image',
    method: ApiDocMethod.post,
    summary: 'Upload image',
    description:
        'Upload an image file. Multipart file upload is not supported by this debugger.',
    params: [
      ApiDocParam(name: 'image', description: 'Multipart file field name'),
    ],
  ),
  ApiDocEndpoint(
    group: 'Utility',
    route: 'utils/upload_voice',
    method: ApiDocMethod.post,
    summary: 'Upload voice',
    description:
        'Upload a voice file. Multipart file upload is not supported by this debugger.',
    params: [
      ApiDocParam(name: 'voice', description: 'Multipart file field name'),
    ],
  ),
  ApiDocEndpoint(
    group: 'Utility',
    route: 'utils/session_extend',
    method: ApiDocMethod.post,
    summary: 'Extend privileged session',
    description:
        'Activate temporary session extension with the server cache key. Internal/admin use only.',
    params: [
      ApiDocParam(name: 'key', description: 'Server cache key', required: true),
    ],
  ),
  ApiDocEndpoint(
    group: 'Utility',
    route: 'utils/session_reset',
    method: ApiDocMethod.post,
    summary: 'Reset session extension',
    description: 'Clear temporary session extension state.',
  ),
  ApiDocEndpoint(
    group: 'Utility',
    route: 'utils/session_info',
    method: ApiDocMethod.get,
    summary: 'Session extension info',
    description: 'Return whether temporary session extension is active.',
  ),
  ApiDocEndpoint(
    group: 'Feedback',
    route: 'bug_report',
    method: ApiDocMethod.post,
    summary: 'Bug report',
    description: 'Submit app feedback to administrators.',
    params: [
      ApiDocParam(name: 'title', description: 'Feedback title', required: true),
      ApiDocParam(
        name: 'description',
        description: 'Feedback description',
        required: true,
      ),
    ],
  ),
  ApiDocEndpoint(
    group: 'Utility',
    route: 'test',
    method: ApiDocMethod.get,
    summary: 'API health test',
    description: 'Simple API/database health check.',
  ),
];

class _UrlSchemeDocEntry {
  const _UrlSchemeDocEntry({
    required this.titleKey,
    required this.descriptionKey,
    required this.examples,
  });

  final String titleKey;
  final String descriptionKey;
  final List<String> examples;
}

const _urlSchemeDocEntries = <_UrlSchemeDocEntry>[
  _UrlSchemeDocEntry(
    titleKey: 'Open chat list',
    descriptionKey: 'Opens the main conversation list.',
    examples: [
      '$csacDeepLinkScheme://home',
      '$csacDeepLinkScheme://chats',
      '$csacDeepLinkScheme://chatlist',
    ],
  ),
  _UrlSchemeDocEntry(
    titleKey: 'Open space',
    descriptionKey: 'Opens the space and dynamic feed page.',
    examples: [
      '$csacDeepLinkScheme://space',
      '$csacDeepLinkScheme://discover',
      '$csacDeepLinkScheme://feed',
    ],
  ),
  _UrlSchemeDocEntry(
    titleKey: 'Open search',
    descriptionKey: 'Opens the global search page.',
    examples: ['$csacDeepLinkScheme://search'],
  ),
  _UrlSchemeDocEntry(
    titleKey: 'Open notices',
    descriptionKey: 'Opens the notifications page.',
    examples: ['$csacDeepLinkScheme://notices'],
  ),
  _UrlSchemeDocEntry(
    titleKey: 'Open eMApps',
    descriptionKey: 'Opens the eMApps catalog or a specific eMApp by appId.',
    examples: [
      '$csacDeepLinkScheme://emapps',
      '$csacDeepLinkScheme://emapp/com.csac.test',
      '$csacDeepLinkScheme://apps?app_id=com.csac.test',
    ],
  ),
  _UrlSchemeDocEntry(
    titleKey: 'Open profile and settings',
    descriptionKey: 'Opens the Me tab and settings area.',
    examples: [
      '$csacDeepLinkScheme://me',
      '$csacDeepLinkScheme://profile',
      '$csacDeepLinkScheme://settings',
    ],
  ),
  _UrlSchemeDocEntry(
    titleKey: 'Open user profile',
    descriptionKey: 'Replace {id} with the user UID.',
    examples: [
      '$csacDeepLinkScheme://profile/user/{id}',
      '$csacDeepLinkScheme://profile/{id}',
      '$csacDeepLinkScheme://u/{id}',
    ],
  ),
  _UrlSchemeDocEntry(
    titleKey: 'Open group chat',
    descriptionKey: 'Replace {id} with the group room ID.',
    examples: [
      '$csacDeepLinkScheme://chat/group/{id}',
      '$csacDeepLinkScheme://group/{id}',
      '$csacDeepLinkScheme://room/{id}',
    ],
  ),
  _UrlSchemeDocEntry(
    titleKey: 'Open private chat',
    descriptionKey: 'Replace {id} with the friend UID.',
    examples: [
      '$csacDeepLinkScheme://chat/private/{id}',
      '$csacDeepLinkScheme://private/{id}',
      '$csacDeepLinkScheme://friend/{id}',
      '$csacDeepLinkScheme://user/{id}',
    ],
  ),
  _UrlSchemeDocEntry(
    titleKey: 'Open chat with draft',
    descriptionKey:
        'Use draft to prefill the chat input. Add send=confirm to ask before sending.',
    examples: [
      '$csacDeepLinkScheme://chat/group/{id}?draft=hello',
      '$csacDeepLinkScheme://chat/private/{id}?draft=hello&send=confirm',
    ],
  ),
  _UrlSchemeDocEntry(
    titleKey: 'Open space post',
    descriptionKey: 'Replace {id} with the post ID.',
    examples: [
      '$csacDeepLinkScheme://space/post/{id}',
      '$csacDeepLinkScheme://post/{id}',
    ],
  ),
  _UrlSchemeDocEntry(
    titleKey: 'Open message',
    descriptionKey:
        'Replace {room} with the conversation ID and {message} with the message ID.',
    examples: [
      '$csacDeepLinkScheme://chat/group/{room}/message/{message}',
      '$csacDeepLinkScheme://chat/private/{room}/message/{message}',
      '$csacDeepLinkScheme://message/group/{room}/{message}',
      '$csacDeepLinkScheme://message/private/{room}/{message}',
    ],
  ),
  _UrlSchemeDocEntry(
    titleKey: 'Open search result',
    descriptionKey: 'Use q to open a search result query.',
    examples: ['$csacDeepLinkScheme://search?q=hello'],
  ),
];

class UrlSchemeDocsScreen extends StatelessWidget {
  const UrlSchemeDocsScreen({super.key});

  Future<void> copyUrl(BuildContext context, String value) async {
    final messenger = ScaffoldMessenger.of(context);
    final copiedText = context.strings.text('URL scheme example copied.');
    await Clipboard.setData(ClipboardData(text: value));
    if (context.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(copiedText)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(strings.text('URL scheme documentation'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.link_outlined, color: colors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$csacDeepLinkScheme://',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            strings.text(
                              'Use these links to open CsAC pages directly.',
                            ),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: strings.text('Copy'),
                      onPressed: () =>
                          copyUrl(context, '$csacDeepLinkScheme://home'),
                      icon: const Icon(Icons.copy),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: Row(
                      children: [
                        Icon(Icons.route_outlined, color: colors.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            strings.text('Supported URL scheme aliases'),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final entry in _urlSchemeDocEntries) ...[
                    const Divider(height: 1),
                    _UrlSchemeDocTile(entry: entry, onCopy: copyUrl),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: colors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        strings.text(
                          'Chat links require an existing logged-in session. If the conversation is not in local data, CsAC will refresh conversations before opening it.',
                        ),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UrlSchemeDocTile extends StatelessWidget {
  const _UrlSchemeDocTile({required this.entry, required this.onCopy});

  final _UrlSchemeDocEntry entry;
  final Future<void> Function(BuildContext context, String value) onCopy;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.text(entry.titleKey),
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  strings.text(entry.descriptionKey),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Column(
                  children: [
                    for (final example in entry.examples)
                      _UrlSchemeExampleRow(
                        example: example,
                        onCopy: () => onCopy(context, example),
                      ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: strings.text('Copy'),
            onPressed: () => onCopy(context, entry.examples.first),
            icon: const Icon(Icons.copy),
          ),
        ],
      ),
    );
  }
}

class _UrlSchemeExampleRow extends StatelessWidget {
  const _UrlSchemeExampleRow({required this.example, required this.onCopy});

  final String example;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onCopy,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
              children: [
                Icon(Icons.link, size: 18, color: colors.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    example,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: context.strings.text('Copy'),
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ApiExplorerScreen extends StatefulWidget {
  const ApiExplorerScreen({super.key, required this.state});

  final CsacAppState state;

  @override
  State<ApiExplorerScreen> createState() => _ApiExplorerScreenState();
}

class _ApiExplorerScreenState extends State<ApiExplorerScreen> {
  late final TextEditingController search;
  final route = TextEditingController();
  final paramControllers = <String, TextEditingController>{};
  ApiDocEndpoint selected = apiDocEndpoints.first;
  ApiDebugResponse? response;
  String? error;
  bool running = false;

  @override
  void initState() {
    super.initState();
    search = TextEditingController()..addListener(() => setState(() {}));
    applyEndpoint(selected, notify: false);
  }

  @override
  void dispose() {
    search.dispose();
    route.dispose();
    for (final controller in paramControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  List<ApiDocEndpoint> get filteredEndpoints {
    final query = search.text.trim().toLowerCase();
    if (query.isEmpty) {
      return apiDocEndpoints;
    }
    return apiDocEndpoints.where((endpoint) {
      return endpoint.route.toLowerCase().contains(query) ||
          endpoint.group.toLowerCase().contains(query) ||
          endpoint.summary.toLowerCase().contains(query) ||
          endpoint.description.toLowerCase().contains(query) ||
          endpoint.params.any(
            (param) =>
                param.name.toLowerCase().contains(query) ||
                param.description.toLowerCase().contains(query),
          );
    }).toList();
  }

  void selectEndpoint(ApiDocEndpoint endpoint) {
    applyEndpoint(endpoint);
  }

  void applyEndpoint(ApiDocEndpoint endpoint, {bool notify = true}) {
    selected = endpoint;
    route.text = endpoint.route;
    final existingValues = <String, String>{
      for (final entry in paramControllers.entries) entry.key: entry.value.text,
    };
    for (final controller in paramControllers.values) {
      controller.dispose();
    }
    paramControllers
      ..clear()
      ..addEntries(
        endpoint.params.map(
          (param) => MapEntry(
            param.name,
            TextEditingController(
              text: existingValues[param.name] ?? param.example,
            ),
          ),
        ),
      );
    response = null;
    error = null;
    if (notify && mounted) {
      setState(() {});
    }
  }

  Map<String, String> requestValues() {
    return <String, String>{
      for (final entry in paramControllers.entries)
        if (entry.value.text.trim().isNotEmpty)
          entry.key: entry.value.text.trim(),
    };
  }

  Future<void> runSelectedEndpoint() async {
    if (running) {
      return;
    }
    setState(() {
      running = true;
      error = null;
      response = null;
    });
    try {
      final result = await widget.state.runApiDebugRequest(
        method: selected.methodLabel,
        route: route.text.trim(),
        values: requestValues(),
      );
      if (mounted) {
        setState(() => response = result);
      }
    } catch (err) {
      if (mounted) {
        setState(() => error = err.toString());
      }
    } finally {
      if (mounted) {
        setState(() => running = false);
      }
    }
  }

  Future<void> copyResult() async {
    final text = response?.prettyBody ?? error ?? '';
    if (text.trim().isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.strings.text('Copied.'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = Theme.of(context).colorScheme;
    final endpoints = filteredEndpoints;
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.text('API explorer')),
        actions: [
          IconButton(
            tooltip: strings.text('Copy'),
            onPressed: response == null && error == null ? null : copyResult,
            icon: const Icon(Icons.copy),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 860;
            final list = _ApiEndpointList(
              search: search,
              endpoints: endpoints,
              selected: selected,
              onSelect: selectEndpoint,
            );
            final detail = _ApiEndpointDetail(
              endpoint: selected,
              route: route,
              paramControllers: paramControllers,
              running: running,
              response: response,
              error: error,
              onRun: runSelectedEndpoint,
              onCopy: copyResult,
            );
            if (wide) {
              return Row(
                children: [
                  SizedBox(width: 340, child: list),
                  VerticalDivider(width: 1, color: colors.outlineVariant),
                  Expanded(child: detail),
                ],
              );
            }
            return Column(
              children: [
                SizedBox(height: 260, child: list),
                Divider(height: 1, color: colors.outlineVariant),
                Expanded(child: detail),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ApiEndpointList extends StatelessWidget {
  const _ApiEndpointList({
    required this.search,
    required this.endpoints,
    required this.selected,
    required this.onSelect,
  });

  final TextEditingController search;
  final List<ApiDocEndpoint> endpoints;
  final ApiDocEndpoint selected;
  final ValueChanged<ApiDocEndpoint> onSelect;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: strings.text('Search API endpoints'),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: endpoints.isEmpty
              ? _EmptyPanel(message: strings.text('No matching API.'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  itemCount: endpoints.length,
                  itemBuilder: (context, index) {
                    final endpoint = endpoints[index];
                    final active =
                        endpoint.route == selected.route &&
                        endpoint.method == selected.method;
                    return Card(
                      elevation: 0,
                      color: active
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      child: ListTile(
                        dense: true,
                        leading: _ApiMethodBadge(method: endpoint.methodLabel),
                        title: Text(endpoint.route),
                        subtitle: Text(
                          '${endpoint.group} · ${endpoint.summary}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        selected: active,
                        onTap: () => onSelect(endpoint),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ApiEndpointDetail extends StatelessWidget {
  const _ApiEndpointDetail({
    required this.endpoint,
    required this.route,
    required this.paramControllers,
    required this.running,
    required this.response,
    required this.error,
    required this.onRun,
    required this.onCopy,
  });

  final ApiDocEndpoint endpoint;
  final TextEditingController route;
  final Map<String, TextEditingController> paramControllers;
  final bool running;
  final ApiDebugResponse? response;
  final String? error;
  final VoidCallback onRun;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _ApiMethodBadge(method: endpoint.methodLabel),
                    Chip(label: Text(endpoint.group)),
                  ],
                ),
                const SizedBox(height: 12),
                SelectableText(
                  endpoint.route,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  endpoint.summary,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  endpoint.description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (!endpoint.runnableInExplorer) ...[
                  const SizedBox(height: 8),
                  Chip(
                    avatar: const Icon(Icons.visibility_off_outlined, size: 18),
                    label: Text(strings.text('Documentation only')),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.text('Run online'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: route,
                  decoration: InputDecoration(
                    labelText: strings.text('Route'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                if (endpoint.params.isEmpty)
                  Text(
                    strings.text('No parameters.'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  )
                else
                  for (final param in endpoint.params) ...[
                    TextField(
                      controller: paramControllers[param.name],
                      decoration: InputDecoration(
                        labelText: '${param.name}${param.required ? ' *' : ''}',
                        helperText: param.description,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                OverflowBar(
                  alignment: MainAxisAlignment.end,
                  children: [
                    FilledButton.icon(
                      onPressed: running || !endpoint.runnableInExplorer
                          ? null
                          : onRun,
                      icon: running
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow),
                      label: Text(
                        strings.text(
                          endpoint.runnableInExplorer
                              ? 'Run request'
                              : 'Documentation only',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _ApiResultPanel(
              response: response,
              error: error,
              onCopy: onCopy,
            ),
          ),
        ),
      ],
    );
  }
}

class _ApiMethodBadge extends StatelessWidget {
  const _ApiMethodBadge({required this.method});

  final String method;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final post = method == 'POST';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: post ? colors.tertiaryContainer : colors.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          method,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: post
                ? colors.onTertiaryContainer
                : colors.onSecondaryContainer,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _ApiResultPanel extends StatelessWidget {
  const _ApiResultPanel({
    required this.response,
    required this.error,
    required this.onCopy,
  });

  final ApiDebugResponse? response;
  final String? error;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = Theme.of(context).colorScheme;
    final text =
        response?.prettyBody ?? error ?? strings.text('No response yet.');
    final hasResult = response != null || error != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                strings.text('Response'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (response != null)
              Chip(
                label: Text(
                  '${response!.statusCode} · ${response!.elapsedMs} ms',
                ),
              ),
            IconButton(
              tooltip: strings.text('Copy'),
              onPressed: hasResult ? onCopy : null,
              icon: const Icon(Icons.copy),
            ),
          ],
        ),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  height: 1.35,
                  color: error == null ? null : colors.error,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LicenseNotice {
  const _LicenseNotice({required this.packages, required this.body});

  final List<String> packages;
  final String body;

  String get title =>
      packages.isEmpty ? 'Unknown package' : packages.join(', ');
}

class _PinPromptDialog extends StatefulWidget {
  const _PinPromptDialog({
    required this.title,
    required this.label,
    required this.confirm,
  });

  final String title;
  final String label;
  final bool confirm;

  @override
  State<_PinPromptDialog> createState() => _PinPromptDialogState();
}

class _PinPromptDialogState extends State<_PinPromptDialog> {
  String pin = '';
  String pinConfirm = '';
  String? localError;
  bool confirming = false;

  String get activePin => confirming ? pinConfirm : pin;

  void updateActivePin(String value) {
    setState(() {
      if (confirming) {
        pinConfirm = value;
      } else {
        pin = value;
      }
      localError = null;
    });
    if (value.length >= 8) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && activePin.length >= 8) {
          submit();
        }
      });
    }
  }

  bool validateFirstPin() {
    if (AppLockPin.isValid(pin)) {
      return true;
    }
    setState(() {
      localError = context.strings.text('PIN must be 4-8 digits.');
    });
    return false;
  }

  void moveToConfirm() {
    if (!validateFirstPin()) {
      return;
    }
    setState(() {
      confirming = true;
      pinConfirm = '';
      localError = null;
    });
  }

  void submit() {
    if (widget.confirm && !confirming) {
      moveToConfirm();
      return;
    }
    if (!validateFirstPin()) {
      return;
    }
    if (widget.confirm && pin != pinConfirm) {
      setState(() {
        localError = context.strings.text('PINs do not match.');
        pinConfirm = '';
      });
      return;
    }
    Navigator.of(context).pop(pin);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final activeLabel = widget.confirm && confirming
        ? strings.text('Confirm PIN')
        : strings.text(widget.label);
    return AlertDialog(
      title: Text(strings.text(widget.title)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PinEntryPad(
              value: activePin,
              onChanged: updateActivePin,
              label: activeLabel,
              helperText: strings.text(
                widget.confirm && confirming ? 'Enter PIN again' : '4-8 digits',
              ),
            ),
            if (localError != null) ...[
              const SizedBox(height: 12),
              Text(
                localError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.text('Cancel')),
        ),
        if (widget.confirm && confirming)
          TextButton(
            onPressed: () {
              setState(() {
                confirming = false;
                pinConfirm = '';
                localError = null;
              });
            },
            child: Text(strings.text('Back')),
          ),
        FilledButton(
          onPressed: AppLockPin.isValid(activePin) ? submit : null,
          child: Text(
            strings.text(widget.confirm && !confirming ? 'Next' : 'Save'),
          ),
        ),
      ],
    );
  }
}

class _BugReportDraft {
  const _BugReportDraft({required this.title, required this.description});

  final String title;
  final String description;
}

class _BugReportDialog extends StatefulWidget {
  const _BugReportDialog();

  @override
  State<_BugReportDialog> createState() => _BugReportDialogState();
}

class _BugReportDialogState extends State<_BugReportDialog> {
  final title = TextEditingController();
  final description = TextEditingController();

  @override
  void initState() {
    super.initState();
    title.addListener(() => setState(() {}));
    description.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    super.dispose();
  }

  void submit() {
    Navigator.of(
      context,
    ).pop(_BugReportDraft(title: title.text, description: description.text));
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final canSubmit =
        title.text.trim().isNotEmpty && description.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(strings.text('Report a problem')),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: strings.text('Feedback title'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: description,
              minLines: 4,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: strings.text('Feedback description'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.text('Cancel')),
        ),
        FilledButton(
          onPressed: canSubmit ? submit : null,
          child: Text(strings.text('Submit feedback')),
        ),
      ],
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.state,
    this.initialDeveloperOptionsExpanded = false,
  });

  final CsacAppState state;
  final bool initialDeveloperOptionsExpanded;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsSectionTitle extends StatelessWidget {
  const _SettingsSectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _SettingsSubsectionTitle extends StatelessWidget {
  const _SettingsSubsectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: colors.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SettingsGroupCard extends StatelessWidget {
  const _SettingsGroupCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: _RoundedInkClip(child: Column(children: children)),
    );
  }
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController serverUrl;
  late final TextEditingController acopServerUrl;
  late final TextEditingController emAppsServerUrl;
  late final TextEditingController settingsSearch;
  late final ScrollController settingsScroll;
  final developerOptionsKey = GlobalKey();
  bool clearing = false;
  bool refreshing = false;
  bool savingServer = false;
  bool savingAcopServer = false;
  bool savingEmAppsServer = false;
  bool loadingPerformanceStats = false;
  bool clearingPerformanceCaches = false;
  bool enablingLowPerformanceMode = false;
  bool submittingBugReport = false;
  bool checkingVersionUpdate = false;
  PerformanceCacheStats? performanceStats;
  late bool developerOptionsExpanded;

  static const themeColorOptions = <_ThemeColorOption>[
    _ThemeColorOption('Emerald', Color(0xff1f8a70)),
    _ThemeColorOption('Blue', Color(0xff2563eb)),
    _ThemeColorOption('Violet', Color(0xff7c3aed)),
    _ThemeColorOption('Rose', Color(0xffe11d48)),
    _ThemeColorOption('Orange', Color(0xffea580c)),
    _ThemeColorOption('Teal', Color(0xff0f766e)),
    _ThemeColorOption('Indigo', Color(0xff4f46e5)),
    _ThemeColorOption('Slate', Color(0xff475569)),
  ];

  static const chatBubbleColorOptions = <_ThemeColorOption>[
    _ThemeColorOption('Emerald', Color(0xff1f8a70)),
    _ThemeColorOption('Blue', Color(0xff2563eb)),
    _ThemeColorOption('Teal', Color(0xff0f766e)),
    _ThemeColorOption('Indigo', Color(0xff4f46e5)),
    _ThemeColorOption('Violet', Color(0xff7c3aed)),
    _ThemeColorOption('Rose', Color(0xffe11d48)),
    _ThemeColorOption('Orange', Color(0xffea580c)),
    _ThemeColorOption('Slate', Color(0xff475569)),
    _ThemeColorOption('Mint', Color(0xff99f6e4)),
    _ThemeColorOption('Sky', Color(0xffbfdbfe)),
    _ThemeColorOption('Lavender', Color(0xffddd6fe)),
    _ThemeColorOption('Sand', Color(0xfffde68a)),
  ];

  @override
  void initState() {
    super.initState();
    settingsScroll = _desktopSmoothScrollController();
    serverUrl = TextEditingController(text: widget.state.preferences.serverUrl);
    acopServerUrl = TextEditingController(
      text: widget.state.preferences.acopServerUrl,
    );
    emAppsServerUrl = TextEditingController(
      text: widget.state.preferences.emAppsServerUrl,
    );
    settingsSearch = TextEditingController()..addListener(handleSearchChanged);
    widget.state.addListener(handleStateChanged);
    developerOptionsExpanded = widget.initialDeveloperOptionsExpanded;
    unawaited(loadPerformanceStats());
    if (developerOptionsExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = developerOptionsKey.currentContext;
        if (context == null) {
          return;
        }
        Scrollable.ensureVisible(
          context,
          duration: 360.ms,
          curve: Curves.easeOutCubic,
          alignment: 0.05,
        );
      });
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(handleStateChanged);
    settingsSearch.removeListener(handleSearchChanged);
    settingsSearch.dispose();
    serverUrl.dispose();
    acopServerUrl.dispose();
    emAppsServerUrl.dispose();
    settingsScroll.dispose();
    super.dispose();
  }

  void handleSearchChanged() {
    setState(() {});
  }

  void handleStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  bool settingMatches(String query, Iterable<String> keywords) {
    if (query.isEmpty) {
      return true;
    }
    final lowerQuery = query.toLowerCase();
    final strings = context.strings;
    return keywords.any((keyword) {
      final translated = strings.text(keyword).toLowerCase();
      return keyword.toLowerCase().contains(lowerQuery) ||
          translated.contains(lowerQuery);
    });
  }

  String get themeLabel {
    final strings = context.strings;
    switch (widget.state.preferences.themeMode) {
      case ThemeMode.system:
        return strings.text('System');
      case ThemeMode.light:
        return strings.text('Light');
      case ThemeMode.dark:
        return strings.text('Dark');
    }
  }

  String get languageLabel {
    return languageLabelFor(widget.state.preferences.language);
  }

  String get clientModeLabel {
    final strings = context.strings;
    switch (widget.state.preferences.clientMode) {
      case AppClientMode.csac:
        return strings.text('CsAC chat');
      case AppClientMode.acop:
        return strings.text('Developer platform');
    }
  }

  String languageLabelFor(CsacLanguage language) {
    switch (language) {
      case CsacLanguage.en:
        return 'English';
      case CsacLanguage.zh:
        return '中文';
      case CsacLanguage.zhTw:
        return '繁體中文';
      case CsacLanguage.ja:
        return '日本語';
      case CsacLanguage.ko:
        return '한국어';
      case CsacLanguage.es:
        return 'Español';
      case CsacLanguage.fr:
        return 'Français';
      case CsacLanguage.de:
        return 'Deutsch';
      case CsacLanguage.ru:
        return 'Русский';
      case CsacLanguage.ptBr:
        return 'Português (Brasil)';
      case CsacLanguage.vi:
        return 'Tiếng Việt';
      case CsacLanguage.id:
        return 'Bahasa Indonesia';
    }
  }

  String translationProgressSummary(TranslationProgress progress) {
    return context.strings.format('Translated {translated}/{total} strings', {
      'translated': progress.translated,
      'total': progress.total,
    });
  }

  Widget languageSubtitle() {
    final language = widget.state.preferences.language;
    return FutureBuilder<TranslationProgress>(
      future: translationProgressForLanguage(language),
      builder: (context, snapshot) {
        final progress = snapshot.data;
        if (progress == null) {
          return Text(languageLabel);
        }
        return Text(
          '$languageLabel · ${progress.percentLabel} · '
          '${translationProgressSummary(progress)}',
        );
      },
    );
  }

  String get fontStyleLabel {
    return fontStyleLabelFor(context, widget.state.preferences.fontStyle);
  }

  String get interfaceFontSizeLabel {
    final percent = (widget.state.preferences.interfaceFontScale * 100).round();
    return '$percent%';
  }

  String get themeColorLabel {
    final selected = themeColorOptions.firstWhere(
      (option) =>
          option.color.toARGB32() == widget.state.preferences.themeColorValue,
      orElse: () => themeColorOptions.first,
    );
    return context.strings.text(selected.label);
  }

  String get conversationSortLabel {
    final strings = context.strings;
    switch (widget.state.preferences.conversationSortMode) {
      case ConversationSortMode.latest:
        return strings.text('Latest message');
      case ConversationSortMode.type:
        return strings.text('Conversation type');
    }
  }

  String get conversationSubtitleModeLabel {
    final strings = context.strings;
    switch (widget.state.preferences.conversationSubtitleMode) {
      case ConversationSubtitleMode.recentMessage:
        return strings.text('Recent message');
      case ConversationSubtitleMode.status:
        return strings.text('Members and online status');
    }
  }

  String get groupMemberBadgeModeLabel {
    final strings = context.strings;
    switch (widget.state.preferences.groupMemberBadgeMode) {
      case GroupMemberBadgeMode.title:
        return strings.text('Member title');
      case GroupMemberBadgeMode.role:
        return strings.text('Member role');
    }
  }

  String get mobileEnterKeyBehaviorLabel {
    final strings = context.strings;
    switch (widget.state.preferences.mobileEnterKeyBehavior) {
      case MobileEnterKeyBehavior.send:
        return strings.text('Send');
      case MobileEnterKeyBehavior.newline:
        return strings.text('New line');
    }
  }

  String get messageTimeFormatLabel {
    return messageTimeFormatLabelFor(
      context,
      widget.state.preferences.messageTimeFormat,
    );
  }

  String get chatBubbleCornerStyleLabel {
    return chatBubbleCornerStyleLabelFor(
      context,
      widget.state.preferences.chatBubbleCornerStyle,
    );
  }

  String chatBubbleColorLabel(int colorValue) {
    if (colorValue == defaultChatBubbleColorValue) {
      return context.strings.text('Follow theme');
    }
    final selected = chatBubbleColorOptions.firstWhere(
      (option) => option.color.toARGB32() == colorValue,
      orElse: () => _ThemeColorOption('Custom', Color(colorValue)),
    );
    return context.strings.text(selected.label);
  }

  String get chatBubbleOpacityLabel {
    final percent = (widget.state.preferences.chatBubbleOpacity * 100).round();
    return '$percent%';
  }

  String get chatBackgroundLabel {
    return widget.state.preferences.chatBackgroundPath.trim().isEmpty
        ? context.strings.text('Default background')
        : context.strings.text('Custom background');
  }

  String formatCacheBytes(int bytes) {
    if (bytes <= 0) {
      return '0 B';
    }
    const units = <String>['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit += 1;
    }
    final decimals = value >= 10 || unit == 0 ? 0 : 1;
    return '${value.toStringAsFixed(decimals)} ${units[unit]}';
  }

  List<_CacheMetric> performanceMetrics(PerformanceCacheStats stats) {
    final strings = context.strings;
    return [
      _CacheMetric(
        icon: Icons.forum_outlined,
        label: strings.text('Message cache'),
        value: formatCacheBytes(stats.messageCacheBytes),
        detail: strings.format(
          '{messages} messages, {conversations} conversations',
          {
            'messages': stats.messageCount,
            'conversations': stats.conversationCount,
          },
        ),
      ),
      _CacheMetric(
        icon: Icons.image_outlined,
        label: strings.text('Image cache'),
        value: formatCacheBytes(stats.imageCacheBytes),
        detail: strings.format('{count} cached image entries', {
          'count': stats.imageCacheEntries,
        }),
      ),
      _CacheMetric(
        icon: Icons.article_outlined,
        label: strings.text('Log files'),
        value: formatCacheBytes(stats.logBytes),
        detail: strings.text('Local diagnostic files'),
      ),
    ];
  }

  Future<void> loadPerformanceStats({bool showError = false}) async {
    if (!mounted || loadingPerformanceStats) {
      return;
    }
    setState(() => loadingPerformanceStats = true);
    try {
      final stats = await widget.state.loadPerformanceCacheStats();
      if (mounted) {
        setState(() => performanceStats = stats);
      }
    } catch (err) {
      if (!mounted || !showError) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.strings.format('Load cache stats failed: {error}', {
              'error': err,
            }),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => loadingPerformanceStats = false);
      }
    }
  }

  Future<void> refreshAll() async {
    setState(() => refreshing = true);
    try {
      await widget.state.refreshHome();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.text('Refreshed.'))),
      );
    } catch (err) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.strings.format('Refresh failed: {error}', {'error': err}),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => refreshing = false);
      }
    }
  }

  Future<void> clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.strings.text('Clear local cache?')),
        content: Text(
          context.strings.text(
            'Cached conversations and message history on this device will be removed. Your login session will be kept.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.strings.text('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.strings.text('Clear')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => clearing = true);
    try {
      await widget.state.clearLocalCache();
      await loadPerformanceStats();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.text('Local cache cleared.'))),
      );
    } catch (err) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.strings.format('Clear cache failed: {error}', {
              'error': err,
            }),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => clearing = false);
      }
    }
  }

  Future<void> clearPerformanceCaches() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.strings.text('Clear performance caches?')),
        content: Text(
          context.strings.text(
            'Message cache, image cache and log files will be removed. Your login session will be kept.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.strings.text('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.strings.text('Clear')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => clearingPerformanceCaches = true);
    try {
      await widget.state.clearPerformanceCaches();
      await loadPerformanceStats();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.strings.text('Performance caches cleared.')),
        ),
      );
    } catch (err) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.strings.format('Clear cache failed: {error}', {
              'error': err,
            }),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => clearingPerformanceCaches = false);
      }
    }
  }

  Future<void> enableLowPerformanceMode() async {
    setState(() => enablingLowPerformanceMode = true);
    try {
      await widget.state.enableLowPerformanceMode();
      await loadPerformanceStats();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.strings.text('Low performance mode enabled.')),
        ),
      );
    } catch (err) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.strings.format('Save failed: {error}', {'error': err}),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => enablingLowPerformanceMode = false);
      }
    }
  }

  Future<void> submitBugReport() async {
    final result = await showDialog<_BugReportDraft>(
      context: context,
      builder: (context) => const _BugReportDialog(),
    );
    if (result == null || !mounted) {
      return;
    }
    if (result.title.trim().isEmpty || result.description.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.strings.text('Title and description are required.'),
          ),
        ),
      );
      return;
    }
    setState(() => submittingBugReport = true);
    try {
      await widget.state.submitBugReport(
        title: result.title,
        description: result.description,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.text('Feedback submitted.'))),
      );
    } catch (err) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.strings.format('Submit failed: {error}', {'error': err}),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => submittingBugReport = false);
      }
    }
  }

  Future<void> checkVersionUpdateManually() async {
    if (checkingVersionUpdate) {
      return;
    }
    setState(() => checkingVersionUpdate = true);
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final checker = VersionUpdateChecker();
      VersionUpdateInfo result;
      try {
        result = await checker.check(
          currentVersion: packageInfo.version.trim(),
          timeout: const Duration(seconds: 8),
        );
      } finally {
        checker.close();
      }
      if (!mounted) {
        return;
      }
      if (result.hasUpdate) {
        await showVersionUpdateDialog(context, result);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.strings.text('Already up to date.'))),
        );
      }
    } catch (err, stackTrace) {
      if (kDebugMode) {
        debugPrint('CsAC manual GitHub update check failed: $err');
        debugPrintStack(stackTrace: stackTrace);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.strings.format('Check update failed: {error}', {
                'error': err,
              }),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => checkingVersionUpdate = false);
      }
    }
  }

  Future<void> logoutToLogin() async {
    await confirmLogout(context, widget.state);
  }

  Future<String?> promptPin({
    required String title,
    required String label,
    bool confirm = false,
  }) async {
    return showDialog<String>(
      context: context,
      builder: (context) =>
          _PinPromptDialog(title: title, label: label, confirm: confirm),
    );
  }

  Future<bool> confirmCurrentAppLockPin() async {
    final pin = await promptPin(
      title: 'Enter current PIN',
      label: 'Current PIN',
    );
    if (pin == null) {
      return false;
    }
    if (widget.state.verifyAppLockPin(pin)) {
      return true;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.text('Incorrect PIN.'))),
      );
    }
    return false;
  }

  Future<void> enableAppLock() async {
    final pin = await promptPin(
      title: 'Set app lock PIN',
      label: 'PIN',
      confirm: true,
    );
    if (pin == null || !mounted) {
      return;
    }
    await widget.state.enableAppLock(pin: pin, biometricEnabled: false);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.text('App lock enabled.'))),
      );
    }
  }

  Future<void> changeAppLockPin() async {
    if (!await confirmCurrentAppLockPin() || !mounted) {
      return;
    }
    final pin = await promptPin(
      title: 'Change app lock PIN',
      label: 'New PIN',
      confirm: true,
    );
    if (pin == null || !mounted) {
      return;
    }
    await widget.state.enableAppLock(
      pin: pin,
      biometricEnabled: widget.state.preferences.appLockBiometricEnabled,
    );
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.text('PIN updated.'))),
      );
    }
  }

  Future<void> disableAppLock() async {
    if (!await confirmCurrentAppLockPin() || !mounted) {
      return;
    }
    await widget.state.disableAppLock();
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.text('App lock disabled.'))),
      );
    }
  }

  Future<void> openAppLockSettings() async {
    if (!widget.state.preferences.effectiveAppLockEnabled) {
      await enableAppLock();
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: _RoundedInkClip(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (supportsLocalAuth) ...[
                SwitchListTile(
                  secondary: const Icon(Icons.fingerprint),
                  title: Text(context.strings.text('Biometric unlock')),
                  subtitle: Text(
                    context.strings.text(
                      'Use device biometrics when available',
                    ),
                  ),
                  value: widget.state.preferences.appLockBiometricEnabled,
                  onChanged: (value) => Navigator.of(
                    context,
                  ).pop(value ? 'biometricOn' : 'biometricOff'),
                ),
                const Divider(height: 1),
              ],
              ListTile(
                leading: const Icon(Icons.pin_outlined),
                title: Text(context.strings.text('Change PIN')),
                onTap: () => Navigator.of(context).pop('changePin'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.lock_open_outlined),
                title: Text(context.strings.text('Disable app lock')),
                onTap: () => Navigator.of(context).pop('disable'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case 'biometricOn':
      case 'biometricOff':
        await widget.state.updateAppLockBiometric(action == 'biometricOn');
        if (mounted) {
          setState(() {});
        }
        break;
      case 'changePin':
        await changeAppLockPin();
        break;
      case 'disable':
        await disableAppLock();
        break;
    }
  }

  Future<void> saveServerUrl() async {
    setState(() => savingServer = true);
    try {
      final changed = await widget.state.updateServerUrl(serverUrl.text);
      if (!mounted) {
        return;
      }
      serverUrl.text = widget.state.preferences.serverUrl;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.strings.text(
              changed
                  ? 'Server address saved. Please log in again.'
                  : 'Server address is unchanged.',
            ),
          ),
        ),
      );
      setState(() {});
    } on FormatException {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.strings.text('Invalid server address.')),
        ),
      );
    } catch (err) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.strings.format('Save failed: {error}', {'error': err}),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => savingServer = false);
      }
    }
  }

  void resetServerUrl() {
    serverUrl.clear();
  }

  Future<void> saveAcopServerUrl() async {
    setState(() => savingAcopServer = true);
    try {
      final changed = await widget.state.updateAcopServerUrl(
        acopServerUrl.text,
      );
      if (!mounted) {
        return;
      }
      acopServerUrl.text = widget.state.preferences.acopServerUrl;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.strings.text(
              changed
                  ? 'ACOP server address saved. Please log in again.'
                  : 'Server address is unchanged.',
            ),
          ),
        ),
      );
      setState(() {});
    } on FormatException {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.strings.text('Invalid server address.')),
        ),
      );
    } catch (err) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.strings.format('Save failed: {error}', {'error': err}),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => savingAcopServer = false);
      }
    }
  }

  void resetAcopServerUrl() {
    acopServerUrl.clear();
  }

  Future<void> saveEmAppsServerUrl() async {
    setState(() => savingEmAppsServer = true);
    try {
      final changed = await widget.state.updateEmAppsServerUrl(
        emAppsServerUrl.text,
      );
      if (!mounted) {
        return;
      }
      emAppsServerUrl.text = widget.state.preferences.emAppsServerUrl;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.strings.text(
              changed
                  ? 'eMApps server address saved.'
                  : 'Server address is unchanged.',
            ),
          ),
        ),
      );
      setState(() {});
    } on FormatException {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.strings.text('Invalid server address.')),
        ),
      );
    } catch (err) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.strings.format('Save failed: {error}', {'error': err}),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => savingEmAppsServer = false);
      }
    }
  }

  void resetEmAppsServerUrl() {
    emAppsServerUrl.clear();
  }

  Future<void> chooseClientMode(AppClientMode mode) async {
    if (widget.state.preferences.clientMode == mode) {
      return;
    }
    await widget.state.switchClientMode(mode);
    if (!mounted) {
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> chooseTheme() async {
    final selected = await showModalBottomSheet<ThemeMode>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: _RoundedInkClip(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: widget.state.preferences.themeMode == ThemeMode.system
                    ? const Icon(Icons.check)
                    : const SizedBox(width: 24),
                title: Text(context.strings.text('System')),
                onTap: () => Navigator.of(context).pop(ThemeMode.system),
              ),
              ListTile(
                leading: widget.state.preferences.themeMode == ThemeMode.light
                    ? const Icon(Icons.check)
                    : const SizedBox(width: 24),
                title: Text(context.strings.text('Light')),
                onTap: () => Navigator.of(context).pop(ThemeMode.light),
              ),
              ListTile(
                leading: widget.state.preferences.themeMode == ThemeMode.dark
                    ? const Icon(Icons.check)
                    : const SizedBox(width: 24),
                title: Text(context.strings.text('Dark')),
                onTap: () => Navigator.of(context).pop(ThemeMode.dark),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      await widget.state.updateThemeMode(selected);
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> chooseThemeColor() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: _RoundedInkClip(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.strings.text('Theme color'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final option in themeColorOptions)
                        _ThemeColorButton(
                          option: option,
                          selected:
                              option.color.toARGB32() ==
                              widget.state.preferences.themeColorValue,
                          onTap: () => Navigator.of(
                            context,
                          ).pop(option.color.toARGB32()),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (selected != null) {
      await widget.state.updateThemeColor(selected);
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> chooseLanguage() async {
    final strings = context.strings;
    final selected = await showModalBottomSheet<CsacLanguage>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final maxHeight = MediaQuery.sizeOf(context).height * 0.82;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: _RoundedInkClip(
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        strings.text('Translation progress'),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  for (final language in CsacLanguage.values)
                    _LanguageOptionTile(
                      label: languageLabelFor(language),
                      selected: widget.state.preferences.language == language,
                      progress: translationProgressForLanguage(language),
                      summaryBuilder: translationProgressSummary,
                      onTap: () => Navigator.of(context).pop(language),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (selected != null) {
      await widget.state.updateLanguage(selected);
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> chooseFontStyle() async {
    final selected = await showModalBottomSheet<CsacFontStyle>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: _RoundedInkClip(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final style in CsacFontStyle.values)
                ListTile(
                  leading: widget.state.preferences.fontStyle == style
                      ? const Icon(Icons.check)
                      : const SizedBox(width: 24),
                  title: Text(
                    fontStyleLabelFor(context, style),
                    style: TextStyle(
                      fontFamily: fontFamilyForStyle(style),
                      fontFamilyFallback: fontFamilyFallbackForStyle(style),
                    ),
                  ),
                  subtitle: Text(
                    fontStyleDescriptionFor(context, style),
                    style: TextStyle(
                      fontFamily: fontFamilyForStyle(style),
                      fontFamilyFallback: fontFamilyFallbackForStyle(style),
                    ),
                  ),
                  onTap: () => Navigator.of(context).pop(style),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      await widget.state.updateFontStyle(selected);
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> chooseConversationSortMode() async {
    final selected = await showModalBottomSheet<ConversationSortMode>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: _RoundedInkClip(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading:
                    widget.state.preferences.conversationSortMode ==
                        ConversationSortMode.latest
                    ? const Icon(Icons.check)
                    : const SizedBox(width: 24),
                title: Text(context.strings.text('Latest message')),
                subtitle: Text(
                  context.strings.text('Show chats with recent activity first'),
                ),
                onTap: () =>
                    Navigator.of(context).pop(ConversationSortMode.latest),
              ),
              ListTile(
                leading:
                    widget.state.preferences.conversationSortMode ==
                        ConversationSortMode.type
                    ? const Icon(Icons.check)
                    : const SizedBox(width: 24),
                title: Text(context.strings.text('Conversation type')),
                subtitle: Text(
                  context.strings.text('Group friends and groups separately'),
                ),
                onTap: () =>
                    Navigator.of(context).pop(ConversationSortMode.type),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      await widget.state.updateConversationSortMode(selected);
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> chooseConversationSubtitleMode() async {
    final selected = await showModalBottomSheet<ConversationSubtitleMode>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: _RoundedInkClip(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading:
                    widget.state.preferences.conversationSubtitleMode ==
                        ConversationSubtitleMode.recentMessage
                    ? const Icon(Icons.check)
                    : const SizedBox(width: 24),
                title: Text(context.strings.text('Recent message')),
                subtitle: Text(
                  context.strings.text(
                    'Show the latest message in each chat row',
                  ),
                ),
                onTap: () => Navigator.of(
                  context,
                ).pop(ConversationSubtitleMode.recentMessage),
              ),
              ListTile(
                leading:
                    widget.state.preferences.conversationSubtitleMode ==
                        ConversationSubtitleMode.status
                    ? const Icon(Icons.check)
                    : const SizedBox(width: 24),
                title: Text(context.strings.text('Members and online status')),
                subtitle: Text(
                  context.strings.text(
                    'Show group member count and online status',
                  ),
                ),
                onTap: () =>
                    Navigator.of(context).pop(ConversationSubtitleMode.status),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      await widget.state.updateConversationSubtitleMode(selected);
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> chooseGroupMemberBadgeMode() async {
    final selected = await showModalBottomSheet<GroupMemberBadgeMode>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: _RoundedInkClip(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading:
                    widget.state.preferences.groupMemberBadgeMode ==
                        GroupMemberBadgeMode.title
                    ? const Icon(Icons.check)
                    : const SizedBox(width: 24),
                title: Text(context.strings.text('Member title')),
                subtitle: Text(
                  context.strings.text('Display group titles set by admins'),
                ),
                onTap: () =>
                    Navigator.of(context).pop(GroupMemberBadgeMode.title),
              ),
              ListTile(
                leading:
                    widget.state.preferences.groupMemberBadgeMode ==
                        GroupMemberBadgeMode.role
                    ? const Icon(Icons.check)
                    : const SizedBox(width: 24),
                title: Text(context.strings.text('Member role')),
                subtitle: Text(
                  context.strings.text('Display owner/admin/member role'),
                ),
                onTap: () =>
                    Navigator.of(context).pop(GroupMemberBadgeMode.role),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      await widget.state.updateGroupMemberBadgeMode(selected);
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> chooseMobileEnterKeyBehavior() async {
    final selected = await showModalBottomSheet<MobileEnterKeyBehavior>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: _RoundedInkClip(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final behavior in MobileEnterKeyBehavior.values)
                ListTile(
                  leading:
                      widget.state.preferences.mobileEnterKeyBehavior ==
                          behavior
                      ? const Icon(Icons.check)
                      : const SizedBox(width: 24),
                  title: Text(
                    context.strings.text(
                      behavior == MobileEnterKeyBehavior.send
                          ? 'Send'
                          : 'New line',
                    ),
                  ),
                  subtitle: Text(
                    context.strings.text(
                      behavior == MobileEnterKeyBehavior.send
                          ? 'The keyboard confirmation key sends the message'
                          : 'The keyboard confirmation key inserts a new line',
                    ),
                  ),
                  onTap: () => Navigator.of(context).pop(behavior),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      await widget.state.updateMobileEnterKeyBehavior(selected);
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> chooseMessageTimeFormat() async {
    final selected = await showModalBottomSheet<MessageTimeFormat>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: _RoundedInkClip(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final format in MessageTimeFormat.values)
                ListTile(
                  leading: widget.state.preferences.messageTimeFormat == format
                      ? const Icon(Icons.check)
                      : const SizedBox(width: 24),
                  title: Text(messageTimeFormatLabelFor(context, format)),
                  subtitle: Text(messageTimeFormatExampleFor(format)),
                  onTap: () => Navigator.of(context).pop(format),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      await widget.state.updateMessageTimeFormat(selected);
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> chooseChatBubbleCornerStyle() async {
    final selected = await showModalBottomSheet<ChatBubbleCornerStyle>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: _RoundedInkClip(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final style in ChatBubbleCornerStyle.values)
                ListTile(
                  leading:
                      widget.state.preferences.chatBubbleCornerStyle == style
                      ? const Icon(Icons.check)
                      : const SizedBox(width: 24),
                  title: Text(chatBubbleCornerStyleLabelFor(context, style)),
                  onTap: () => Navigator.of(context).pop(style),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      await widget.state.updateChatBubbleCornerStyle(selected);
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> chooseChatBubbleColor({required bool mine}) async {
    final title = mine ? 'Own bubble color' : 'Other bubble color';
    final current = mine
        ? widget.state.preferences.ownChatBubbleColorValue
        : widget.state.preferences.otherChatBubbleColorValue;
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: _RoundedInkClip(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.strings.text(title),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _FollowThemeColorButton(
                        selected: current == defaultChatBubbleColorValue,
                        onTap: () => Navigator.of(
                          context,
                        ).pop(defaultChatBubbleColorValue),
                      ),
                      for (final option in chatBubbleColorOptions)
                        _ThemeColorButton(
                          option: option,
                          selected: option.color.toARGB32() == current,
                          onTap: () => Navigator.of(
                            context,
                          ).pop(option.color.toARGB32()),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (selected != null) {
      if (mine) {
        await widget.state.updateOwnChatBubbleColor(selected);
      } else {
        await widget.state.updateOtherChatBubbleColor(selected);
      }
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> updateChatBubbleOpacity(double value) async {
    await widget.state.updateChatBubbleOpacity(value);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> updateInterfaceFontScale(double value) async {
    await widget.state.updateInterfaceFontScale(value);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> chooseChatBackground() async {
    final strings = context.strings;
    if (isWebPlatform) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings.text('Chat background files are not supported on Web.'),
          ),
        ),
      );
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: _RoundedInkClip(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: Text(context.strings.text('Choose background image')),
                onTap: () => Navigator.of(context).pop('choose'),
              ),
              if (widget.state.preferences.chatBackgroundPath.trim().isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: Text(context.strings.text('Reset background')),
                  onTap: () => Navigator.of(context).pop('reset'),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) {
      return;
    }
    if (action == 'reset') {
      await widget.state.updateChatBackgroundPath('');
      if (mounted) {
        setState(() {});
      }
      return;
    }
    try {
      final picked = isMobilePlatform
          ? await pickImageForMobileGallery()
          : await openFile(
              acceptedTypeGroups: <XTypeGroup>[
                XTypeGroup(
                  label: strings.text('Images'),
                  extensions: imageExtensions,
                ),
              ],
            );
      if (!mounted || picked == null) {
        return;
      }
      final path = await persistChatBackground(picked);
      await widget.state.updateChatBackgroundPath(path);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.strings.text('Chat background saved.')),
          ),
        );
      }
    } catch (err) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyMobileFileError(
              strings,
              err,
              fallbackKey: 'Save failed: {error}',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.state.user;
    final strings = context.strings;
    final query = settingsSearch.text.trim().toLowerCase();
    final hasSearchQuery = query.isNotEmpty;
    final colors = Theme.of(context).colorScheme;
    final showAccount = settingMatches(query, [
      'Account settings',
      'Username',
      'Nickname',
      'Avatar',
      'UID',
      'Profile',
    ]);
    final showInfo = settingMatches(query, [
      'App information',
      'Open-source licenses',
      'Version',
      if (supportsVersionUpdateChecks) ...[
        'Version updates',
        'Check for updates',
        'Automatic update checks',
        'Release notes',
      ],
      'Source code',
      'License',
    ]);
    final showFeedback = settingMatches(query, [
      'Feedback',
      'Report a problem',
      'Bug report',
      'Problem',
      'Submit feedback',
    ]);
    final showAppearance = settingMatches(query, [
      'Theme',
      'Theme color',
      'Language',
      'Font style',
      'Font size',
      'Text size',
      'Font',
      'Typography',
      'Compact mode',
      'Display density',
      'Spacing',
      'High contrast mode',
      'High contrast',
      'Contrast',
      'Conversation sorting',
      'Conversation subtitle',
      'Recent message',
      'Members and online status',
      'Message time format',
      'Chat bubble theme',
      'Own bubble color',
      'Other bubble color',
      'Bubble corner style',
      'Bubble opacity',
      'Chat background',
      'Background',
      'Show chat avatars',
      'Avatar',
      'Double tap avatar pat',
      'Pat',
      'Quick input triggers',
      'Quick activation',
      '@',
      '#',
      'Keyboard confirmation key',
      'Send',
      'New line',
      'Group badge content',
      'Member title',
      'Member role',
      'Level',
      'Reduce motion',
      'Animation',
      'Motion',
    ]);
    final showLock = settingMatches(query, ['App lock', 'PIN', 'Security']);
    final showData = settingMatches(query, [
      'Refresh app data',
      'Connection diagnostics',
      'Network diagnostics',
      'HTTP protocol',
      'HTTP/1.1',
      'HTTP/2',
      'Server latency',
      'API availability',
      'Login status',
      'Image domain',
      'Clear local cache',
      'Performance and cache',
      'Message cache',
      'Image cache',
      'Log files',
      'App logs',
      'View app logs',
      'Diagnostics',
      'System notifications',
      'Local notifications',
      'New message alerts',
      'Low performance mode',
      'Cache',
      'Cached conversations and message history',
    ]);
    final showDeveloper = settingMatches(query, [
      'Developer options',
      'Client mode',
      'CsAC chat',
      'Developer platform',
      'Force desktop window to mobile width',
      'Lock the desktop window to a mobile-style width',
      'Mobile width',
      'Mobile-style width',
      'Desktop window',
      'CsAC server address',
      'ACOP server address',
      'HTTP protocol',
      'HTTP/1.1',
      'HTTP/2',
      'API explorer',
      'API documentation',
      'URL scheme documentation',
      'Supported URL scheme aliases',
      'Run online',
      'Endpoint',
      'Route',
      'Server',
      'Default server',
    ]);
    final showLogout = settingMatches(query, [
      'Logout',
      'Clear session and return to login',
      'Session',
    ]);
    final hasMatches =
        showAccount ||
        showInfo ||
        showFeedback ||
        showAppearance ||
        showLock ||
        showData ||
        showDeveloper ||
        showLogout;
    return Scaffold(
      appBar: AppBar(title: Text(strings.text('Settings'))),
      body: SafeArea(
        child: ListView(
          controller: settingsScroll,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            TextField(
              controller: settingsSearch,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: strings.text('Search settings'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: strings.text('Clear'),
                        onPressed: settingsSearch.clear,
                        icon: const Icon(Icons.close),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              child: _RoundedInkClip(
                child: ListTile(
                  leading: _Avatar(
                    url: widget.state.currentUserAvatar,
                    fallback: Icons.person_rounded,
                  ),
                  title: Text(user?.nickname ?? strings.text('Not logged in')),
                  subtitle: Text(
                    [
                      if (user?.username.isNotEmpty == true)
                        '@${user!.username}',
                      if (user != null) 'UID ${user.uid}',
                    ].join(' | '),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: user == null
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  AccountSettingsScreen(state: widget.state),
                            ),
                          );
                        },
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  selected: hasSearchQuery && showAppearance,
                  onSelected: (_) => settingsSearch.text = 'Theme',
                  label: Text(strings.text('Appearance')),
                ),
                FilterChip(
                  selected: hasSearchQuery && showData,
                  onSelected: (_) => settingsSearch.text = 'Refresh app data',
                  label: Text(strings.text('Data')),
                ),
                FilterChip(
                  selected: hasSearchQuery && showDeveloper,
                  onSelected: (_) => settingsSearch.text = 'Developer options',
                  label: Text(strings.text('Developer')),
                ),
                FilterChip(
                  selected: hasSearchQuery && showInfo,
                  onSelected: (_) => settingsSearch.text = 'App information',
                  label: Text(strings.text('About')),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (showAccount) ...[
              _SettingsSectionTitle(strings.text('Account')),
              Card(
                elevation: 0,
                child: _RoundedInkClip(
                  child: ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(strings.text('Account settings')),
                    subtitle: Text(
                      user == null
                          ? strings.text('Not logged in')
                          : '${user.nickname} · UID ${user.uid}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: user == null
                        ? null
                        : () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    AccountSettingsScreen(state: widget.state),
                              ),
                            );
                          },
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (showInfo) ...[
              _SettingsSectionTitle(strings.text('About')),
              Card(
                elevation: 0,
                child: _RoundedInkClip(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.info_outline),
                        title: Text(strings.text('App information')),
                        subtitle: const _AppInfoSubtitle(),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const AppInfoScreen(),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      if (supportsVersionUpdateChecks) ...[
                        SwitchListTile(
                          secondary: const Icon(Icons.event_repeat_outlined),
                          title: Text(strings.text('Automatic update checks')),
                          subtitle: Text(
                            strings.text(
                              'Silently check GitHub Releases once on startup',
                            ),
                          ),
                          value:
                              widget.state.preferences.autoCheckVersionUpdates,
                          onChanged: widget.state.updateAutoCheckVersionUpdates,
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.update),
                          title: Text(strings.text('Check for updates')),
                          subtitle: Text(
                            strings.text(
                              'Check the latest GitHub Release manually',
                            ),
                          ),
                          trailing: checkingVersionUpdate
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.chevron_right),
                          onTap: checkingVersionUpdate
                              ? null
                              : checkVersionUpdateManually,
                        ),
                        const Divider(height: 1),
                      ],
                      ListTile(
                        leading: const Icon(Icons.article_outlined),
                        title: Text(strings.text('Open-source licenses')),
                        subtitle: Text(
                          strings.text('View licenses for included libraries'),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const OpenSourceLicensesScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (showFeedback) ...[
              _SettingsSectionTitle(strings.text('Feedback')),
              Card(
                elevation: 0,
                child: _RoundedInkClip(
                  child: ListTile(
                    leading: const Icon(Icons.feedback_outlined),
                    title: Text(strings.text('Report a problem')),
                    subtitle: Text(
                      strings.text('Send app feedback to administrators'),
                    ),
                    trailing: submittingBugReport
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: submittingBugReport ? null : submitBugReport,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (showAppearance) ...[
              _SettingsSectionTitle(strings.text('Appearance')),
              _SettingsSubsectionTitle(strings.text('Theme')),
              _SettingsGroupCard(
                children: [
                  ListTile(
                    leading: const Icon(Icons.dark_mode_outlined),
                    title: Text(strings.text('Theme')),
                    subtitle: Text(themeLabel),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: chooseTheme,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.palette_outlined),
                    title: Text(strings.text('Theme color')),
                    subtitle: Text(themeColorLabel),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ThemeColorDot(
                          color: Color(
                            widget.state.preferences.themeColorValue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: chooseThemeColor,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.translate),
                    title: Text(strings.text('Language')),
                    subtitle: languageSubtitle(),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: chooseLanguage,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.text_fields),
                    title: Text(strings.text('Font style')),
                    subtitle: Text(fontStyleLabel),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: chooseFontStyle,
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Row(
                      children: [
                        const Icon(Icons.format_size),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(strings.text('Font size')),
                              Text(
                                interfaceFontSizeLabel,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                              Slider(
                                value:
                                    widget.state.preferences.interfaceFontScale,
                                min: minInterfaceFontScale,
                                max: maxInterfaceFontScale,
                                divisions: 9,
                                label: interfaceFontSizeLabel,
                                onChanged: updateInterfaceFontScale,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.format_line_spacing),
                    title: Text(strings.text('Compact mode')),
                    subtitle: Text(
                      strings.text('Reduce spacing in lists and controls'),
                    ),
                    value: widget.state.preferences.compactMode,
                    onChanged: widget.state.updateCompactMode,
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.contrast),
                    title: Text(strings.text('High contrast mode')),
                    subtitle: Text(
                      strings.text('Use stronger contrast colors and outlines'),
                    ),
                    value: widget.state.preferences.highContrastMode,
                    onChanged: widget.state.updateHighContrastMode,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SettingsSubsectionTitle(strings.text('Chats')),
              _SettingsGroupCard(
                children: [
                  ListTile(
                    leading: const Icon(Icons.sort),
                    title: Text(strings.text('Conversation sorting')),
                    subtitle: Text(conversationSortLabel),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: chooseConversationSortMode,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.subject_outlined),
                    title: Text(strings.text('Conversation subtitle')),
                    subtitle: Text(conversationSubtitleModeLabel),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: chooseConversationSubtitleMode,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.schedule_outlined),
                    title: Text(strings.text('Message time format')),
                    subtitle: Text(messageTimeFormatLabel),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: chooseMessageTimeFormat,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SettingsSubsectionTitle(strings.text('Chat bubble theme')),
              _SettingsGroupCard(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                    child: _ChatBubbleThemePreview(
                      preferences: widget.state.preferences,
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.chat_bubble_outline),
                    title: Text(strings.text('Own bubble color')),
                    subtitle: Text(
                      chatBubbleColorLabel(
                        widget.state.preferences.ownChatBubbleColorValue,
                      ),
                    ),
                    trailing: _ChatBubbleColorTrailing(
                      colorValue:
                          widget.state.preferences.ownChatBubbleColorValue,
                      fallback: Theme.of(context).colorScheme.primaryContainer,
                    ),
                    onTap: () => chooseChatBubbleColor(mine: true),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.chat_bubble_outline),
                    title: Text(strings.text('Other bubble color')),
                    subtitle: Text(
                      chatBubbleColorLabel(
                        widget.state.preferences.otherChatBubbleColorValue,
                      ),
                    ),
                    trailing: _ChatBubbleColorTrailing(
                      colorValue:
                          widget.state.preferences.otherChatBubbleColorValue,
                      fallback: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                    ),
                    onTap: () => chooseChatBubbleColor(mine: false),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.rounded_corner),
                    title: Text(strings.text('Bubble corner style')),
                    subtitle: Text(chatBubbleCornerStyleLabel),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: chooseChatBubbleCornerStyle,
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Row(
                      children: [
                        const Icon(Icons.opacity),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(strings.text('Bubble opacity')),
                              Text(
                                chatBubbleOpacityLabel,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                              Slider(
                                value:
                                    widget.state.preferences.chatBubbleOpacity,
                                min: 0.45,
                                max: 1,
                                divisions: 11,
                                label: chatBubbleOpacityLabel,
                                onChanged: updateChatBubbleOpacity,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.wallpaper_outlined),
                    title: Text(strings.text('Chat background')),
                    subtitle: Text(chatBackgroundLabel),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: chooseChatBackground,
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.account_circle_outlined),
                    title: Text(strings.text('Show chat avatars')),
                    subtitle: Text(
                      strings.text(
                        'Display sender avatars beside message bubbles',
                      ),
                    ),
                    value: widget.state.preferences.showChatAvatars,
                    onChanged: widget.state.updateShowChatAvatars,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SettingsSubsectionTitle(strings.text('Input and interaction')),
              _SettingsGroupCard(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.waving_hand_outlined),
                    title: Text(strings.text('Double tap avatar pat')),
                    subtitle: Text(
                      strings.text(
                        'Double tap a group member avatar to send a pat',
                      ),
                    ),
                    value: widget.state.preferences.enablePat,
                    onChanged: widget.state.updateEnablePat,
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.bolt_outlined),
                    title: Text(strings.text('Quick input triggers')),
                    subtitle: Text(
                      strings.text(
                        'Automatically open pickers after typing @ or #',
                      ),
                    ),
                    value: widget.state.preferences.enableQuickInputTriggers,
                    onChanged: widget.state.updateEnableQuickInputTriggers,
                  ),
                  if (isMobilePlatform) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.keyboard_return_outlined),
                      title: Text(strings.text('Keyboard confirmation key')),
                      subtitle: Text(mobileEnterKeyBehaviorLabel),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: chooseMobileEnterKeyBehavior,
                    ),
                  ],
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.badge_outlined),
                    title: Text(strings.text('Group badge content')),
                    subtitle: Text(groupMemberBadgeModeLabel),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: chooseGroupMemberBadgeMode,
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.motion_photos_off_outlined),
                    title: Text(strings.text('Reduce motion')),
                    subtitle: Text(
                      strings.text(
                        'Use simpler transitions and fewer decorative animations',
                      ),
                    ),
                    value: widget.state.preferences.reduceMotion,
                    onChanged: widget.state.updateReduceMotion,
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (showLock) ...[
              _SettingsSectionTitle(strings.text('Security')),
              Card(
                elevation: 0,
                child: _RoundedInkClip(
                  child: ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: Text(strings.text('App lock')),
                    subtitle: Text(
                      widget.state.preferences.effectiveAppLockEnabled
                          ? strings.text('PIN required when returning to CsAC')
                          : strings.text('Off'),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: openAppLockSettings,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (showData) ...[
              _SettingsSectionTitle(strings.text('Data')),
              _SettingsSubsectionTitle(strings.text('Performance and cache')),
              _SettingsGroupCard(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                    child: Row(
                      children: [
                        Icon(
                          Icons.speed_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                strings.text('Performance and cache'),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                performanceStats == null
                                    ? strings.text(
                                        'Measure local storage and memory cache',
                                      )
                                    : strings.format('Total cache: {size}', {
                                        'size': formatCacheBytes(
                                          performanceStats!.totalBytes,
                                        ),
                                      }),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: strings.text('Refresh'),
                          onPressed: loadingPerformanceStats
                              ? null
                              : () => loadPerformanceStats(showError: true),
                          icon: loadingPerformanceStats
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                  ),
                  if (performanceStats == null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: LinearProgressIndicator(
                        minHeight: 2,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final metric in performanceMetrics(
                            performanceStats!,
                          ))
                            _CacheMetricTile(metric: metric),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OutlinedButton.icon(
                          onPressed: enablingLowPerformanceMode
                              ? null
                              : enableLowPerformanceMode,
                          icon: enablingLowPerformanceMode
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.battery_saver_outlined),
                          label: Text(strings.text('Low performance mode')),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: clearingPerformanceCaches
                              ? null
                              : clearPerformanceCaches,
                          icon: clearingPerformanceCaches
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.auto_delete_outlined),
                          label: Text(strings.text('Clear performance caches')),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SettingsSubsectionTitle(strings.text('Refresh app data')),
              _SettingsGroupCard(
                children: [
                  ListTile(
                    leading: const Icon(Icons.sync),
                    title: Text(strings.text('Refresh app data')),
                    subtitle: Text(
                      strings.text('Reload conversations and counters'),
                    ),
                    trailing: refreshing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: refreshing ? null : refreshAll,
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.notifications_active_outlined),
                    title: Text(strings.text('System notifications')),
                    subtitle: Text(
                      strings.text('Show local system alerts for new messages'),
                    ),
                    value: widget
                        .state
                        .preferences
                        .localSystemNotificationsEnabled,
                    onChanged: widget.state.updateLocalSystemNotifications,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SettingsSubsectionTitle(strings.text('Connection diagnostics')),
              _SettingsGroupCard(
                children: [
                  ListTile(
                    leading: const Icon(Icons.network_check_outlined),
                    title: Text(strings.text('Connection diagnostics')),
                    subtitle: Text(
                      strings.text(
                        'Test server latency, API, login and image domain',
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              NetworkDiagnosticsScreen(state: widget.state),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.http_outlined),
                    title: Text(strings.text('HTTP protocol')),
                    subtitle: Text(strings.text('Last API request protocol')),
                    trailing: Text(
                      localizedApiHttpProtocolLabel(
                        context,
                        widget.state.activeHttpProtocol,
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.article_outlined),
                    title: Text(strings.text('App logs')),
                    subtitle: Text(strings.text('View local diagnostic logs')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => AppLogsScreen(state: widget.state),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.cleaning_services_outlined),
                    title: Text(strings.text('Clear local cache')),
                    subtitle: Text(
                      strings.text(
                        'Remove cached conversations and message history',
                      ),
                    ),
                    trailing: clearing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: clearing ? null : clearCache,
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (showDeveloper) ...[
              _SettingsSectionTitle(strings.text('Developer')),
              Card(
                key: developerOptionsKey,
                elevation: 0,
                child: _RoundedInkClip(
                  child: ExpansionTile(
                    initiallyExpanded: developerOptionsExpanded,
                    onExpansionChanged: (value) {
                      setState(() => developerOptionsExpanded = value);
                    },
                    leading: const Icon(Icons.developer_mode_outlined),
                    title: Text(strings.text('Developer options')),
                    subtitle: Text(
                      [
                        clientModeLabel,
                        strings.format('Current server: {server}', {
                          'server':
                              widget.state.preferences.serverUrl.trim().isEmpty
                              ? strings.text('Default server')
                              : widget.state.preferences.serverUrl.trim(),
                        }),
                      ].join(' · '),
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          strings.text('Client mode'),
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<AppClientMode>(
                          segments: [
                            ButtonSegment(
                              value: AppClientMode.csac,
                              icon: const Icon(Icons.forum_outlined),
                              label: Text(strings.text('CsAC chat')),
                            ),
                            ButtonSegment(
                              value: AppClientMode.acop,
                              icon: const Icon(
                                Icons.integration_instructions_outlined,
                              ),
                              label: Text(strings.text('Developer platform')),
                            ),
                          ],
                          selected: {widget.state.preferences.clientMode},
                          onSelectionChanged: widget.state.loading
                              ? null
                              : (selection) => unawaited(
                                  chooseClientMode(selection.first),
                                ),
                        ),
                      ),
                      if (!isMobilePlatform) ...[
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.smartphone_outlined),
                          title: Text(
                            strings.text(
                              'Force desktop window to mobile width',
                            ),
                          ),
                          subtitle: Text(
                            strings.text(
                              'Lock the desktop window to a mobile-style width.',
                            ),
                          ),
                          value:
                              widget.state.preferences.forceDesktopMobileWidth,
                          onChanged: widget.state.updateForceDesktopMobileWidth,
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextField(
                        controller: serverUrl,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) {
                          if (!savingServer) {
                            saveServerUrl();
                          }
                        },
                        decoration: InputDecoration(
                          labelText: strings.text('CsAC server address'),
                          hintText: '192.168.1.10:8080',
                          helperText: strings.text(
                            'Leave empty to use the default server.',
                          ),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OverflowBar(
                        alignment: MainAxisAlignment.end,
                        spacing: 12,
                        overflowSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: savingServer ? null : resetServerUrl,
                            icon: const Icon(Icons.restart_alt),
                            label: Text(strings.text('Reset to default')),
                          ),
                          FilledButton.icon(
                            onPressed: savingServer ? null : saveServerUrl,
                            icon: savingServer
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: Text(strings.text('Apply server')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: acopServerUrl,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) {
                          if (!savingAcopServer) {
                            saveAcopServerUrl();
                          }
                        },
                        decoration: InputDecoration(
                          labelText: strings.text('ACOP server address'),
                          hintText: '192.168.1.10:8082',
                          helperText: strings.text(
                            'Leave empty to use the default server.',
                          ),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OverflowBar(
                        alignment: MainAxisAlignment.end,
                        spacing: 12,
                        overflowSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: savingAcopServer
                                ? null
                                : resetAcopServerUrl,
                            icon: const Icon(Icons.restart_alt),
                            label: Text(strings.text('Reset ACOP server')),
                          ),
                          FilledButton.icon(
                            onPressed: savingAcopServer
                                ? null
                                : saveAcopServerUrl,
                            icon: savingAcopServer
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: Text(strings.text('Apply ACOP server')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: emAppsServerUrl,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) {
                          if (!savingEmAppsServer) {
                            saveEmAppsServerUrl();
                          }
                        },
                        decoration: InputDecoration(
                          labelText: strings.text('eMApps server address'),
                          hintText: 'https://acop.csac.chat',
                          helperText: strings.text(
                            'Leave empty to use the default server.',
                          ),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OverflowBar(
                        alignment: MainAxisAlignment.end,
                        spacing: 12,
                        overflowSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: savingEmAppsServer
                                ? null
                                : resetEmAppsServerUrl,
                            icon: const Icon(Icons.restart_alt),
                            label: Text(strings.text('Reset eMApps server')),
                          ),
                          FilledButton.icon(
                            onPressed: savingEmAppsServer
                                ? null
                                : saveEmAppsServerUrl,
                            icon: savingEmAppsServer
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: Text(strings.text('Apply eMApps server')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(Icons.terminal_outlined),
                        title: Text(strings.text('eMApps debug logging')),
                        subtitle: Text(
                          strings.text(
                            'Write eMApps runtime, HTTP, crypto and WebView logs for diagnostics.',
                          ),
                        ),
                        value: widget.state.preferences.emAppsDebugLogging,
                        onChanged: widget.state.updateEmAppsDebugLogging,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.apps_outlined),
                        title: Text(strings.text('eMApps cache and logs')),
                        subtitle: Text(
                          strings.text(
                            'View logs or clear downloaded eMApps runtime files',
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  EmAppsLogScreen(state: widget.state),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.api_outlined),
                        title: Text(strings.text('API explorer')),
                        subtitle: Text(
                          strings.text(
                            'Search API docs, inspect parameters and run requests',
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  ApiExplorerScreen(state: widget.state),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.link_outlined),
                        title: Text(strings.text('URL scheme documentation')),
                        subtitle: Text(
                          strings.text(
                            'View CsAC URL scheme aliases and examples',
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const UrlSchemeDocsScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (showLogout) ...[
              _SettingsSectionTitle(strings.text('Account')),
              Card(
                elevation: 0,
                child: _RoundedInkClip(
                  child: ListTile(
                    leading: const Icon(Icons.logout),
                    title: Text(strings.text('Logout')),
                    subtitle: Text(
                      strings.text('Clear session and return to login'),
                    ),
                    iconColor: colors.error,
                    onTap: logoutToLogin,
                  ),
                ),
              ),
            ],
            if (!hasMatches)
              _EmptyPanel(message: strings.text('No matching settings.')),
          ],
        ),
      ),
    );
  }
}
