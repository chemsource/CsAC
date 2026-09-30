part of '../../main.dart';

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.state,
    required this.navigatorKey,
    required this.scaffoldMessengerKey,
  });

  final CsacAppState state;
  final GlobalKey<NavigatorState> navigatorKey;
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int index = 0;
  int lastUnreadChats = 0;
  Conversation? selectedConversation;
  int? selectedFocusMessageId;
  String? selectedDraftText;
  bool selectedDraftConfirmSend = false;
  int selectedDraftRequestId = 0;
  int? selectedSpacePostId;
  String? selectedEmAppId;
  String selectedSearchQuery = '';
  Timer? timer;

  @override
  void initState() {
    super.initState();
    lastUnreadChats = totalUnreadChats();
    timer = Timer.periodic(
      const Duration(seconds: 12),
      (_) => refreshHomeWithHint(),
    );
  }

  int totalUnreadChats() {
    return widget.state.conversations.fold<int>(
      0,
      (total, conversation) => total + conversation.unreadCount,
    );
  }

  String conversationKey(Conversation conversation) {
    return '${conversation.type.name}:${conversation.id}';
  }

  int newUnreadDelta(Map<String, int> beforeUnread) {
    var total = 0;
    for (final conversation in widget.state.conversations) {
      if (widget.state.isVisibleActiveConversation(conversation)) {
        continue;
      }
      final previous = beforeUnread[conversationKey(conversation)] ?? 0;
      final delta = conversation.unreadCount - previous;
      if (delta > 0) {
        total += delta;
      }
    }
    return total;
  }

  Future<void> refreshHomeWithHint() async {
    final strings = context.strings;
    final messenger = ScaffoldMessenger.of(context);
    final beforeUnread = <String, int>{
      for (final conversation in widget.state.conversations)
        conversationKey(conversation): conversation.unreadCount,
    };
    try {
      await widget.state.refreshHome();
    } catch (_) {
      return;
    }
    if (!mounted) {
      return;
    }
    final currentConversation =
        selectedConversation ?? widget.state.activeConversation;
    if (currentConversation != null) {
      final selected = currentConversation;
      final latestSelected = widget.state.conversations
          .where(
            (conversation) =>
                conversation.type == selected.type &&
                conversation.id == selected.id,
          )
          .firstOrNull;
      if (latestSelected != null) {
        if (selectedConversation != null) {
          selectedConversation = latestSelected.copyWith(unreadCount: 0);
        }
        if (widget.state.appInForeground) {
          await widget.state.markConversationRead(
            latestSelected,
            syncServer: false,
          );
        }
      }
    }
    final newCount = newUnreadDelta(beforeUnread);
    final after = totalUnreadChats();
    if (newCount > 0) {
      final message = strings.format('New messages: {count}', {
        'count': newCount,
      });
      messenger.showSnackBar(SnackBar(content: Text(message)));
      await showNewMessageNotifications(beforeUnread);
    }
    lastUnreadChats = after;
  }

  Future<void> showNewMessageNotifications(
    Map<String, int> beforeUnread,
  ) async {
    if (!widget.state.preferences.localSystemNotificationsEnabled) {
      return;
    }
    for (final conversation in widget.state.conversations) {
      if (widget.state.isVisibleActiveConversation(conversation)) {
        continue;
      }
      final key = conversationKey(conversation);
      final previous = beforeUnread[key] ?? 0;
      final delta = conversation.unreadCount - previous;
      if (delta > 0) {
        final strings = context.strings;
        final latestMessage = await latestNotificationMessage(conversation);
        if (!mounted) {
          return;
        }
        await CsacLocalNotificationService.instance
            .showConversationNotification(
              conversation: conversation,
              newCount: delta,
              title: notificationTitleForConversation(
                conversation,
                latestMessage,
              ),
              body: notificationBodyForConversation(
                conversation,
                delta,
                latestMessage,
                strings,
              ),
            );
      }
    }
  }

  Future<ChatMessage?> latestNotificationMessage(
    Conversation conversation,
  ) async {
    if (conversation.type == ConversationType.group) {
      final cached = await widget.state.loadCachedMessages(conversation);
      final afterId = cached.isEmpty ? 0 : cached.last.id;
      final previousIncomingId = latestIncomingNotificationMessageId(
        conversation,
        cached,
        currentUserId: widget.state.user?.uid ?? 0,
      );
      final loaded = await widget.state.syncMessages(
        conversation,
        afterId: afterId,
      );
      final latestIncoming = latestIncomingNotificationMessage(
        conversation,
        loaded,
        currentUserId: widget.state.user?.uid ?? 0,
      );
      if (latestIncoming != null && latestIncoming.id > previousIncomingId) {
        return latestIncoming;
      }
      return null;
    }
    final cached = await widget.state.loadCachedMessages(conversation);
    return latestIncomingNotificationMessage(
      conversation,
      cached,
      currentUserId: widget.state.user?.uid ?? 0,
    );
  }

  Future<ChatMessage?> latestCachedMessage(Conversation conversation) async {
    final cached = await widget.state.loadCachedMessages(conversation);
    return latestIncomingNotificationMessage(
          conversation,
          cached,
          currentUserId: widget.state.user?.uid ?? 0,
        ) ??
        (cached.isEmpty ? null : cached.last);
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  void selectDestination(int value) {
    setState(() => index = value);
    if (value == 0) {
      unawaited(widget.state.loadConversations());
    }
    if (value == 3) {
      unawaited(widget.state.refreshNotificationCounts());
    }
  }

  Future<bool> openDeepLinkTarget(CsacDeepLinkTarget target) async {
    switch (target.action) {
      case CsacDeepLinkAction.chats:
        return openDeepLinkTab(0);
      case CsacDeepLinkAction.space:
        selectedSpacePostId = null;
        return openDeepLinkTab(1);
      case CsacDeepLinkAction.spacePost:
        return openDeepLinkSpacePost(target.id ?? 0);
      case CsacDeepLinkAction.search:
        selectedSearchQuery = '';
        return openDeepLinkTab(2);
      case CsacDeepLinkAction.searchResult:
        return openDeepLinkSearch(target.query ?? '');
      case CsacDeepLinkAction.notices:
        return openDeepLinkTab(3);
      case CsacDeepLinkAction.emApps:
        return openDeepLinkEmApps();
      case CsacDeepLinkAction.emApp:
        return openDeepLinkEmApp(target.appId ?? '');
      case CsacDeepLinkAction.profile:
        return openDeepLinkTab(4);
      case CsacDeepLinkAction.userProfile:
        return openDeepLinkUserProfile(target.id ?? 0);
      case CsacDeepLinkAction.groupChat:
        return openDeepLinkChat(
          ConversationType.group,
          target.id ?? 0,
          draftText: target.draftText,
          confirmSend: target.confirmSend,
        );
      case CsacDeepLinkAction.privateChat:
        return openDeepLinkChat(
          ConversationType.private,
          target.id ?? 0,
          draftText: target.draftText,
          confirmSend: target.confirmSend,
        );
      case CsacDeepLinkAction.groupMessage:
        return openDeepLinkChat(
          ConversationType.group,
          target.id ?? 0,
          focusMessageId: target.messageId,
          draftText: target.draftText,
          confirmSend: target.confirmSend,
        );
      case CsacDeepLinkAction.privateMessage:
        return openDeepLinkChat(
          ConversationType.private,
          target.id ?? 0,
          focusMessageId: target.messageId,
          draftText: target.draftText,
          confirmSend: target.confirmSend,
        );
      case CsacDeepLinkAction.unsupported:
        return false;
    }
  }

  bool openDeepLinkTab(int value) {
    if (value < 0 || value > 4) {
      return false;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
    selectDestination(value);
    return true;
  }

  bool openDeepLinkSpacePost(int id) {
    if (id <= 0) {
      return false;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() => selectedSpacePostId = id);
    selectDestination(1);
    return true;
  }

  bool openDeepLinkSearch(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() => selectedSearchQuery = trimmed);
    selectDestination(2);
    return true;
  }

  Future<bool> openDeepLinkChat(
    ConversationType type,
    int id, {
    int? focusMessageId,
    String? draftText,
    bool confirmSend = false,
  }) async {
    if (id <= 0) {
      return false;
    }
    var conversation = findConversation(type, id);
    if (conversation == null) {
      try {
        await widget.state.loadConversations();
      } catch (_) {
        return false;
      }
      if (!mounted) {
        return false;
      }
      conversation = findConversation(type, id);
    }
    if (conversation == null) {
      if (type == ConversationType.group) {
        return openDeepLinkGroupDetail(id);
      }
      return false;
    }

    final navigator = Navigator.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    navigator.popUntil((route) => route.isFirst);
    final opened = conversation.copyWith(unreadCount: 0);
    final externalDraft = (draftText ?? '').trim();
    if (externalDraft.isNotEmpty) {
      await ConversationDraftStore.save(opened, externalDraft);
      selectedDraftRequestId += 1;
    }
    if (!mounted) {
      return true;
    }
    unawaited(widget.state.markConversationRead(conversation));
    widget.state.setActiveConversation(opened);
    selectDestination(0);
    if (wide) {
      setState(() {
        selectedConversation = opened;
        selectedFocusMessageId = focusMessageId;
        selectedDraftText = externalDraft.isEmpty ? null : externalDraft;
        selectedDraftConfirmSend = confirmSend && externalDraft.isNotEmpty;
      });
      lastUnreadChats = totalUnreadChats();
      return true;
    }
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          state: widget.state,
          conversation: opened,
          focusMessageId: focusMessageId,
          initialDraftText: externalDraft.isEmpty ? null : externalDraft,
          confirmInitialDraftSend: confirmSend && externalDraft.isNotEmpty,
          draftRequestId: externalDraft.isEmpty ? 0 : selectedDraftRequestId,
        ),
      ),
    );
    return true;
  }

  Future<bool> openDeepLinkGroupDetail(int roomId) async {
    if (roomId <= 0) {
      return false;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
    selectDestination(0);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConversationDetailScreen(
          state: widget.state,
          conversation: Conversation(
            type: ConversationType.group,
            id: roomId,
            name: context.strings.format('Room {id}', {'id': roomId}),
          ),
        ),
      ),
    );
    return true;
  }

  Future<bool> openDeepLinkUserProfile(int uid) async {
    if (uid <= 0) {
      return false;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UserProfileScreen(state: widget.state, uid: uid),
      ),
    );
    return true;
  }

  bool openDeepLinkEmApp(String appId) {
    final trimmed = appId.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    if (MediaQuery.sizeOf(context).width >= 900) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      setState(() => selectedEmAppId = trimmed);
      selectDestination(5);
      return true;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EmAppDetailScreen(state: widget.state, appId: trimmed),
      ),
    );
    return true;
  }

  bool openDeepLinkEmApps() {
    if (MediaQuery.sizeOf(context).width >= 900) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      setState(() => selectedEmAppId = null);
      selectDestination(5);
      return true;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EmAppsScreen(state: widget.state),
      ),
    );
    return true;
  }

  Conversation? findConversation(ConversationType type, int id) {
    return widget.state.conversations
        .where(
          (conversation) => conversation.type == type && conversation.id == id,
        )
        .firstOrNull;
  }

  Future<void> openCommandPalette({
    Future<void> Function()? onRefresh,
    Future<void> Function()? onScanQr,
  }) {
    return _showCommandPalette(
      state: widget.state,
      navigatorKey: widget.navigatorKey,
      scaffoldMessengerKey: widget.scaffoldMessengerKey,
      onRefresh: onRefresh,
      onScanQr: onScanQr,
    );
  }

  @override
  Widget build(BuildContext context) {
    final unreadChats = totalUnreadChats();
    final noticeCount = widget.state.notificationCounts.total;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final mainPages = <Widget>[
      ConversationScreen(
        state: widget.state,
        navigatorKey: widget.navigatorKey,
        scaffoldMessengerKey: widget.scaffoldMessengerKey,
        onOpenCommandPalette: openCommandPalette,
        embedded: true,
        selectedConversation: selectedConversation,
        onOpenDeepLinkTarget: openDeepLinkTarget,
        onConversationSelected: wide
            ? (conversation) {
                widget.state.markConversationRead(conversation);
                widget.state.setActiveConversation(conversation);
                setState(() {
                  selectedConversation = conversation.copyWith(unreadCount: 0);
                  selectedFocusMessageId = null;
                  selectedDraftText = null;
                  selectedDraftConfirmSend = false;
                  selectedDraftRequestId = 0;
                });
                lastUnreadChats = totalUnreadChats();
              }
            : null,
      ),
      SpaceFeedScreen(
        state: widget.state,
        embedded: true,
        focusPostId: selectedSpacePostId,
      ),
      MessageSearchScreen(
        state: widget.state,
        embedded: true,
        initialQuery: selectedSearchQuery,
      ),
      NoticeCenterScreen(state: widget.state),
      ProfileScreen(state: widget.state),
    ];
    final widePages = <Widget>[
      mainPages[0], // Chats
      mainPages[1], // Space
      mainPages[2], // Search
      mainPages[3], // Notices
      EmAppsScreen(  // Apps
        state: widget.state,
        embedded: true,
        initialAppId: selectedEmAppId,
      ),
      mainPages[4], // Me
    ];
    Widget shell;
    if (wide) {
      shell = Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: index,
                onDestinationSelected: selectDestination,
                labelType: NavigationRailLabelType.all,
                leading: Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 18),
                  child: Icon(
                    Icons.forum_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                destinations: [
                  NavigationRailDestination(
                    icon: _BadgeIcon(
                      icon: Icons.chat_bubble_outline,
                      count: unreadChats,
                    ),
                    selectedIcon: _BadgeIcon(
                      icon: Icons.chat_bubble,
                      count: unreadChats,
                    ),
                    label: Text(context.strings.text('Chats')),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.public_outlined),
                    selectedIcon: const Icon(Icons.public),
                    label: Text(context.strings.text('Space')),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.manage_search_outlined),
                    selectedIcon: const Icon(Icons.manage_search),
                    label: Text(context.strings.text('Search')),
                  ),
                  NavigationRailDestination(
                    icon: _BadgeIcon(
                      icon: Icons.notifications_none,
                      count: noticeCount,
                    ),
                    selectedIcon: _BadgeIcon(
                      icon: Icons.notifications,
                      count: noticeCount,
                    ),
                    label: Text(context.strings.text('Notices')),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.apps_outlined),
                    selectedIcon: const Icon(Icons.apps),
                    label: Text(context.strings.text('Apps')),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.person_outline),
                    selectedIcon: const Icon(Icons.person),
                    label: Text(context.strings.text('Me')),
                  ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: index == 0
                    ? _WideChatLayout(
                        state: widget.state,
                        conversations: widePages[0],
                        selectedConversation: selectedConversation,
                        focusMessageId: selectedFocusMessageId,
                        draftText: selectedDraftText,
                        confirmDraftSend: selectedDraftConfirmSend,
                        draftRequestId: selectedDraftRequestId,
                      )
                    : widePages[index],
              ),
            ],
          ),
        ),
      );
    } else {
      shell = Scaffold(
        body: _BottomTabSwitcher(index: index, children: mainPages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: selectDestination,
          destinations: [
            NavigationDestination(
              icon: _BadgeIcon(
                icon: Icons.chat_bubble_outline,
                count: unreadChats,
              ),
              selectedIcon: _BadgeIcon(
                icon: Icons.chat_bubble,
                count: unreadChats,
              ),
              label: context.strings.text('Chats'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.public_outlined),
              selectedIcon: const Icon(Icons.public),
              label: context.strings.text('Space'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.manage_search_outlined),
              selectedIcon: const Icon(Icons.manage_search),
              label: context.strings.text('Search'),
            ),
            NavigationDestination(
              icon: _BadgeIcon(
                icon: Icons.notifications_none,
                count: noticeCount,
              ),
              selectedIcon: _BadgeIcon(
                icon: Icons.notifications,
                count: noticeCount,
              ),
              label: context.strings.text('Notices'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person),
              label: context.strings.text('Me'),
            ),
          ],
        ),
      );
    }
    return shell;
  }
}

