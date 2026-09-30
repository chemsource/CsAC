part of '../../main.dart';

class EmAppsScreen extends StatefulWidget {
  const EmAppsScreen({
    super.key,
    required this.state,
    this.embedded = false,
    this.initialAppId,
  });

  final CsacAppState state;
  final bool embedded;
  final String? initialAppId;

  @override
  State<EmAppsScreen> createState() => _EmAppsScreenState();
}

class _EmAppsScreenState extends State<EmAppsScreen> {
  late final TextEditingController search;
  List<EmAppPackage> apps = const <EmAppPackage>[];
  bool loading = false;
  String? error;
  Timer? searchDebounce;
  String? openedInitialAppId;

  @override
  void initState() {
    super.initState();
    search = TextEditingController()..addListener(scheduleSearch);
    unawaited(loadCatalog());
    WidgetsBinding.instance.addPostFrameCallback((_) => openInitialApp());
  }

  @override
  void didUpdateWidget(covariant EmAppsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialAppId != widget.initialAppId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => openInitialApp());
    }
  }

  @override
  void dispose() {
    searchDebounce?.cancel();
    search.removeListener(scheduleSearch);
    search.dispose();
    super.dispose();
  }

  void scheduleSearch() {
    searchDebounce?.cancel();
    searchDebounce = Timer(360.ms, () => loadCatalog());
  }

  Future<void> openInitialApp() async {
    final appId = widget.initialAppId?.trim() ?? '';
    if (appId.isEmpty || openedInitialAppId == appId || !mounted) {
      return;
    }
    openedInitialAppId = appId;
    await openDetail(appId);
  }

  Future<void> loadCatalog() async {
    if (!mounted) {
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final loaded = await widget.state.emAppsClient.catalog(
        keyword: search.text,
      );
      if (mounted) {
        setState(() => apps = loaded);
      }
    } catch (err) {
      if (mounted) {
        setState(() => error = err.toString());
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> openDetail(String appId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EmAppDetailScreen(state: widget.state, appId: appId),
      ),
    );
  }

  Future<void> openLogs() {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EmAppsLogScreen(state: widget.state),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final body = RefreshIndicator(
      onRefresh: loadCatalog,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _EmAppsHeader(
            title: strings.text('eMApps'),
            subtitle: widget.state.emAppsClient.baseUrl,
            action: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                IconButton.filledTonal(
                  tooltip: strings.text('Debug logs'),
                  onPressed: openLogs,
                  icon: const Icon(Icons.terminal_outlined),
                ),
                IconButton.filledTonal(
                  tooltip: strings.text('Refresh'),
                  onPressed: loading ? null : loadCatalog,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => loadCatalog(),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              labelText: strings.text('Search eMApps'),
              border: const OutlineInputBorder(),
              suffixIcon: search.text.trim().isEmpty
                  ? null
                  : IconButton(
                      tooltip: strings.text('Clear'),
                      onPressed: () {
                        search.clear();
                        unawaited(loadCatalog());
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          if (loading) const LinearProgressIndicator(),
          if (error != null)
            _EmAppsErrorPanel(message: error!, onRetry: loadCatalog)
          else if (!loading && apps.isEmpty)
            _EmptyPanel(message: strings.text('No eMApps found.'))
          else
            Card(
              elevation: 0,
              child: _RoundedInkClip(
                child: Column(
                  children: [
                    for (var i = 0; i < apps.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _EmAppPackageTile(
                        package: apps[i],
                        onTap: () => openDetail(apps[i].appId),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (widget.embedded) {
      return SafeArea(child: body);
    }
    return Scaffold(
      appBar: AppBar(title: Text(strings.text('eMApps'))),
      body: body,
    );
  }
}

class EmAppDetailScreen extends StatefulWidget {
  const EmAppDetailScreen({
    super.key,
    required this.state,
    required this.appId,
  });

  final CsacAppState state;
  final String appId;

  @override
  State<EmAppDetailScreen> createState() => _EmAppDetailScreenState();
}

class _EmAppDetailScreenState extends State<EmAppDetailScreen> {
  EmAppPackage? package;
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    unawaited(loadInfo());
  }

  Future<void> loadInfo() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final loaded = await widget.state.emAppsClient.info(widget.appId);
      if (mounted) {
        setState(() => package = loaded);
      }
    } catch (err) {
      if (mounted) {
        setState(() => error = err.toString());
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> openRunner() async {
    final appId = (package?.appId ?? widget.appId).trim();
    if (appId.isEmpty) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EmAppRunnerScreen(state: widget.state, appId: appId),
      ),
    );
  }

  Future<void> shareLink() async {
    final appId = (package?.appId ?? widget.appId).trim();
    if (appId.isEmpty) {
      return;
    }
    await SharePlus.instance.share(ShareParams(text: csacEmAppDeepLink(appId)));
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final info = package;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          info?.name.trim().isNotEmpty == true ? info!.name : widget.appId,
        ),
        actions: [
          IconButton(
            tooltip: strings.text('Share'),
            onPressed: shareLink,
            icon: const Icon(Icons.ios_share_outlined),
          ),
          IconButton(
            tooltip: strings.text('Refresh'),
            onPressed: loading ? null : loadInfo,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            if (loading) const LinearProgressIndicator(),
            if (error != null)
              _EmAppsErrorPanel(message: error!, onRetry: loadInfo)
            else if (info == null)
              _EmptyPanel(message: strings.text('Loading eMApp...'))
            else ...[
              Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _EmAppIcon(name: info.name, size: 58),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  info.name.trim().isEmpty
                                      ? info.appId
                                      : info.name,
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 4),
                                SelectableText(info.appId),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (info.description.trim().isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(info.description),
                      ],
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _EmAppInfoChip(
                            icon: Icons.new_releases_outlined,
                            label: strings.format('Version {version}', {
                              'version': info.version,
                            }),
                          ),
                          _EmAppInfoChip(
                            icon: Icons.data_object_outlined,
                            label: _formatEmAppBytes(info.packageSize),
                          ),
                          _EmAppInfoChip(
                            icon: Icons.article_outlined,
                            label: info.entryPage,
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
                child: _RoundedInkClip(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.verified_user_outlined),
                        title: Text(strings.text('Signature verification')),
                        subtitle: Text(
                          strings.text(
                            'The package will only run after SHA-256 and RSA verification pass.',
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.fingerprint),
                        title: Text(strings.text('SHA-256')),
                        subtitle: SelectableText(
                          info.fileHash.isEmpty ? '-' : info.fileHash,
                          maxLines: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: openRunner,
                icon: const Icon(Icons.play_arrow),
                label: Text(strings.text('Open eMApp')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class EmAppRunnerScreen extends StatefulWidget {
  const EmAppRunnerScreen({
    super.key,
    required this.state,
    required this.appId,
  });

  final CsacAppState state;
  final String appId;

  @override
  State<EmAppRunnerScreen> createState() => _EmAppRunnerScreenState();
}

class _EmAppRunnerScreenState extends State<EmAppRunnerScreen> {
  EmAppRuntime? runtime;
  EmAppLaunchResult? launch;
  webview_all.WebViewController? controller;
  bool loading = false;
  bool showLogs = false;
  int progress = 0;
  String status = '';
  String? error;
  final logs = <EmAppRuntimeLogEntry>[];

  // 节流：防 onProgress / addRuntimeLog 高频 setState 导致 WebView 闪烁
  int _lastProgressTimeMs = 0;
  int _logBatch = 0;
  Timer? _logTimer;
  // 缓存 WebViewWidget，只在 controller 或 showLogs 变化时重建
  webview_all.WebViewController? _cachedController;
  bool? _cachedShowLogs;
  Widget? _cachedWebView;
  final _webFrameKey = GlobalKey<EmAppWebFrameState>();

  @override
  void initState() {
    super.initState();
    unawaited(openApp());
  }

  @override
  void dispose() {
    _logTimer?.cancel();
    unawaited(launch?.close());
    super.dispose();
  }

  Future<void> openApp() async {
    setState(() {
      loading = true;
      error = null;
      status = contextFallbackText('Preparing eMApp...');
    });
    try {
      final nextRuntime = widget.state.createEmAppRuntime();
      final result = await nextRuntime.open(widget.appId);
      runtime = nextRuntime;
      logs
        ..clear()
        ..addAll(result.logs);
      launch = result;
      if (isWebPlatform) {
        // Web: iframe renders via EmAppWebFrame, no WebViewController needed
        if (!mounted) {
          await result.close();
          return;
        }
        setState(() {
          loading = false;
          status = '';
        });
        return;
      }
      final nextController = webview_all.WebViewController()
        ..setJavaScriptMode(webview_all.JavaScriptMode.unrestricted)
        ..setUserAgent('CsAC-Flutter-eMApps/1.0')
        ..addJavaScriptChannel(
          'CsacEmApps',
          onMessageReceived: handleBridgeMessage,
        )
        ..setOnConsoleMessage((message) {
          addRuntimeLog('WEBVIEW', '${message.level.name}: ${message.message}');
        })
        ..setNavigationDelegate(
          webview_all.NavigationDelegate(
            onProgress: (value) {
              final now = DateTime.now().millisecondsSinceEpoch;
              if (!mounted || now - _lastProgressTimeMs < 80) return;
              _lastProgressTimeMs = now;
              setState(() => progress = value);
            },
            onPageStarted: (url) {
              addRuntimeLog('WEBVIEW', 'Started $url');
            },
            onPageFinished: (url) {
              addRuntimeLog('WEBVIEW', 'Finished $url');
              unawaited(injectBridge());
            },
            onWebResourceError: (err) {
              addRuntimeLog('WEBVIEW', err.description);
            },
            onNavigationRequest: (request) {
              final uri = Uri.tryParse(request.url);
              final host = launch?.url.host;
              if (uri != null &&
                  (uri.scheme == 'http' || uri.scheme == 'https') &&
                  uri.host == host) {
                return webview_all.NavigationDecision.navigate;
              }
              addRuntimeLog('WEBVIEW', 'Blocked navigation ${request.url}');
              return webview_all.NavigationDecision.prevent;
            },
          ),
        );
      controller = nextController;
      await nextController.loadRequest(result.url);
      if (!mounted) {
        await result.close();
        return;
      }
      setState(() {
        loading = false;
        status = '';
      });
    } catch (err) {
      if (mounted) {
        setState(() {
          error = err.toString();
          loading = false;
          status = '';
        });
      }
    }
  }

  String contextFallbackText(String key) {
    try {
      return context.strings.text(key);
    } catch (_) {
      return key;
    }
  }

  void addRuntimeLog(String kind, String message) {
    final entry = EmAppRuntimeLogEntry(
      kind: kind,
      message: message,
      time: DateTime.now(),
    );
    logs.add(entry);
    if (logs.length > 300) {
      logs.removeRange(0, logs.length - 300);
    }
    // 批量刷新：每 5 条日志或 200ms 后才 setState，避免高频重建
    _logBatch++;
    if (_logBatch >= 5) {
      _logBatch = 0;
      _logTimer?.cancel();
      if (mounted) setState(() {});
    } else {
      _logTimer?.cancel();
      _logTimer = Timer(const Duration(milliseconds: 200), () {
        _logBatch = 0;
        if (mounted) setState(() {});
      });
    }
  }

  Future<void> injectBridge() async {
    final web = controller;
    if (web == null) {
      return;
    }
    await web.runJavaScript(_emAppsBridgeScript);
  }

  Future<void> handleBridgeMessage(
    webview_all.JavaScriptMessage message,
  ) async {
    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(message.message);
      if (decoded is! Map) {
        throw const FormatException('Invalid bridge payload.');
      }
      payload = decoded.map((key, value) => MapEntry(key.toString(), value));
    } catch (err) {
      addRuntimeLog('WEBVIEW', 'Bridge parse failed: $err');
      return;
    }
    final id = payload['id']?.toString() ?? '';
    final method = payload['method']?.toString() ?? '';
    final args = payload['args'];
    Object result;
    try {
      result = await callBridgeMethod(method, args);
      await completeBridgeCall(id, success: true, value: result);
    } catch (err) {
      await completeBridgeCall(
        id,
        success: false,
        value: {'success': false, 'message': err.toString()},
      );
    }
  }

  Future<Object> callBridgeMethod(String method, Object? args) async {
    addRuntimeLog('WEBVIEW', 'Bridge call $method');
    switch (method) {
      case 'chat.openChat':
        final uid = _bridgeInt(args, 'uid');
        if (uid <= 0) {
          return {'success': false, 'message': 'Invalid uid.'};
        }
        final conversation = widget.state.conversations
            .where(
              (item) => item.type == ConversationType.private && item.id == uid,
            )
            .firstOrNull;
        if (conversation == null || !mounted) {
          return {
            'success': false,
            'message': 'No private chat context found.',
          };
        }
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                ChatScreen(state: widget.state, conversation: conversation),
          ),
        );
        return {'success': true};
      case 'chat.sendMessage':
        final text = _bridgeString(args, 'text').trim();
        final conversation = widget.state.activeConversation;
        if (text.isEmpty) {
          return {'success': false, 'message': 'Message text is empty.'};
        }
        if (conversation == null) {
          return {
            'success': false,
            'message': 'No active chat context for direct sending.',
          };
        }
        await widget.state.client.sendMessage(conversation, text);
        return {'success': true};
      default:
        return {'success': false, 'message': 'Unknown method: $method'};
    }
  }

  Future<void> completeBridgeCall(
    String id, {
    required bool success,
    required Object value,
  }) async {
    final web = controller;
    if (web == null || id.isEmpty) {
      return;
    }
    final payload = jsonEncode({'id': id, 'success': success, 'value': value});
    await web.runJavaScript(
      'window.__emapps_bridge && window.__emapps_bridge.__complete($payload);',
    );
  }

  KeyEventResult handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.f11 &&
        HardwareKeyboard.instance.isControlPressed &&
        HardwareKeyboard.instance.isShiftPressed &&
        HardwareKeyboard.instance.isAltPressed) {
      setState(() => showLogs = !showLogs);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final title = launch?.package.name.trim().isNotEmpty == true
        ? launch!.package.name
        : widget.appId;
    return Focus(
      autofocus: true,
      onKeyEvent: handleKey,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            IconButton(
              tooltip: strings.text('Debug logs'),
              onPressed: () => setState(() => showLogs = !showLogs),
              icon: const Icon(Icons.terminal_outlined),
            ),
            IconButton(
              tooltip: strings.text('Reload'),
              onPressed: () {
                if (isWebPlatform) {
                  _webFrameKey.currentState?.reload();
                } else if (controller != null) {
                  unawaited(controller!.reload());
                }
              },
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: progress > 0 && progress < 100
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: LinearProgressIndicator(value: progress / 100),
                )
              : null,
        ),
        body: SafeArea(
          child: Builder(
            builder: (context) {
              if (error != null) {
                return _EmAppsCenteredMessage(
                  icon: Icons.error_outline,
                  title: strings.text('Unable to open eMApp'),
                  message: error!,
                  action: FilledButton.icon(
                    onPressed: loading ? null : openApp,
                    icon: const Icon(Icons.refresh),
                    label: Text(strings.text('Retry')),
                  ),
                );
              }
              if (loading ||
                  (!isWebPlatform && controller == null) ||
                  (isWebPlatform && launch == null)) {
                return _EmAppsCenteredMessage(
                  icon: Icons.apps_outlined,
                  title: status.isEmpty
                      ? strings.text('Preparing eMApp...')
                      : status,
                  message: strings.text(
                    'Downloading, verifying and starting the local runtime.',
                  ),
                  action: const CircularProgressIndicator(),
                );
              }

              Widget webView;
              if (isWebPlatform) {
                webView = EmAppWebFrame(
                  key: _webFrameKey,
                  url: launch!.url.toString(),
                  htmlContent: launch!.htmlContent,
                  onBridgeMessage: (method, args) =>
                      callBridgeMethod(method, args),
                  onLog: addRuntimeLog,
                );
              } else {
                // 缓存 WebViewWidget：只在 controller 或 showLogs 变化时重建
                if (_cachedController != controller ||
                    _cachedShowLogs != showLogs ||
                    _cachedWebView == null) {
                  _cachedController = controller;
                  _cachedShowLogs = showLogs;
                  _cachedWebView = webview_all.WebViewWidget(
                    controller: controller!,
                    key: ValueKey(showLogs),
                  );
                }
                webView = _cachedWebView!;
              }

              if (!showLogs) {
                return webView;
              }
              return Stack(
                children: [
                  Positioned.fill(child: webView),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: _EmAppsFloatingLogs(logs: logs),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class EmAppsLogScreen extends StatefulWidget {
  const EmAppsLogScreen({super.key, required this.state});

  final CsacAppState state;

  @override
  State<EmAppsLogScreen> createState() => _EmAppsLogScreenState();
}

class _EmAppsLogScreenState extends State<EmAppsLogScreen> {
  List<EmAppRuntimeLogEntry> logs = const <EmAppRuntimeLogEntry>[];
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    unawaited(loadLogs());
  }

  Future<void> loadLogs() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final runtime = widget.state.createEmAppRuntime();
      final loaded = await runtime.loadStoredLogs();
      if (mounted) {
        setState(() => logs = loaded);
      }
    } catch (err) {
      if (mounted) {
        setState(() => error = err.toString());
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> clearCacheAndLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.strings.text('Clear eMApps cache?')),
        content: Text(
          context.strings.text(
            'Downloaded runtime files and eMApps debug logs on this device will be removed.',
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
    final runtime = widget.state.createEmAppRuntime();
    await runtime.clearStoredData();
    await loadLogs();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.text('eMApps cache cleared.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.text('eMApps debug logs')),
        actions: [
          IconButton(
            tooltip: strings.text('Clear'),
            onPressed: clearCacheAndLogs,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
          IconButton(
            tooltip: strings.text('Refresh'),
            onPressed: loading ? null : loadLogs,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: loadLogs,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              if (loading) const LinearProgressIndicator(),
              if (error != null)
                _EmAppsErrorPanel(message: error!, onRetry: loadLogs)
              else if (logs.isEmpty)
                _EmptyPanel(message: strings.text('No eMApps logs.'))
              else
                Card(
                  elevation: 0,
                  child: _RoundedInkClip(
                    child: Column(
                      children: [
                        for (var i = 0; i < logs.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          ListTile(
                            dense: true,
                            leading: _EmAppsLogIcon(kind: logs[i].kind),
                            title: SelectableText(logs[i].message),
                            subtitle: Text(
                              '${formatLocalDateTime(logs[i].time)} | ${logs[i].kind}',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmAppPackageTile extends StatelessWidget {
  const _EmAppPackageTile({required this.package, required this.onTap});

  final EmAppPackage package;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = package.name.trim().isEmpty ? package.appId : package.name;
    return ListTile(
      leading: _EmAppIcon(name: title),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          package.appId,
          context.strings.format('Version {version}', {
            'version': package.version,
          }),
          _formatEmAppBytes(package.packageSize),
          if (package.description.trim().isNotEmpty) package.description.trim(),
        ].join(' | '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _EmAppIcon extends StatelessWidget {
  const _EmAppIcon({required this.name, this.size = 42});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final seed = name.codeUnits.fold<int>(0, (sum, item) => sum + item);
    final palette = [
      colors.primaryContainer,
      colors.secondaryContainer,
      colors.tertiaryContainer,
      colors.surfaceContainerHighest,
    ];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: palette[seed % palette.length],
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        Icons.apps_rounded,
        color: colors.onPrimaryContainer,
        size: size * 0.56,
      ),
    );
  }
}

class _EmAppsHeader extends StatelessWidget {
  const _EmAppsHeader({
    required this.title,
    required this.subtitle,
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    if (action == null) {
      return text;
    }
    return Row(
      children: [
        Expanded(child: text),
        const SizedBox(width: 12),
        action!,
      ],
    );
  }
}

class _EmAppsErrorPanel extends StatelessWidget {
  const _EmAppsErrorPanel({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(context.strings.text('Retry')),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmAppInfoChip extends StatelessWidget {
  const _EmAppInfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _EmAppsCenteredMessage extends StatelessWidget {
  const _EmAppsCenteredMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 46, color: colors.primary),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: 16), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmAppsFloatingLogs extends StatelessWidget {
  const _EmAppsFloatingLogs({required this.logs});

  final List<EmAppRuntimeLogEntry> logs;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      elevation: 6,
      color: colors.surface.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: ListView.builder(
          padding: const EdgeInsets.all(10),
          shrinkWrap: true,
          itemCount: logs.length,
          itemBuilder: (context, index) {
            final log = logs[index];
            return Text(
              '${formatLocalTime(log.time)} ${log.kind} ${log.message}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            );
          },
        ),
      ),
    );
  }
}

class _EmAppsLogIcon extends StatelessWidget {
  const _EmAppsLogIcon({required this.kind});

  final String kind;

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case 'NET':
        return const Icon(Icons.cloud_sync_outlined);
      case 'CRYPTO':
        return const Icon(Icons.verified_user_outlined);
      case 'HTTP':
        return const Icon(Icons.http_outlined);
      case 'WEBVIEW':
        return const Icon(Icons.web_asset_outlined);
      default:
        return const Icon(Icons.apps_outlined);
    }
  }
}

const _emAppsBridgeScript = '''
(function() {
  if (window.__emapps_bridge && window.__emapps_bridge.__installed) return;
  var pending = {};
  var serial = 1;
  window.__emapps_bridge = {
    __installed: true,
    call: function(method, args) {
      return new Promise(function(resolve, reject) {
        var id = String(serial++);
        pending[id] = { resolve: resolve, reject: reject };
        CsacEmApps.postMessage(JSON.stringify({
          id: id,
          method: method,
          args: args || {}
        }));
      });
    },
    __complete: function(payload) {
      var item = pending[payload.id];
      if (!item) return;
      delete pending[payload.id];
      if (payload.success) item.resolve(payload.value);
      else item.reject(payload.value);
    }
  };
  window.chat = window.chat || {};
  window.chat.openChat = function(uid) {
    return window.__emapps_bridge.call('chat.openChat', { uid: uid });
  };
  window.chat.sendMessage = function(text) {
    return window.__emapps_bridge.call('chat.sendMessage', { text: text });
  };
})();
''';

String _formatEmAppBytes(int bytes) {
  if (bytes <= 0) {
    return '0 B';
  }
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  final decimals = value >= 10 || unit == 0 ? 0 : 1;
  return '${value.toStringAsFixed(decimals)} ${units[unit]}';
}

int _bridgeInt(Object? args, String key) {
  if (args is Map) {
    return asInt(args[key]);
  }
  if (args is List && args.isNotEmpty) {
    return asInt(args.first);
  }
  return asInt(args);
}

String _bridgeString(Object? args, String key) {
  if (args is Map) {
    return asString(args[key]);
  }
  if (args is List && args.isNotEmpty) {
    return asString(args.first);
  }
  return asString(args);
}