class _BottomTabSwitcher extends StatefulWidget {
  const _BottomTabSwitcher({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<_BottomTabSwitcher> createState() => _BottomTabSwitcherState();
}

class _BottomTabSwitcherState extends State<_BottomTabSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  int previousIndex = 0;

  @override
  void initState() {
    super.initState();
    previousIndex = widget.index;
    controller = AnimationController(duration: 280.ms, vsync: this)..value = 1;
  }

  @override
  void didUpdateWidget(covariant _BottomTabSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      previousIndex = oldWidget.index;
      controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = _MotionPreference.reduceOf(context);
    if (reduceMotion) {
      return IndexedStack(
        index: widget.index,
        children: [
          for (var i = 0; i < widget.children.length; i++)
            _FocusableTabPage(
              active: i == widget.index,
              child: widget.children[i],
            ),
        ],
      );
    }
    final forward = widget.index >= previousIndex;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final curved = Curves.easeOutCubic.transform(controller.value);
        return ClipRect(
          child: Stack(
            clipBehavior: Clip.hardEdge,
            fit: StackFit.expand,
            children: [
              for (var i = 0; i < widget.children.length; i++)
                _buildPage(i, curved, forward),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPage(int pageIndex, double progress, bool forward) {
    final active = pageIndex == widget.index;
    final outgoing = pageIndex == previousIndex && pageIndex != widget.index;
    final direction = forward ? 1.0 : -1.0;
    final offset = active
        ? Offset(0.06 * direction * (1 - progress), 0)
        : outgoing
        ? Offset(-0.04 * direction * progress, 0)
        : Offset.zero;
    final opacity = active
        ? progress
        : outgoing
        ? 1 - progress
        : pageIndex == widget.index
        ? 1.0
        : 0.0;
    return _FocusableTabPage(
      active: active,
      child: Offstage(
        offstage: !active && !outgoing,
        child: TickerMode(
          enabled: active,
          child: IgnorePointer(
            ignoring: !active,
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: FractionalTranslation(
                translation: offset,
                child: widget.children[pageIndex],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusableTabPage extends StatelessWidget {
  const _FocusableTabPage({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      canRequestFocus: active,
      descendantsAreFocusable: active,
      descendantsAreTraversable: active,
      child: child,
    );
  }
}

class _WideChatLayout extends StatelessWidget {
  const _WideChatLayout({
    required this.state,
    required this.conversations,
    required this.selectedConversation,
    this.focusMessageId,
    this.draftText,
    this.confirmDraftSend = false,
    this.draftRequestId = 0,
  });

  final CsacAppState state;
  final Widget conversations;
  final Conversation? selectedConversation;
  final int? focusMessageId;
  final String? draftText;
  final bool confirmDraftSend;
  final int draftRequestId;

  @override
  Widget build(BuildContext context) {
    final selected = selectedConversation;
    return Row(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 320, maxWidth: 430),
          child: conversations,
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: selected == null
              ? const _WideEmptyChatPlaceholder()
              : ChatScreen(
                  key: ValueKey(
                    '${selected.type.name}:${selected.id}:${focusMessageId ?? 0}',
                  ),
                  state: state,
                  conversation: selected,
                  embedded: true,
                  focusMessageId: focusMessageId,
                  initialDraftText: draftText,
                  confirmInitialDraftSend: confirmDraftSend,
                  draftRequestId: draftRequestId,
                ),
        ),
      ],
    );
  }
}

class _WideEmptyChatPlaceholder extends StatelessWidget {
  const _WideEmptyChatPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 56,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              context.strings.text('Select a conversation'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgeIcon extends StatelessWidget {
  const _BadgeIcon({required this.icon, required this.count});

  final IconData icon;
  final int count;

  @override
  Widget build(BuildContext context) {
    final child = Icon(icon);
    if (count <= 0) {
      return child;
    }
    return Badge(label: Text(count > 99 ? '99+' : '$count'), child: child);
  }
}

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    super.key,
    required this.state,
    required this.navigatorKey,
    required this.scaffoldMessengerKey,
    this.embedded = false,
    this.selectedConversation,
    this.onConversationSelected,
    this.onOpenDeepLinkTarget,
    this.onOpenCommandPalette,
  });

  final CsacAppState state;
  final GlobalKey<NavigatorState> navigatorKey;
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey;
  final bool embedded;
  final Conversation? selectedConversation;
  final ValueChanged<Conversation>? onConversationSelected;
  final Future<bool> Function(CsacDeepLinkTarget target)? onOpenDeepLinkTarget;
  final CommandPaletteOpener? onOpenCommandPalette;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

enum _ConversationGroupFilter { all, important, friends, groups, archived }

class _ConversationScreenState extends State<ConversationScreen> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final search = TextEditingController();
  late final ScrollController conversationsScroll;
  Map<String, ConversationDraft> drafts = const <String, ConversationDraft>{};
  Map<String, ConversationLocalPreference> conversationPrefs =
      const <String, ConversationLocalPreference>{};
  bool refreshing = false;
  _ConversationGroupFilter groupFilter = _ConversationGroupFilter.all;

  @override
  void initState() {
    super.initState();
    conversationsScroll = _desktopSmoothScrollController();
    ConversationDraftStore.changes.addListener(handleDraftsChanged);
    ConversationPreferenceStore.changes.addListener(handlePreferencesChanged);
    unawaited(loadDrafts());
    unawaited(loadConversationPrefs());
  }

  @override
  void dispose() {
    ConversationDraftStore.changes.removeListener(handleDraftsChanged);
    ConversationPreferenceStore.changes.removeListener(
      handlePreferencesChanged,
    );
    conversationsScroll.dispose();
    search.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    setState(() => refreshing = true);
    try {
      await widget.state.loadConversations();
      await loadDrafts();
      await loadConversationPrefs();
    } finally {
      if (mounted) {
        setState(() => refreshing = false);
      }
    }
  }

  Future<void> loadDrafts() async {
    final loaded = await ConversationDraftStore.loadAll();
    if (mounted) {
      setState(() => drafts = loaded);
    }
  }

  void handleDraftsChanged() {
    unawaited(loadDrafts());
  }

  Future<void> loadConversationPrefs() async {
    final loaded = await ConversationPreferenceStore.loadAll();
    if (mounted) {
      setState(() {
        conversationPrefs = loaded;
        if (groupFilter == _ConversationGroupFilter.archived &&
            !loaded.values.any((value) => value.archived)) {
          groupFilter = _ConversationGroupFilter.all;
        }
      });
    }
  }

  void handlePreferencesChanged() {
    unawaited(loadConversationPrefs());
  }

  String draftKey(Conversation conversation) {
    return ConversationPreferenceStore.keyFor(conversation);
  }

  ConversationLocalPreference localPref(Conversation conversation) {
    return conversationPrefs[draftKey(conversation)] ??
        ConversationLocalPreference.defaults;
  }

  List<Conversation> visibleConversations(String query) {
    final searched = query.isEmpty
        ? widget.state.conversations
        : widget.state.conversations.where((conversation) {
            final target =
                '${conversation.name} ${conversation.subtitle} ${conversation.searchText}'
                    .toLowerCase();
            return target.contains(query);
          }).toList();
    final visible = searched.where(conversationInCurrentGroup).toList();
    visible.sort((a, b) {
      final aPref = localPref(a);
      final bPref = localPref(b);
      if (aPref.pinned != bPref.pinned) {
        return aPref.pinned ? -1 : 1;
      }
      return searched.indexOf(a).compareTo(searched.indexOf(b));
    });
    return visible;
  }

  bool conversationInCurrentGroup(Conversation conversation) {
    final pref = localPref(conversation);
    switch (groupFilter) {
      case _ConversationGroupFilter.all:
        return !conversation.hidden && !pref.archived;
      case _ConversationGroupFilter.important:
        return !conversation.hidden && !pref.archived && pref.pinned;
      case _ConversationGroupFilter.friends:
        return !conversation.hidden &&
            !pref.archived &&
            conversation.type == ConversationType.private;
      case _ConversationGroupFilter.groups:
        return !conversation.hidden &&
            !pref.archived &&
            conversation.type == ConversationType.group;
      case _ConversationGroupFilter.archived:
        return !conversation.hidden && pref.archived;
    }
  }

  int groupCount(_ConversationGroupFilter filter) {
    return widget.state.conversations.where((conversation) {
      final pref = localPref(conversation);
      switch (filter) {
        case _ConversationGroupFilter.all:
          return !conversation.hidden && !pref.archived;
        case _ConversationGroupFilter.important:
          return !conversation.hidden && !pref.archived && pref.pinned;
        case _ConversationGroupFilter.friends:
          return !conversation.hidden &&
              !pref.archived &&
              conversation.type == ConversationType.private;
        case _ConversationGroupFilter.groups:
          return !conversation.hidden &&
              !pref.archived &&
              conversation.type == ConversationType.group;
        case _ConversationGroupFilter.archived:
          return !conversation.hidden && pref.archived;
      }
    }).length;
  }

  String emptyMessageForGroup(String query) {
    if (query.isNotEmpty) {
      return 'No matching conversations.';
    }
    switch (groupFilter) {
      case _ConversationGroupFilter.all:
        return 'No active conversations.';
      case _ConversationGroupFilter.important:
        return 'No important conversations.';
      case _ConversationGroupFilter.friends:
        return 'No friend conversations.';
      case _ConversationGroupFilter.groups:
        return 'No group conversations.';
      case _ConversationGroupFilter.archived:
        return 'No archived conversations.';
    }
  }

  Future<void> updateLocalPreference(
    Conversation conversation,
    ConversationLocalPreference Function(ConversationLocalPreference current)
    change,
  ) async {
    await widget.state.updateConversationLocalPreference(conversation, change);
    await loadConversationPrefs();
  }

  Future<void> showConversationActions(Conversation conversation) async {
    final pref = localPref(conversation);
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: _RoundedInkClip(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  pref.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                ),
                title: Text(
                  context.strings.text(
                    pref.pinned ? 'Unpin conversation' : 'Pin conversation',
                  ),
                ),
                onTap: () => Navigator.of(context).pop('pin'),
              ),
              ListTile(
                leading: Icon(
                  pref.muted
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                ),
                title: Text(
                  context.strings.text(
                    pref.muted ? 'Unmute conversation' : 'Mute conversation',
                  ),
                ),
                onTap: () => Navigator.of(context).pop('mute'),
              ),
              ListTile(
                leading: Icon(
                  pref.archived
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined,
                ),
                title: Text(
                  context.strings.text(
                    pref.archived
                        ? 'Unarchive conversation'
                        : 'Archive conversation',
                  ),
                ),
                onTap: () => Navigator.of(context).pop('archive'),
              ),
              if (conversation.type == ConversationType.group)
                ListTile(
                  leading: Icon(
                    conversation.hidden
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  title: Text(
                    context.strings.text(
                      conversation.hidden
                          ? 'Unhide conversation'
                          : 'Hide conversation',
                    ),
                  ),
                  onTap: () => Navigator.of(context).pop('hide'),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selected == null) {
      return;
    }
    switch (selected) {
      case 'pin':
        await updateLocalPreference(
          conversation,
          (current) => current.copyWith(pinned: !current.pinned),
        );
        break;
      case 'mute':
        await updateLocalPreference(
          conversation,
          (current) => current.copyWith(muted: !current.muted),
        );
        break;
      case 'archive':
        await updateLocalPreference(
          conversation,
          (current) => current.copyWith(
            archived: !current.archived,
            pinned: current.archived ? current.pinned : false,
          ),
        );
        break;
      case 'hide':
        try {
          final update = await widget.state.toggleConversationHidden(
            conversation,
          );
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                update.message.trim().isNotEmpty
                    ? update.message
                    : context.strings.text(
                        update.isHidden
                            ? 'Conversation hidden.'
                            : 'Conversation unhidden.',
                      ),
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
        }
        break;
    }
  }

  Future<void> openHomeAction(String action) async {
    switch (action) {
      case 'refresh':
        await refresh();
        break;
      case 'scanQr':
        await scanQrCode();
        break;
      case 'addFriend':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AddFriendScreen(state: widget.state),
          ),
        );
        break;
      case 'joinGroup':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => JoinGroupScreen(state: widget.state),
          ),
        );
        break;
      case 'createGroup':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CreateGroupScreen(state: widget.state),
          ),
        );
        break;
      case 'searchMessages':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MessageSearchScreen(state: widget.state),
          ),
        );
        break;
      case 'logout':
        await confirmLogout(context, widget.state, popToRoot: false);
        break;
    }
    if (mounted &&
        action != 'refresh' &&
        action != 'scanQr' &&
        action != 'searchMessages' &&
        action != 'logout') {
      await refresh();
    }
  }

  Future<void> scanQrCode() async {
    if (!isMobilePlatform) {
      return;
    }
    final uri = await openCsacQrScanner(context);
    if (uri == null || !mounted) {
      return;
    }
    final target = parseCsacDeepLink(uri);
    if (!target.isSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.text('Unsupported CsAC link.'))),
      );
      return;
    }
    final opener = widget.onOpenDeepLinkTarget;
    final handled = opener == null
        ? await openScannedDeepLinkTarget(target)
        : await opener(target);
    if (mounted && !handled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.strings.text('Unable to open CsAC link.')),
        ),
      );
    }
  }

  Future<bool> openScannedDeepLinkTarget(CsacDeepLinkTarget target) async {
    switch (target.action) {
      case CsacDeepLinkAction.userProfile:
        final uid = target.id ?? 0;
        if (uid <= 0) {
          return false;
        }
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => UserProfileScreen(state: widget.state, uid: uid),
          ),
        );
        return true;
      case CsacDeepLinkAction.unsupported:
        return false;
      case CsacDeepLinkAction.chats:
      case CsacDeepLinkAction.space:
      case CsacDeepLinkAction.spacePost:
      case CsacDeepLinkAction.search:
      case CsacDeepLinkAction.searchResult:
      case CsacDeepLinkAction.notices:
      case CsacDeepLinkAction.emApps:
      case CsacDeepLinkAction.emApp:
      case CsacDeepLinkAction.profile:
      case CsacDeepLinkAction.groupChat:
      case CsacDeepLinkAction.privateChat:
      case CsacDeepLinkAction.groupMessage:
      case CsacDeepLinkAction.privateMessage:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.state.user;
    final strings = context.strings;
    final query = search.text.trim().toLowerCase();
    final conversations = visibleConversations(query);
    final screenSize = MediaQuery.sizeOf(context);
    final isTabletMobile = isMobilePlatform && screenSize.shortestSide >= 600;
    final drawerEnabled = isMobilePlatform && !isTabletMobile;
    final commandButtonEnabled = isMobilePlatform;
    final groupFilters = <_ConversationGroupFilter>[
      _ConversationGroupFilter.all,
      _ConversationGroupFilter.important,
      _ConversationGroupFilter.friends,
      _ConversationGroupFilter.groups,
      _ConversationGroupFilter.archived,
    ];
    final content = RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        controller: conversationsScroll,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      _Avatar(
                        url: widget.state.currentUserAvatar,
                        fallback: Icons.person_rounded,
                        radius: 19,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          user == null
                              ? strings.text('Not logged in')
                              : '${user.nickname} / UID ${user.uid}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.state.offlineMode)
                  Chip(
                    avatar: const Icon(Icons.cloud_off_outlined, size: 18),
                    label: Text(strings.text('Offline')),
                  ),
                if (commandButtonEnabled)
                  IconButton(
                    tooltip: strings.text('Commands'),
                    onPressed: () {
                      if (drawerEnabled) {
                        scaffoldKey.currentState?.openDrawer();
                        return;
                      }
                      final openPalette = widget.onOpenCommandPalette;
                      if (openPalette != null) {
                        unawaited(
                          openPalette(onRefresh: refresh, onScanQr: scanQrCode),
                        );
                        return;
                      }
                      unawaited(
                        _showCommandPalette(
                          state: widget.state,
                          navigatorKey: widget.navigatorKey,
                          scaffoldMessengerKey: widget.scaffoldMessengerKey,
                          onRefresh: refresh,
                          onScanQr: scanQrCode,
                        ),
                      );
                    },
                    icon: const Icon(Icons.terminal_rounded),
                  ),
                PopupMenuButton<String>(
                  tooltip: strings.text('More'),
                  onSelected: openHomeAction,
                  itemBuilder: (context) => [
                    if (drawerEnabled)
                      PopupMenuItem(
                        value: 'scanQr',
                        child: ListTile(
                          leading: const Icon(Icons.qr_code_scanner),
                          title: Text(strings.text('Scan QR code')),
                        ),
                      ),
                    PopupMenuItem(
                      value: 'addFriend',
                      child: ListTile(
                        leading: const Icon(Icons.person_add_alt),
                        title: Text(strings.text('Add friend')),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'joinGroup',
                      child: ListTile(
                        leading: const Icon(Icons.group_add_outlined),
                        title: Text(strings.text('Join group')),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'createGroup',
                      child: ListTile(
                        leading: const Icon(Icons.add_home_work_outlined),
                        title: Text(strings.text('Create group')),
                      ),
                    ),
                  ],
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: TextField(
              controller: search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: strings.text('Search conversations'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: strings.text('Clear'),
                        onPressed: () {
                          search.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: ScrollConfiguration(
              behavior: const _HorizontalDragScrollBehavior(),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final filter in groupFilters)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          showCheckmark: false,
                          avatar: Icon(
                            _conversationGroupIcon(filter),
                            size: 18,
                          ),
                          label: Text(
                            strings.format(_conversationGroupLabel(filter), {
                              'count': groupCount(filter),
                            }),
                          ),
                          selected: groupFilter == filter,
                          onSelected: (_) =>
                              setState(() => groupFilter = filter),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (widget.state.conversations.isEmpty)
            _EmptyPanel(message: strings.text('No conversations yet.'))
          else if (conversations.isEmpty)
            _EmptyPanel(message: strings.text(emptyMessageForGroup(query)))
          else
            for (final entry in conversations.indexed)
              _MotionListItem(
                index: entry.$1,
                child: _ConversationTile(
                  conversation: entry.$2,
                  draft: drafts[draftKey(entry.$2)],
                  preference: localPref(entry.$2),
                  subtitleMode:
                      widget.state.preferences.conversationSubtitleMode,
                  selected:
                      widget.selectedConversation?.type == entry.$2.type &&
                      widget.selectedConversation?.id == entry.$2.id,
                  onLongPress: () => showConversationActions(entry.$2),
                  onTap: () async {
                    if (widget.onConversationSelected != null) {
                      widget.onConversationSelected!(entry.$2);
                      unawaited(loadDrafts());
                      return;
                    }
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ChatScreen(
                          state: widget.state,
                          conversation: entry.$2,
                        ),
                      ),
                    );
                    if (mounted) {
                      refresh();
                    }
                  },
                ),
              ),
        ],
      ),
    );
    return Scaffold(
      key: scaffoldKey,
      drawer: drawerEnabled
          ? _MobileCommandSidebar(
              state: widget.state,
              onRefresh: refresh,
              onScanQr: scanQrCode,
            )
          : null,
      drawerEnableOpenDragGesture: drawerEnabled,
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('CsAC'),
              actions: [
                PopupMenuButton<String>(
                  tooltip: strings.text('More'),
                  onSelected: openHomeAction,
                  itemBuilder: (context) => [
                    if (drawerEnabled)
                      PopupMenuItem(
                        value: 'scanQr',
                        child: ListTile(
                          leading: const Icon(Icons.qr_code_scanner),
                          title: Text(strings.text('Scan QR code')),
                        ),
                      ),
                    PopupMenuItem(
                      value: 'refresh',
                      child: ListTile(
                        leading: const Icon(Icons.refresh),
                        title: Text(strings.text('Refresh')),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'addFriend',
                      child: ListTile(
                        leading: const Icon(Icons.person_add_alt),
                        title: Text(strings.text('Add friend')),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'joinGroup',
                      child: ListTile(
                        leading: const Icon(Icons.group_add_outlined),
                        title: Text(strings.text('Join group')),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'createGroup',
                      child: ListTile(
                        leading: const Icon(Icons.add_home_work_outlined),
                        title: Text(strings.text('Create group')),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'searchMessages',
                      child: ListTile(
                        leading: const Icon(Icons.manage_search),
                        title: Text(strings.text('Search messages')),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'logout',
                      child: ListTile(
                        leading: const Icon(Icons.logout),
                        title: Text(strings.text('Logout')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
      body: SafeArea(top: widget.embedded, child: content),
    );
  }
}

String _conversationGroupLabel(_ConversationGroupFilter filter) {
  switch (filter) {
    case _ConversationGroupFilter.all:
      return 'All conversations ({count})';
    case _ConversationGroupFilter.important:
      return 'Important ({count})';
    case _ConversationGroupFilter.friends:
      return 'Friends ({count})';
    case _ConversationGroupFilter.groups:
      return 'Groups ({count})';
    case _ConversationGroupFilter.archived:
      return 'Archived ({count})';
  }
}

IconData _conversationGroupIcon(_ConversationGroupFilter filter) {
  switch (filter) {
    case _ConversationGroupFilter.all:
      return Icons.inbox_outlined;
    case _ConversationGroupFilter.important:
      return Icons.push_pin_outlined;
    case _ConversationGroupFilter.friends:
      return Icons.person_outline;
    case _ConversationGroupFilter.groups:
      return Icons.groups_outlined;
    case _ConversationGroupFilter.archived:
      return Icons.archive_outlined;
  }
}

class _HorizontalDragScrollBehavior extends MaterialScrollBehavior {
  const _HorizontalDragScrollBehavior();

  @override
  Set<ui.PointerDeviceKind> get dragDevices => const {
    ui.PointerDeviceKind.touch,
    ui.PointerDeviceKind.mouse,
    ui.PointerDeviceKind.trackpad,
    ui.PointerDeviceKind.stylus,
    ui.PointerDeviceKind.unknown,
  };
}

class _MobileCommandSidebar extends StatefulWidget {
  const _MobileCommandSidebar({
    required this.state,
    required this.onRefresh,
    required this.onScanQr,
  });

  final CsacAppState state;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onScanQr;

  @override
  State<_MobileCommandSidebar> createState() => _MobileCommandSidebarState();
}

class _MobileCommandSidebarState extends State<_MobileCommandSidebar> {
  late final TextEditingController search;
  late final ScrollController actionsScroll;
  Map<String, CommandPaletteUsage> usage =
      const <String, CommandPaletteUsage>{};
  bool running = false;
  String query = '';

  @override
  void initState() {
    super.initState();
    search = TextEditingController();
    actionsScroll = _desktopSmoothScrollController();
    unawaited(loadUsage());
  }

  @override
  void dispose() {
    search.dispose();
    actionsScroll.dispose();
    super.dispose();
  }

  Future<void> loadUsage() async {
    final loaded = await CommandPaletteUsageStore.loadAll();
    if (mounted) {
      setState(() => usage = loaded);
    }
  }

  List<_CommandPaletteAction> actions(BuildContext context) {
    final strings = context.strings;
    return [
      _CommandPaletteAction(
        id: 'settings',
        icon: Icons.settings_outlined,
        title: strings.text('Settings'),
        subtitle: strings.text('Open app settings'),
        keywords: const ['settings', 'setting', 'preferences', '设置'],
        run: (context) =>
            openRoute(SettingsScreen(state: widget.state), context),
      ),
      _CommandPaletteAction(
        id: 'scan_qr',
        icon: Icons.qr_code_scanner,
        title: strings.text('Scan QR code'),
        subtitle: strings.text('Open a CsAC QR code'),
        keywords: const ['qr', 'scan', 'scheme', '扫码', '二维码'],
        run: scanQr,
      ),
      _CommandPaletteAction(
        id: 'search_messages',
        icon: Icons.manage_search,
        title: strings.text('Search messages'),
        subtitle: strings.text('Search cached messages'),
        keywords: const ['search', 'messages', 'history', '搜索', '消息'],
        run: (context) =>
            openRoute(MessageSearchScreen(state: widget.state), context),
      ),
      _CommandPaletteAction(
        id: 'space',
        icon: Icons.public_outlined,
        title: strings.text('Space'),
        subtitle: strings.text('Friends space feed'),
        keywords: const ['space', 'feed', 'dynamic', '动态', '空间'],
        run: (context) =>
            openRoute(SpaceFeedScreen(state: widget.state), context),
      ),
      _CommandPaletteAction(
        id: 'refresh_conversations',
        icon: Icons.sync,
        title: strings.text('Refresh conversations'),
        subtitle: strings.text('Chats'),
        keywords: const ['refresh', 'reload', 'sync', '刷新', '同步'],
        run: refreshConversations,
      ),
      _CommandPaletteAction(
        id: 'add_friend',
        icon: Icons.person_add_alt,
        title: strings.text('Add friend'),
        subtitle: strings.text('User UID'),
        keywords: const ['friend', 'add', 'uid', '好友', '添加'],
        run: (context) async {
          await openRoute(AddFriendScreen(state: widget.state), context);
          await widget.onRefresh();
        },
      ),
      _CommandPaletteAction(
        id: 'join_group',
        icon: Icons.group_add_outlined,
        title: strings.text('Join group'),
        subtitle: strings.text('Room ID'),
        keywords: const ['group', 'join', 'room', '群', '加入'],
        run: (context) async {
          await openRoute(JoinGroupScreen(state: widget.state), context);
          await widget.onRefresh();
        },
      ),
      _CommandPaletteAction(
        id: 'create_group',
        icon: Icons.add_home_work_outlined,
        title: strings.text('Create group'),
        subtitle: strings.text('Group chat'),
        keywords: const ['group', 'create', 'room', '群', '创建'],
        run: (context) async {
          await openRoute(CreateGroupScreen(state: widget.state), context);
          await widget.onRefresh();
        },
      ),
      _CommandPaletteAction(
        id: 'clear_local_cache',
        icon: Icons.cleaning_services_outlined,
        title: strings.text('Clear local cache'),
        subtitle: strings.text(
          'Remove cached conversations and message history',
        ),
        keywords: const ['clear', 'cache', 'clean', '缓存', '清理'],
        run: clearLocalCache,
      ),
      _CommandPaletteAction(
        id: 'theme_light',
        icon: Icons.light_mode_outlined,
        title: strings.text('Switch to light theme'),
        subtitle: strings.text('Theme'),
        keywords: const ['theme', 'light', '浅色', '主题'],
        run: (context) => switchTheme(ThemeMode.light, context),
      ),
      _CommandPaletteAction(
        id: 'theme_dark',
        icon: Icons.dark_mode_outlined,
        title: strings.text('Switch to dark theme'),
        subtitle: strings.text('Theme'),
        keywords: const ['theme', 'dark', '深色', '主题'],
        run: (context) => switchTheme(ThemeMode.dark, context),
      ),
      _CommandPaletteAction(
        id: 'theme_system',
        icon: Icons.brightness_auto_outlined,
        title: strings.text('Follow system theme'),
        subtitle: strings.text('Theme'),
        keywords: const ['theme', 'system', 'auto', '系统', '主题'],
        run: (context) => switchTheme(ThemeMode.system, context),
      ),
      _CommandPaletteAction(
        id: 'api_explorer',
        icon: Icons.api_outlined,
        title: strings.text('API explorer'),
        subtitle: '/api',
        keywords: const ['api', '/api', '接口', '文档'],
        run: (context) =>
            openRoute(ApiExplorerScreen(state: widget.state), context),
      ),
      _CommandPaletteAction(
        id: 'app_logs',
        icon: Icons.article_outlined,
        title: strings.text('App logs'),
        subtitle: '/log',
        keywords: const ['log', '/log', 'logs', '日志'],
        run: (context) =>
            openRoute(AppLogsScreen(state: widget.state), context),
      ),
      _CommandPaletteAction(
        id: 'network_diagnostics',
        icon: Icons.network_check_outlined,
        title: strings.text('Connection diagnostics'),
        subtitle: '/diag',
        keywords: const ['diag', '/diag', 'network', 'diagnostics', '诊断', '网络'],
        run: (context) =>
            openRoute(NetworkDiagnosticsScreen(state: widget.state), context),
      ),
    ];
  }

  List<_CommandPaletteAction> filteredActions(
    BuildContext context,
    String value,
  ) {
    final normalized = value.trim().toLowerCase();
    if (normalized.startsWith('@')) {
      return contactActions(context, normalized.substring(1));
    }
    if (normalized.startsWith('#')) {
      return groupActions(context, normalized.substring(1));
    }
    if (normalized.startsWith('/')) {
      return prefixActions(context, normalized);
    }
    final all = actions(context);
    if (normalized.isEmpty) {
      return sortedActions(all);
    }
    return sortedActions(
      all.where((action) => action.matches(normalized)).toList(),
    );
  }

  List<_CommandPaletteAction> prefixActions(
    BuildContext context,
    String value,
  ) {
    final slashCommands = actions(context)
        .where(
          (action) => action.keywords.any((keyword) => keyword.startsWith('/')),
        )
        .toList();
    return sortedActions(
      slashCommands.where((action) => action.matches(value)).toList(),
    );
  }

  List<_CommandPaletteAction> contactActions(
    BuildContext context,
    String value,
  ) {
    final strings = context.strings;
    final query = value.trim().toLowerCase();
    final conversations = widget.state.conversations.where(
      (conversation) => conversation.type == ConversationType.private,
    );
    final byName = conversations
        .where((conversation) {
          if (query.isEmpty) {
            return true;
          }
          return [
            conversation.name,
            conversation.subtitle,
            conversation.searchText,
            '${conversation.id}',
          ].join(' ').toLowerCase().contains(query);
        })
        .map((conversation) {
          return _CommandPaletteAction(
            id: 'open_user:${conversation.id}',
            icon: Icons.person_outline,
            title: '@${conversation.name}',
            subtitle: strings.format('Open {name} profile', {
              'name': conversation.name,
            }),
            keywords: [
              '@${conversation.name}',
              conversation.name,
              conversation.subtitle,
              conversation.searchText,
              '${conversation.id}',
            ],
            run: (context) => openConversationDetails(conversation, context),
          );
        })
        .toList();
    final uid = int.tryParse(query);
    if (uid != null &&
        uid > 0 &&
        !byName.any((action) => action.id == 'open_user:$uid')) {
      byName.insert(
        0,
        _CommandPaletteAction(
          id: 'open_user:$uid',
          icon: Icons.tag,
          title: '@UID $uid',
          subtitle: strings.text('Open user profile by UID'),
          keywords: ['@$uid', '$uid', 'uid'],
          run: (context) => openUserProfileByUid(uid, context),
        ),
      );
    }
    return sortedActions(byName);
  }

  List<_CommandPaletteAction> groupActions(BuildContext context, String value) {
    final strings = context.strings;
    final query = value.trim().toLowerCase();
    final actions = widget.state.conversations
        .where((conversation) => conversation.type == ConversationType.group)
        .where((conversation) {
          if (query.isEmpty) {
            return true;
          }
          return [
            conversation.name,
            conversation.subtitle,
            conversation.searchText,
            '${conversation.id}',
          ].join(' ').toLowerCase().contains(query);
        })
        .map(
          (conversation) => _CommandPaletteAction(
            id: 'open_group:${conversation.id}',
            icon: Icons.groups_outlined,
            title: '#${conversation.name}',
            subtitle: strings.format('Open {name} chat', {
              'name': conversation.name,
            }),
            keywords: [
              '#${conversation.name}',
              conversation.name,
              conversation.subtitle,
              conversation.searchText,
              '${conversation.id}',
            ],
            run: (context) => openChat(conversation, context),
          ),
        )
        .toList();
    return sortedActions(actions);
  }

  List<_CommandPaletteAction> sortedActions(List<_CommandPaletteAction> input) {
    final result = input.toList();
    result.sort((a, b) {
      final aUsage = usage[a.id];
      final bUsage = usage[b.id];
      final aUsed = aUsage != null;
      final bUsed = bUsage != null;
      if (aUsed != bUsed) {
        return aUsed ? -1 : 1;
      }
      if (aUsage != null && bUsage != null) {
        final count = bUsage.count.compareTo(aUsage.count);
        if (count != 0) {
          return count;
        }
        return bUsage.lastUsedAt.compareTo(aUsage.lastUsedAt);
      }
      return 0;
    });
    return result;
  }

  Future<void> runAction(_CommandPaletteAction action) async {
    if (running) {
      return;
    }
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final strings = context.strings;
    setState(() => running = true);
    navigator.pop();
    try {
      await CommandPaletteUsageStore.record(action.id);
      await action.run(
        _CommandPaletteActionContext(
          navigator: navigator,
          messenger: messenger,
          strings: strings,
        ),
      );
    } catch (err) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            strings.format('Command failed: {error}', {'error': err}),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => running = false);
      }
    }
  }

  Future<void> openRoute(
    Widget screen,
    _CommandPaletteActionContext context,
  ) async {
    if (context.navigator == null) {
      return;
    }
    await context.navigator!.push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  Future<void> refreshConversations(
    _CommandPaletteActionContext context,
  ) async {
    await widget.onRefresh();
    context.messenger?.showSnackBar(
      SnackBar(content: Text(context.strings.text('Refreshed.'))),
    );
  }

  Future<void> scanQr(_CommandPaletteActionContext context) async {
    await widget.onScanQr();
  }

  Future<void> clearLocalCache(_CommandPaletteActionContext context) async {
    final navigator = context.navigator;
    if (navigator == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: navigator.context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.strings.text('Clear local cache?')),
        content: Text(
          context.strings.text(
            'Cached conversations and message history on this device will be removed. Your login session will be kept.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.strings.text('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.strings.text('Clear')),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await widget.state.clearLocalCache();
    await widget.onRefresh();
    context.messenger?.showSnackBar(
      SnackBar(content: Text(context.strings.text('Local cache cleared.'))),
    );
  }

  Future<void> switchTheme(
    ThemeMode mode,
    _CommandPaletteActionContext context,
  ) async {
    await widget.state.updateThemeMode(mode);
    context.messenger?.showSnackBar(
      SnackBar(content: Text(context.strings.text('Theme updated.'))),
    );
  }

  Future<void> openConversationDetails(
    Conversation conversation,
    _CommandPaletteActionContext context,
  ) async {
    final navigator = context.navigator;
    if (navigator == null) {
      return;
    }
    if (conversation.type == ConversationType.private) {
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => UserProfileScreen(
            state: widget.state,
            uid: conversation.id,
            avatarHeroTag: conversationAvatarHeroTag(conversation),
          ),
        ),
      );
      return;
    }
    await openRoute(
      ConversationDetailScreen(state: widget.state, conversation: conversation),
      context,
    );
  }

  Future<void> openUserProfileByUid(
    int uid,
    _CommandPaletteActionContext context,
  ) async {
    final navigator = context.navigator;
    if (navigator == null) {
      return;
    }
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => UserProfileScreen(state: widget.state, uid: uid),
      ),
    );
  }

  Future<void> openChat(
    Conversation conversation,
    _CommandPaletteActionContext context,
  ) async {
    final navigator = context.navigator;
    if (navigator == null) {
      return;
    }
    await widget.state.markConversationRead(conversation);
    widget.state.setActiveConversation(conversation);
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ChatScreen(state: widget.state, conversation: conversation),
      ),
    );
    await widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final matches = filteredActions(context, query);
    return Drawer(
      width: math.min(MediaQuery.sizeOf(context).width * 0.86, 360),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 12, 10),
              child: Row(
                children: [
                  Icon(Icons.terminal_rounded, color: colors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.strings.text('Commands'),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: context.strings.text('Close'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                controller: search,
                textInputAction: TextInputAction.search,
                onChanged: (value) => setState(() => query = value),
                onSubmitted: (_) {
                  if (matches.isNotEmpty) {
                    unawaited(runAction(matches.first));
                  }
                },
                decoration: InputDecoration(
                  hintText: context.strings.text('Type a command'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: context.strings.text('Clear'),
                          onPressed: () {
                            search.clear();
                            setState(() => query = '');
                          },
                          icon: const Icon(Icons.close),
                        ),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            Divider(height: 1, color: colors.outlineVariant),
            Expanded(
              child: matches.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          context.strings.text('No matching commands.'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: actionsScroll,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: matches.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 2),
                      itemBuilder: (context, index) {
                        final action = matches[index];
                        return _MobileCommandTile(
                          action: action,
                          usage: usage[action.id],
                          onTap: () => unawaited(runAction(action)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileCommandTile extends StatelessWidget {
  const _MobileCommandTile({
    required this.action,
    required this.onTap,
    this.usage,
  });

  final _CommandPaletteAction action;
  final VoidCallback onTap;
  final CommandPaletteUsage? usage;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final usage = this.usage;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: _RoundedInkClip(
        child: ListTile(
          minVerticalPadding: 12,
          leading: Icon(action.icon, color: colors.primary),
          title: Text(action.title),
          subtitle: Text(
            action.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: usage == null
              ? const Icon(Icons.chevron_right)
              : Text(
                  usage.count > 1
                      ? context.strings.format('Used {count} times', {
                          'count': usage.count,
                        })
                      : context.strings.text('Recent'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.onTap,
    required this.onLongPress,
    this.draft,
    this.preference = ConversationLocalPreference.defaults,
    this.subtitleMode = ConversationSubtitleMode.recentMessage,
    this.selected = false,
  });

  final Conversation conversation;
  final ConversationDraft? draft;
  final ConversationLocalPreference preference;
  final ConversationSubtitleMode subtitleMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final isGroup = conversation.type == ConversationType.group;
    final colors = Theme.of(context).colorScheme;
    final draft = this.draft;
    final hasDraft = draft != null && draft.hasContent;
    final fallbackSubtitle = context.strings.text(
      isGroup ? 'Group chat' : 'Private chat',
    );
    final statusFallback = conversation.subtitle.trim().isNotEmpty
        ? conversation.subtitle.trim()
        : fallbackSubtitle;
    final preferredSubtitle = switch (subtitleMode) {
      ConversationSubtitleMode.recentMessage =>
        conversation.lastMessagePreview.trim().isNotEmpty
            ? conversation.lastMessagePreview.trim()
            : fallbackSubtitle,
      ConversationSubtitleMode.status =>
        conversation.statusSubtitle.trim().isNotEmpty
            ? conversation.statusSubtitle.trim()
            : statusFallback,
    };
    final subtitleText = hasDraft
        ? context.strings.format('Draft: {text}', {
            'text': compactDraftText(draft.previewText, max: 72),
          })
        : preferredSubtitle;
    return GestureDetector(
      onSecondaryTap: onLongPress,
      child: Card(
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 5),
        color: selected ? colors.secondaryContainer : null,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: _RoundedInkClip(
          child: ListTile(
            selected: selected,
            selectedColor: colors.onSecondaryContainer,
            selectedTileColor: colors.secondaryContainer,
            onTap: onTap,
            onLongPress: onLongPress,
            leading: _ConversationAvatarHero(
              conversation: conversation,
              radius: 22,
            ),
            title: Row(
              children: [
                if (preference.pinned) ...[
                  Icon(Icons.push_pin, size: 15, color: colors.primary),
                  const SizedBox(width: 4),
                ],
                if (conversation.hidden) ...[
                  Icon(
                    Icons.visibility_off_outlined,
                    size: 16,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: _ConversationTitleHero(
                    conversation: conversation,
                    enabled: !selected,
                  ),
                ),
              ],
            ),
            subtitle: Text(
              subtitleText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: hasDraft ? TextStyle(color: colors.primary) : null,
            ),
            trailing: conversation.unreadCount > 0
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (preference.muted) ...[
                        Icon(
                          Icons.notifications_off_outlined,
                          size: 18,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Badge(
                        backgroundColor: preference.muted
                            ? colors.surfaceContainerHighest
                            : null,
                        textColor: preference.muted
                            ? colors.onSurfaceVariant
                            : null,
                        label: Text('${conversation.unreadCount}'),
                      ),
                    ],
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (preference.muted)
                        Icon(
                          Icons.notifications_off_outlined,
                          size: 18,
                          color: colors.onSurfaceVariant,
                        ),
                      if (preference.archived) ...[
                        if (preference.muted) const SizedBox(width: 8),
                        Icon(
                          Icons.archive_outlined,
                          size: 18,
                          color: colors.onSurfaceVariant,
                        ),
                      ],
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
