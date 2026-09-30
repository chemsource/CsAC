part of '../../main.dart';

enum _AcopAuthMode { password, code, register }

class AcopLoginScreen extends StatefulWidget {
  const AcopLoginScreen({super.key, required this.state});

  final CsacAppState state;

  @override
  State<AcopLoginScreen> createState() => _AcopLoginScreenState();
}

class _AcopLoginScreenState extends State<AcopLoginScreen> {
  late final TextEditingController serverUrl;
  final email = TextEditingController();
  final password = TextEditingController();
  final code = TextEditingController();
  final developerName = TextEditingController();
  final csacUsername = TextEditingController();
  final csacPassword = TextEditingController();
  Timer? codeTimer;
  _AcopAuthMode mode = _AcopAuthMode.password;
  bool savingServer = false;
  bool sendingCode = false;
  int codeResendRemaining = 0;
  int codeExpiresIn = 600;
  String? message;
  String? error;

  @override
  void initState() {
    super.initState();
    serverUrl = TextEditingController(
      text: widget.state.preferences.acopServerUrl,
    );
  }

  @override
  void dispose() {
    codeTimer?.cancel();
    serverUrl.dispose();
    email.dispose();
    password.dispose();
    code.dispose();
    developerName.dispose();
    csacUsername.dispose();
    csacPassword.dispose();
    super.dispose();
  }

  bool get canSendCode => !sendingCode && codeResendRemaining <= 0;

  void startCodeCountdown([int seconds = 60]) {
    codeTimer?.cancel();
    setState(() => codeResendRemaining = seconds <= 0 ? 60 : seconds);
    codeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (codeResendRemaining <= 1) {
        timer.cancel();
        setState(() => codeResendRemaining = 0);
        return;
      }
      setState(() => codeResendRemaining--);
    });
  }

  void changeMode(_AcopAuthMode value) {
    setState(() {
      mode = value;
      message = null;
      error = null;
    });
  }

  Future<void> saveServerIfNeeded() async {
    setState(() => savingServer = true);
    try {
      final changed = await widget.state.updateAcopServerUrl(serverUrl.text);
      if (!mounted) {
        return;
      }
      serverUrl.text = widget.state.preferences.acopServerUrl;
      if (changed) {
        setState(
          () => message = context.strings.text('ACOP server address saved.'),
        );
      }
    } finally {
      if (mounted) {
        setState(() => savingServer = false);
      }
    }
  }

  Future<void> sendCode() async {
    final strings = context.strings;
    final targetEmail = email.text.trim();
    if (!_looksLikeEmail(targetEmail)) {
      setState(() => error = strings.text('Please enter a valid email.'));
      return;
    }
    setState(() {
      sendingCode = true;
      message = null;
      error = null;
    });
    try {
      await saveServerIfNeeded();
      await widget.state.acopSendCode(
        targetEmail,
        mode == _AcopAuthMode.register ? 'register' : 'login',
      );
      if (!mounted) {
        return;
      }
      setState(
        () => message = strings.format(
          'Code sent. It expires in {minutes} minutes.',
          {'minutes': _durationMinutesLabel(codeExpiresIn)},
        ),
      );
      startCodeCountdown();
    } catch (err) {
      if (mounted) {
        setState(() => error = err.toString());
      }
    } finally {
      if (mounted) {
        setState(() => sendingCode = false);
      }
    }
  }

  bool validateBaseFields() {
    final strings = context.strings;
    if (!_looksLikeEmail(email.text.trim())) {
      setState(() => error = strings.text('Please enter a valid email.'));
      return false;
    }
    if (mode != _AcopAuthMode.code && password.text.isEmpty) {
      setState(() => error = strings.text('Email and password are required.'));
      return false;
    }
    if (mode != _AcopAuthMode.password && code.text.trim().length != 6) {
      setState(() => error = strings.text('Please enter the 6-digit code.'));
      return false;
    }
    return true;
  }

  Future<void> submit() async {
    if (widget.state.loading || savingServer) {
      return;
    }
    if (!validateBaseFields()) {
      return;
    }
    setState(() {
      error = null;
      message = null;
    });
    try {
      await saveServerIfNeeded();
      switch (mode) {
        case _AcopAuthMode.password:
          await widget.state.acopLogin(email.text.trim(), password.text);
          break;
        case _AcopAuthMode.code:
          await widget.state.acopLoginByCode(email.text.trim(), code.text);
          break;
        case _AcopAuthMode.register:
          if (developerName.text.trim().isEmpty ||
              csacUsername.text.trim().isEmpty ||
              csacPassword.text.isEmpty) {
            setState(
              () => error = context.strings.text('Please fill all fields.'),
            );
            return;
          }
          await widget.state.acopRegister(
            email: email.text.trim(),
            password: password.text,
            developerName: developerName.text.trim(),
            code: code.text.trim(),
            csacUsername: csacUsername.text.trim(),
            csacPassword: csacPassword.text,
          );
          break;
      }
    } catch (err) {
      if (mounted) {
        setState(() => error = err.toString());
      }
    }
  }

  Future<void> switchToChatMode() {
    return widget.state.switchClientMode(AppClientMode.csac);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final defaultServer = widget.state.preferences.acopServerUrl.trim().isEmpty;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.integration_instructions_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    strings.text('CsAC Open Platform'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    strings.text('Independent developer platform mode'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: serverUrl,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: strings.text('ACOP server address'),
                      helperText: defaultServer
                          ? strings.text(
                              'Leave empty to use the default server.',
                            )
                          : widget.state.acopClient.baseUrl,
                      prefixIcon: const Icon(Icons.dns_outlined),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<_AcopAuthMode>(
                    segments: [
                      ButtonSegment(
                        value: _AcopAuthMode.password,
                        icon: const Icon(Icons.lock_outline),
                        label: Text(strings.text('Password login')),
                      ),
                      ButtonSegment(
                        value: _AcopAuthMode.code,
                        icon: const Icon(Icons.pin_outlined),
                        label: Text(strings.text('Code login')),
                      ),
                      ButtonSegment(
                        value: _AcopAuthMode.register,
                        icon: const Icon(Icons.person_add_alt),
                        label: Text(strings.text('Register')),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: widget.state.loading
                        ? null
                        : (selection) => changeMode(selection.first),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: strings.text('Email'),
                      prefixIcon: const Icon(Icons.alternate_email),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (mode != _AcopAuthMode.code) ...[
                    TextField(
                      controller: password,
                      obscureText: true,
                      textInputAction: mode == _AcopAuthMode.register
                          ? TextInputAction.next
                          : TextInputAction.done,
                      onSubmitted: (_) => submit(),
                      decoration: InputDecoration(
                        labelText: strings.text('Password'),
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (mode != _AcopAuthMode.password) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _EmailCodeTextField(
                            controller: code,
                            label: strings.text('Email code'),
                            onSubmitted: (_) => submit(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          height: _emailCodeControlHeight,
                          child: OutlinedButton(
                            style: _emailCodeButtonStyle(),
                            onPressed:
                                canSendCode &&
                                    !widget.state.loading &&
                                    !sendingCode
                                ? sendCode
                                : null,
                            child: Text(
                              codeResendRemaining > 0
                                  ? strings.format('Resend in {seconds}s', {
                                      'seconds': codeResendRemaining,
                                    })
                                  : strings.text('Send code'),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      strings.format('Code expires in {minutes} minutes.', {
                        'minutes': _durationMinutesLabel(codeExpiresIn),
                      }),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (mode == _AcopAuthMode.register) ...[
                    TextField(
                      controller: developerName,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: strings.text('Developer name'),
                        prefixIcon: const Icon(Icons.badge_outlined),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: csacUsername,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: strings.text('CsAC username'),
                        prefixIcon: const Icon(Icons.person_outline),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: csacPassword,
                      obscureText: true,
                      onSubmitted: (_) => submit(),
                      decoration: InputDecoration(
                        labelText: strings.text('CsAC password'),
                        prefixIcon: const Icon(Icons.password_outlined),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (message != null) ...[
                    Text(
                      message!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (error != null) ...[
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  FilledButton.icon(
                    onPressed: widget.state.loading || savingServer
                        ? null
                        : submit,
                    icon: widget.state.loading || savingServer
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login),
                    label: Text(
                      strings.text(
                        mode == _AcopAuthMode.register ? 'Register' : 'Login',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: widget.state.loading ? null : switchToChatMode,
                    icon: const Icon(Icons.forum_outlined),
                    label: Text(strings.text('Switch to CsAC chat')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AcopPlatformShell extends StatefulWidget {
  const AcopPlatformShell({super.key, required this.state});

  final CsacAppState state;

  @override
  State<AcopPlatformShell> createState() => _AcopPlatformShellState();
}

class _AcopPlatformShellState extends State<AcopPlatformShell> {
  late final TextEditingController serverUrl;
  int selectedIndex = 0;
  List<AcopBot> bots = const <AcopBot>[];
  List<AcopBot> adminBots = const <AcopBot>[];
  List<AcopAcrUpload> pendingAcrUploads = const <AcopAcrUpload>[];
  List<AcopEmaUpload> pendingEmaUploads = const <AcopEmaUpload>[];
  bool loadingBots = false;
  bool loadingAdminBots = false;
  bool loadingPendingAcr = false;
  bool loadingPendingEma = false;
  bool savingServer = false;
  String? botsError;
  String? adminError;
  String? pendingAcrError;
  String? pendingEmaError;
  List<AcopLibUpload> pendingLibs = const <AcopLibUpload>[];
  bool loadingPendingLibs = false;
  String? pendingLibsError;
  String _botSearchQuery = '';
  String _botFilter = 'all';

  @override
  void initState() {
    super.initState();
    serverUrl = TextEditingController(
      text: widget.state.preferences.acopServerUrl,
    );
    unawaited(refreshBots());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(showQuickEditNoticeIfNeeded());
    });
  }

  @override
  void dispose() {
    serverUrl.dispose();
    super.dispose();
  }

  Future<void> refreshBots() async {
    if (loadingBots) {
      return;
    }
    setState(() {
      loadingBots = true;
      botsError = null;
    });
    try {
      final loaded = await widget.state.acopClient.listBots();
      if (mounted) {
        setState(() => bots = loaded);
      }
    } catch (err) {
      if (mounted) {
        setState(() => botsError = err.toString());
      }
    } finally {
      if (mounted) {
        setState(() => loadingBots = false);
      }
    }
  }

  Future<void> refreshAdminBots() async {
    if (loadingAdminBots) {
      return;
    }
    setState(() {
      loadingAdminBots = true;
      adminError = null;
    });
    try {
      final loaded = await widget.state.acopClient.listAdminBots();
      if (mounted) {
        setState(() => adminBots = loaded);
      }
    } catch (err) {
      if (mounted) {
        setState(() => adminError = err.toString());
      }
    } finally {
      if (mounted) {
        setState(() => loadingAdminBots = false);
      }
    }
  }

  Future<void> refreshPendingAcrUploads() async {
    if (loadingPendingAcr) {
      return;
    }
    setState(() {
      loadingPendingAcr = true;
      pendingAcrError = null;
    });
    try {
      final loaded = await widget.state.acopClient.listPendingAcrUploads();
      if (mounted) {
        setState(() => pendingAcrUploads = loaded);
      }
    } catch (err) {
      if (mounted) {
        setState(() => pendingAcrError = err.toString());
      }
    } finally {
      if (mounted) {
        setState(() => loadingPendingAcr = false);
      }
    }
  }

  Future<void> refreshPendingEmaUploads() async {
    if (loadingPendingEma) {
      return;
    }
    setState(() {
      loadingPendingEma = true;
      pendingEmaError = null;
    });
    try {
      final loaded = await widget.state.acopClient.listPendingEmaUploads();
      if (mounted) {
        setState(() => pendingEmaUploads = loaded);
      }
    } catch (err) {
      if (mounted) {
        setState(() => pendingEmaError = err.toString());
      }
    } finally {
      if (mounted) {
        setState(() => loadingPendingEma = false);
      }
    }
  }

  void showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> showQuickEditNoticeIfNeeded() async {
    if (await AcopQuickEditNoticeStore.isSeen()) {
      return;
    }
    await AcopQuickEditNoticeStore.markSeen();
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.strings.text('ACOP quick edit mode')),
        content: Text(
          context.strings.text(
            'This mode is only for quick editing. For more features, please use the website: https://acop.csac.chat/',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.strings.text('Got it')),
          ),
          FilledButton.icon(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final copiedText = context.strings.text('Link copied.');
              final opened = await launchUrl(
                Uri.parse('https://acop.csac.chat/'),
                mode: LaunchMode.externalApplication,
              );
              if (!opened) {
                await Clipboard.setData(
                  const ClipboardData(text: 'https://acop.csac.chat/'),
                );
                showSnack(copiedText);
              }
              if (navigator.mounted) {
                navigator.pop();
              }
            },
            icon: const Icon(Icons.open_in_new),
            label: Text(context.strings.text('Open website')),
          ),
        ],
      ),
    );
  }

  Future<void> createBot() async {
    final draft = await showDialog<_AcopBotDraft>(
      context: context,
      builder: (context) => const _AcopBotDialog(),
    );
    if (draft == null || !mounted) {
      return;
    }
    try {
      final created = await widget.state.acopClient.createBot(
        botName: draft.name,
        botDesc: draft.description,
      );
      await refreshBots();
      if (!mounted) {
        return;
      }
      if (created.botToken.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (context) => _AcopTokenDialog(token: created.botToken),
        );
      } else {
        showSnack(context.strings.text('Bot created.'));
      }
    } catch (err) {
      showSnack(err.toString());
    }
  }

  Future<void> editBot(AcopBot bot) async {
    final strings = context.strings;
    final draft = await showDialog<_AcopBotDraft>(
      context: context,
      builder: (context) => _AcopBotDialog(bot: bot),
    );
    if (draft == null || !mounted) {
      return;
    }
    try {
      await widget.state.acopClient.updateBot(
        botId: bot.botId,
        botName: draft.name,
        botDesc: draft.description,
      );
      await refreshBots();
      showSnack(strings.text('Saved.'));
    } catch (err) {
      showSnack(err.toString());
    }
  }

  Future<void> uploadBotAvatar(AcopBot bot) async {
    final strings = context.strings;
    try {
      final picked = isMobilePlatform
          ? await pickImageForMobileGallery()
          : await openFile(
              acceptedTypeGroups: <XTypeGroup>[
                XTypeGroup(
                  label: strings.text('Images'),
                  extensions: _acopAvatarExtensions,
                ),
              ],
            );
      if (picked == null || !mounted) {
        return;
      }
      final bytes = await picked.readAsBytes();
      await widget.state.acopClient.uploadBotAvatar(
        botId: bot.botId,
        avatarBytes: bytes,
        fileName: picked.name,
      );
      await refreshBots();
      showSnack(strings.text('Bot avatar updated.'));
    } catch (err) {
      showSnack(
        friendlyMobileFileError(
          strings,
          err,
          fallbackKey: 'Image selection failed: {error}',
        ),
      );
    }
  }

  Future<void> resetBotToken(AcopBot bot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.strings.text('Reset bot token?')),
        content: Text(
          context.strings.text('The old token will stop working after reset.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.strings.text('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.strings.text('Reset token')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      final token = await widget.state.acopClient.resetBotToken(bot.botId);
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => _AcopTokenDialog(token: token),
      );
    } catch (err) {
      showSnack(err.toString());
    }
  }

  Future<void> deleteBot(AcopBot bot) async {
    final strings = context.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.strings.text('Delete bot?')),
        content: Text(
          context.strings.format('Delete {name} permanently?', {
            'name': bot.botName,
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.strings.text('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.strings.text('Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await widget.state.acopClient.deleteBot(bot.botId);
      await refreshBots();
      showSnack(strings.text('Deleted.'));
    } catch (err) {
      showSnack(err.toString());
    }
  }

  Future<void> openBot(AcopBot bot) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AcopBotDetailScreen(state: widget.state, bot: bot),
      ),
    );
    if (mounted) {
      await refreshBots();
    }
  }

  Future<void> saveServer() async {
    final strings = context.strings;
    setState(() => savingServer = true);
    try {
      final changed = await widget.state.updateAcopServerUrl(serverUrl.text);
      if (!mounted) {
        return;
      }
      serverUrl.text = widget.state.preferences.acopServerUrl;
      if (changed) {
        showSnack(
          strings.text('ACOP server address saved. Please log in again.'),
        );
      } else {
        showSnack(strings.text('Server address is unchanged.'));
      }
    } on FormatException {
      showSnack(strings.text('Invalid server address.'));
    } catch (err) {
      showSnack(err.toString());
    } finally {
      if (mounted) {
        setState(() => savingServer = false);
      }
    }
  }

  Future<void> logout() async {
    try {
      await widget.state.acopLogout();
    } catch (err) {
      showSnack(err.toString());
    }
  }

  Future<void> switchToChatMode() {
    return widget.state.switchClientMode(AppClientMode.csac);
  }

  Future<void> handlePermissionById() async {
    final strings = context.strings;
    final draft = await showDialog<_AcopAdminPermissionDraft>(
      context: context,
      builder: (context) => const _AcopAdminPermissionDialog(),
    );
    if (draft == null || !mounted) {
      return;
    }
    try {
      await widget.state.acopClient.handlePermissionRequest(
        requestId: draft.requestId,
        action: draft.action,
        adminReply: draft.reply,
      );
      showSnack(strings.text('Permission request handled.'));
      await refreshAdminBots();
    } catch (err) {
      showSnack(err.toString());
    }
  }

  Future<void> runSaveChainDiagnostic() async {
    final draft = await showDialog<_AcopSaveDiagnosticDraft>(
      context: context,
      builder: (context) => const _AcopSaveDiagnosticDialog(),
    );
    if (draft == null || !mounted) {
      return;
    }
    try {
      final result = await widget.state.acopClient.runSaveChainDiagnostic(
        name: draft.name,
        content: draft.content,
        mode: draft.mode,
      );
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => _AcopJsonResultDialog(
          title: context.strings.text('Save-chain diagnostic'),
          value: result,
        ),
      );
    } catch (err) {
      showSnack(err.toString());
    }
  }

  Future<void> reviewLibUpload() async {
    final strings = context.strings;
    final draft = await showDialog<_AcopLibReviewDraft>(
      context: context,
      builder: (context) => const _AcopLibReviewDialog(),
    );
    if (draft == null || !mounted) {
      return;
    }
    try {
      final result = await widget.state.acopClient.reviewLibUpload(
        id: draft.id,
        action: draft.action,
        adminNote: draft.adminNote,
      );
      if (!mounted) {
        return;
      }
      final message = result['message']?.toString();
      showSnack(
        message == null || message.trim().isEmpty
            ? strings.text('AJL review submitted.')
            : message,
      );
    } catch (err) {
      showSnack(err.toString());
    }
  }

  Future<void> reviewAcrUpload(AcopAcrUpload upload, String action) async {
    final strings = context.strings;
    final draft = await showDialog<_AcopReviewDraft>(
      context: context,
      builder: (context) =>
          _AcopReviewDialog(fileName: upload.fileName, action: action),
    );
    if (draft == null || !mounted) {
      return;
    }
    try {
      final result = await widget.state.acopClient.reviewAcrUpload(
        id: upload.id,
        action: draft.action,
        adminNote: draft.adminNote,
      );
      await refreshPendingAcrUploads();
      if (!mounted) {
        return;
      }
      final message = result['message']?.toString();
      showSnack(
        message == null || message.trim().isEmpty
            ? strings.text('ACR review submitted.')
            : message,
      );
    } catch (err) {
      showSnack(err.toString());
    }
  }

  Future<void> reviewEmaUpload(AcopEmaUpload upload, String action) async {
    final strings = context.strings;
    final draft = await showDialog<_AcopReviewDraft>(
      context: context,
      builder: (context) =>
          _AcopReviewDialog(fileName: upload.appId, action: action),
    );
    if (draft == null || !mounted) {
      return;
    }
    try {
      final result = await widget.state.acopClient.reviewEmaUpload(
        id: upload.id,
        action: draft.action,
        adminNote: draft.adminNote,
      );
      await refreshPendingEmaUploads();
      if (!mounted) {
        return;
      }
      final message = result['message']?.toString();
      showSnack(
        message == null || message.trim().isEmpty
            ? strings.text('EMA review submitted.')
            : message,
      );
    } catch (err) {
      showSnack(err.toString());
    }
  }

  Future<void> refreshPendingLibs() async {
    if (loadingPendingLibs) {
      return;
    }
    setState(() {
      loadingPendingLibs = true;
      pendingLibsError = null;
    });
    try {
      final loaded = await widget.state.acopClient.getPendingLibs();
      if (mounted) {
        setState(() => pendingLibs = loaded);
      }
    } catch (err) {
      if (mounted) {
        setState(() => pendingLibsError = err.toString());
      }
    } finally {
      if (mounted) {
        setState(() => loadingPendingLibs = false);
      }
    }
  }

  Future<void> reviewPendingLib(int id, String action) async {
    final strings = context.strings;
    try {
      final result = await widget.state.acopClient.reviewLibUpload(
        id: id,
        action: action,
        adminNote: '',
      );
      await refreshPendingLibs();
      if (!mounted) {
        return;
      }
      final message = result['message']?.toString();
      showSnack(
        message == null || message.trim().isEmpty
            ? strings.text('AJL review submitted.')
            : message,
      );
    } catch (err) {
      showSnack(err.toString());
    }
  }

  Future<void> openLibManager() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AcopLibManagerPage(apiClient: widget.state.acopClient),
      ),
    );
  }

  List<AcopBot> get filteredBots {
    var list = bots.toList();
    if (_botSearchQuery.isNotEmpty) {
      final q = _botSearchQuery.toLowerCase();
      list = list.where((b) =>
        b.botName.toLowerCase().contains(q) ||
        (b.botDesc).toLowerCase().contains(q) ||
        b.botId.toString().contains(q)
      ).toList();
    }
    switch (_botFilter) {
      case 'online':
        list = list.where((b) => b.online == 1).toList();
        break;
      case 'offline':
        list = list.where((b) => b.online == 0 && b.status == 1).toList();
        break;
      case 'disabled':
        list = list.where((b) => b.status == 0).toList();
        break;
      default:
        break;
    }
    return list;
  }

  int get botOnlineCount => bots.where((b) => b.online == 1).length;
  int get botActiveCount => bots.where((b) => b.status == 1).length;

  void selectDestination(int index) {
    setState(() => selectedIndex = index);
    if (index == 1) {
      if (adminBots.isEmpty && !loadingAdminBots) {
        unawaited(refreshAdminBots());
      }
      if (pendingAcrUploads.isEmpty && !loadingPendingAcr) {
        unawaited(refreshPendingAcrUploads());
      }
      if (pendingEmaUploads.isEmpty && !loadingPendingEma) {
        unawaited(refreshPendingEmaUploads());
      }
      if (pendingLibs.isEmpty && !loadingPendingLibs) {
        unawaited(refreshPendingLibs());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final isWide = MediaQuery.sizeOf(context).width >= 860;
    final pages = [
      _AcopBotsPage(
        bots: filteredBots,
        totalCount: bots.length,
        onlineCount: botOnlineCount,
        activeCount: botActiveCount,
        assetBaseUrl: widget.state.acopClient.baseUrl,
        loading: loadingBots,
        error: botsError,
        searchQuery: _botSearchQuery,
        currentFilter: _botFilter,
        onSearchChanged: (v) => setState(() => _botSearchQuery = v),
        onFilterChanged: (v) => setState(() => _botFilter = v),
        onRefresh: refreshBots,
        onCreate: createBot,
        onOpen: openBot,
        onEdit: editBot,
        onUploadAvatar: uploadBotAvatar,
        onResetToken: resetBotToken,
        onDelete: deleteBot,
        onOpenLibManager: openLibManager,
      ),
      _AcopAdminPage(
        bots: adminBots,
        pendingAcrUploads: pendingAcrUploads,
        pendingEmaUploads: pendingEmaUploads,
        pendingLibs: pendingLibs,
        assetBaseUrl: widget.state.acopClient.baseUrl,
        loading: loadingAdminBots,
        loadingPendingAcr: loadingPendingAcr,
        loadingPendingEma: loadingPendingEma,
        loadingPendingLibs: loadingPendingLibs,
        error: adminError,
        pendingAcrError: pendingAcrError,
        pendingEmaError: pendingEmaError,
        pendingLibsError: pendingLibsError,
        onRefresh: refreshAdminBots,
        onRefreshPendingAcr: refreshPendingAcrUploads,
        onRefreshPendingEma: refreshPendingEmaUploads,
        onRefreshPendingLibs: refreshPendingLibs,
        onHandlePermission: handlePermissionById,
        onRunDiagnostic: runSaveChainDiagnostic,
        onReviewLib: reviewLibUpload,
        onReviewAcr: reviewAcrUpload,
        onReviewEma: reviewEmaUpload,
        onReviewPendingLib: reviewPendingLib,
      ),
      _AcopAccountPage(
        state: widget.state,
        serverUrl: serverUrl,
        savingServer: savingServer,
        onSaveServer: saveServer,
        onResetServer: serverUrl.clear,
        onShowBlockCodeChanged: widget.state.updateShowAcopBlockGeneratedCode,
        onWrapCodeEditorChanged: widget.state.updateWrapAcopCodeEditorOnMobile,
        onLogout: logout,
        onSwitchToChat: switchToChatMode,
      ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.text('CsAC Open Platform')),
        actions: [
          IconButton(
            tooltip: strings.text('Bot JavaScript guide'),
            onPressed: () => openAcopScriptGuide(context),
            icon: const Icon(Icons.help_outline),
          ),
          IconButton(
            tooltip: strings.text('Refresh'),
            onPressed: selectedIndex == 1
                ? () {
                    unawaited(refreshAdminBots());
                    unawaited(refreshPendingAcrUploads());
                  }
                : refreshBots,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: strings.text('Switch to CsAC chat'),
            onPressed: switchToChatMode,
            icon: const Icon(Icons.forum_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Row(
          children: [
            if (isWide)
              NavigationRail(
                selectedIndex: selectedIndex,
                onDestinationSelected: selectDestination,
                labelType: NavigationRailLabelType.all,
                destinations: [
                  NavigationRailDestination(
                    icon: const Icon(Icons.smart_toy_outlined),
                    selectedIcon: const Icon(Icons.smart_toy),
                    label: Text(strings.text('Bots')),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                    selectedIcon: const Icon(Icons.admin_panel_settings),
                    label: Text(strings.text('Admin')),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.account_circle_outlined),
                    selectedIcon: const Icon(Icons.account_circle),
                    label: Text(strings.text('Account')),
                  ),
                ],
              ),
            Expanded(child: pages[selectedIndex]),
          ],
        ),
      ),
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: selectDestination,
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.smart_toy_outlined),
                  selectedIcon: const Icon(Icons.smart_toy),
                  label: strings.text('Bots'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.admin_panel_settings_outlined),
                  selectedIcon: const Icon(Icons.admin_panel_settings),
                  label: strings.text('Admin'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.account_circle_outlined),
                  selectedIcon: const Icon(Icons.account_circle),
                  label: strings.text('Account'),
                ),
              ],
            ),
    );
  }
}

class _AcopBotsPage extends StatelessWidget {
  const _AcopBotsPage({
    required this.bots,
    required this.totalCount,
    required this.onlineCount,
    required this.activeCount,
    required this.assetBaseUrl,
    required this.loading,
    required this.error,
    required this.searchQuery,
    required this.currentFilter,
    required this.onSearchChanged,
    required this.onFilterChanged,
    required this.onRefresh,
    required this.onCreate,
    required this.onOpen,
    required this.onEdit,
    required this.onUploadAvatar,
    required this.onResetToken,
    required this.onDelete,
    required this.onOpenLibManager,
  });

  final List<AcopBot> bots;
  final int totalCount;
  final int onlineCount;
  final int activeCount;
  final String assetBaseUrl;
  final bool loading;
  final String? error;
  final String searchQuery;
  final String currentFilter;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onFilterChanged;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onCreate;
  final Future<void> Function(AcopBot bot) onOpen;
  final Future<void> Function(AcopBot bot) onEdit;
  final Future<void> Function(AcopBot bot) onUploadAvatar;
  final Future<void> Function(AcopBot bot) onResetToken;
  final Future<void> Function(AcopBot bot) onDelete;
  final Future<void> Function() onOpenLibManager;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _AcopHeaderRow(
            title: strings.text('Bot management'),
            subtitle: strings.text(
              'Create bots, manage tokens and open scripts.',
            ),
            action: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onOpenLibManager,
                  icon: const Icon(Icons.library_books_outlined),
                  label: Text(strings.text('JSLibs')),
                ),
                FilledButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add),
                  label: Text(strings.text('Create bot')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (!loading && error == null)
            _BotStatsRow(
              totalCount: totalCount,
              activeCount: activeCount,
              onlineCount: onlineCount,
            ),
          const SizedBox(height: 8),
          if (!loading && error == null && bots.isNotEmpty) ...[
            TextField(
              controller: TextEditingController(text: searchQuery),
              onChanged: onSearchChanged,
              decoration: InputDecoration(
                hintText: strings.text('Search bots...'),
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip(context, 'all', strings.text('All')),
                  const SizedBox(width: 6),
                  _buildFilterChip(context, 'online', strings.text('Online')),
                  const SizedBox(width: 6),
                  _buildFilterChip(context, 'offline', strings.text('Offline')),
                  const SizedBox(width: 6),
                  _buildFilterChip(context, 'disabled', strings.text('Disabled')),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (loading)
            const LinearProgressIndicator()
          else if (error != null)
            _AcopErrorPanel(message: error!, onRetry: onRefresh)
          else if (bots.isEmpty)
            _EmptyPanel(message: strings.text('No bots found.'))
          else
            Card(
              elevation: 0,
              child: _RoundedInkClip(
                child: Column(
                  children: [
                    for (var i = 0; i < bots.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _AcopBotTile(
                        bot: bots[i],
                        assetBaseUrl: assetBaseUrl,
                        onTap: () => onOpen(bots[i]),
                        onEdit: () => onEdit(bots[i]),
                        onUploadAvatar: () => onUploadAvatar(bots[i]),
                        onResetToken: () => onResetToken(bots[i]),
                        onDelete: () => onDelete(bots[i]),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(BuildContext context, String value, String label) {
    final selected = currentFilter == value;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onFilterChanged(value),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _BotStatsRow extends StatelessWidget {
  const _BotStatsRow({
    required this.totalCount,
    required this.activeCount,
    required this.onlineCount,
  });

  final int totalCount;
  final int activeCount;
  final int onlineCount;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(child: _StatItem(icon: Icons.smart_toy, label: 'Total', value: '$totalCount')),
            const SizedBox(width: 8),
            Expanded(child: _StatItem(icon: Icons.check_circle, label: 'Active', value: '$activeCount', color: Colors.green)),
            const SizedBox(width: 8),
            Expanded(child: _StatItem(icon: Icons.online_prediction, label: 'Online', value: '$onlineCount', color: Colors.blue)),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.icon, required this.label, required this.value, this.color});
  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        Icon(icon, size: 28, color: c),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: c)),
        Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _AcopAdminPage extends StatelessWidget {
  const _AcopAdminPage({
    required this.bots,
    required this.pendingAcrUploads,
    required this.pendingEmaUploads,
    required this.pendingLibs,
    required this.assetBaseUrl,
    required this.loading,
    required this.loadingPendingAcr,
    required this.loadingPendingEma,
    required this.loadingPendingLibs,
    required this.error,
    required this.pendingAcrError,
    required this.pendingEmaError,
    required this.pendingLibsError,
    required this.onRefresh,
    required this.onRefreshPendingAcr,
    required this.onRefreshPendingEma,
    required this.onRefreshPendingLibs,
    required this.onHandlePermission,
    required this.onRunDiagnostic,
    required this.onReviewLib,
    required this.onReviewAcr,
    required this.onReviewEma,
    required this.onReviewPendingLib,
  });

  final List<AcopBot> bots;
  final List<AcopAcrUpload> pendingAcrUploads;
  final List<AcopEmaUpload> pendingEmaUploads;
  final List<AcopLibUpload> pendingLibs;
  final String assetBaseUrl;
  final bool loading;
  final bool loadingPendingAcr;
  final bool loadingPendingEma;
  final bool loadingPendingLibs;
  final String? error;
  final String? pendingAcrError;
  final String? pendingEmaError;
  final String? pendingLibsError;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onRefreshPendingAcr;
  final Future<void> Function() onRefreshPendingEma;
  final Future<void> Function() onRefreshPendingLibs;
  final Future<void> Function() onHandlePermission;
  final Future<void> Function() onRunDiagnostic;
  final Future<void> Function() onReviewLib;
  final Future<void> Function(AcopAcrUpload upload, String action) onReviewAcr;
  final Future<void> Function(AcopEmaUpload upload, String action) onReviewEma;
  final Future<void> Function(int id, String action) onReviewPendingLib;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          onRefresh(),
          onRefreshPendingAcr(),
          onRefreshPendingEma(),
          onRefreshPendingLibs(),
        ]);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _AcopHeaderRow(
            title: strings.text('Admin tools'),
            subtitle: strings.text(
              'Review ACR uploads, run diagnostics and handle permissions.',
            ),
            action: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: onRunDiagnostic,
                  icon: const Icon(Icons.health_and_safety_outlined),
                  label: Text(strings.text('Save-chain diagnostic')),
                ),
                OutlinedButton.icon(
                  onPressed: onHandlePermission,
                  icon: const Icon(Icons.rule_outlined),
                  label: Text(strings.text('Handle permission')),
                ),
                OutlinedButton.icon(
                  onPressed: onReviewLib,
                  icon: const Icon(Icons.library_books_outlined),
                  label: Text(strings.text('Review AJL library')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SettingsSectionTitle(strings.text('Pending EMA uploads')),
          Card(
            elevation: 0,
            child: _RoundedInkClip(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.apps_outlined),
                    title: Text(strings.text('EMA review queue')),
                    subtitle: Text(
                      strings.text(
                        'Approving an EMA publishes it to the eMApps package service.',
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: strings.text('Refresh'),
                      onPressed: onRefreshPendingEma,
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                  const Divider(height: 1),
                  if (loadingPendingEma)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: LinearProgressIndicator(),
                    )
                  else if (pendingEmaError != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: _AcopErrorPanel(
                        message: pendingEmaError!,
                        onRetry: onRefreshPendingEma,
                      ),
                    )
                  else if (pendingEmaUploads.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: _EmptyPanel(
                        message: strings.text('No pending EMA uploads.'),
                      ),
                    )
                  else
                    for (var i = 0; i < pendingEmaUploads.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _AcopEmaUploadTile(
                        upload: pendingEmaUploads[i],
                        onApprove: () =>
                            onReviewEma(pendingEmaUploads[i], 'approve'),
                        onReject: () =>
                            onReviewEma(pendingEmaUploads[i], 'reject'),
                      ),
                    ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _SettingsSectionTitle(strings.text('Pending ACR uploads')),
          Card(
            elevation: 0,
            child: _RoundedInkClip(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.fact_check_outlined),
                    title: Text(strings.text('ACR review queue')),
                    subtitle: Text(
                      strings.text(
                        'Approving an ACR also saves it to ServerBot lib as AJL.',
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: strings.text('Refresh'),
                      onPressed: onRefreshPendingAcr,
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                  const Divider(height: 1),
                  if (loadingPendingAcr)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: LinearProgressIndicator(),
                    )
                  else if (pendingAcrError != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: _AcopErrorPanel(
                        message: pendingAcrError!,
                        onRetry: onRefreshPendingAcr,
                      ),
                    )
                  else if (pendingAcrUploads.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: _EmptyPanel(
                        message: strings.text('No pending ACR uploads.'),
                      ),
                    )
                  else
                    for (var i = 0; i < pendingAcrUploads.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _AcopAcrUploadTile(
                        upload: pendingAcrUploads[i],
                        onApprove: () =>
                            onReviewAcr(pendingAcrUploads[i], 'approve'),
                        onReject: () =>
                            onReviewAcr(pendingAcrUploads[i], 'reject'),
                      ),
                    ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _SettingsSectionTitle(strings.text('Pending JSLibs review')),
          Card(
            elevation: 0,
            child: _RoundedInkClip(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.library_books_outlined),
                    title: Text(strings.text('AJL review queue')),
                    subtitle: Text(
                      strings.text('Review community JSLibs uploads.'),
                    ),
                    trailing: IconButton(
                      tooltip: strings.text('Refresh'),
                      onPressed: onRefreshPendingLibs,
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                  const Divider(height: 1),
                  if (loadingPendingLibs)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: LinearProgressIndicator(),
                    )
                  else if (pendingLibsError != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: _AcopErrorPanel(
                        message: pendingLibsError!,
                        onRetry: onRefreshPendingLibs,
                      ),
                    )
                  else if (pendingLibs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: _EmptyPanel(
                        message: strings.text('No pending JSLibs uploads.'),
                      ),
                    )
                  else
                    for (var i = 0; i < pendingLibs.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _AcopPendingLibTile(
                         lib: pendingLibs[i],
                         onApprove: () =>
                             onReviewPendingLib(pendingLibs[i].id, 'approve'),
                         onReject: () =>
                             onReviewPendingLib(pendingLibs[i].id, 'reject'),
                       ),
                    ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _SettingsSectionTitle(strings.text('All bots')),
          if (loading)
            const LinearProgressIndicator()
          else if (error != null)
            _AcopErrorPanel(message: error!, onRetry: onRefresh)
          else if (bots.isEmpty)
            _EmptyPanel(message: strings.text('No admin bot data.'))
          else
            Card(
              elevation: 0,
              child: _RoundedInkClip(
                child: Column(
                  children: [
                    for (var i = 0; i < bots.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _AcopAdminBotTile(
                        bot: bots[i],
                        assetBaseUrl: assetBaseUrl,
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AcopAccountPage extends StatelessWidget {
  const _AcopAccountPage({
    required this.state,
    required this.serverUrl,
    required this.savingServer,
    required this.onSaveServer,
    required this.onResetServer,
    required this.onShowBlockCodeChanged,
    required this.onWrapCodeEditorChanged,
    required this.onLogout,
    required this.onSwitchToChat,
  });

  final CsacAppState state;
  final TextEditingController serverUrl;
  final bool savingServer;
  final Future<void> Function() onSaveServer;
  final VoidCallback onResetServer;
  final Future<void> Function(bool enabled) onShowBlockCodeChanged;
  final Future<void> Function(bool enabled) onWrapCodeEditorChanged;
  final Future<void> Function() onLogout;
  final Future<void> Function() onSwitchToChat;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final developer = state.acopDeveloper;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _AcopHeaderRow(
          title: strings.text('Developer account'),
          subtitle: state.acopClient.baseUrl,
        ),
        const SizedBox(height: 12),
        _SettingsSectionTitle(strings.text('Block editor')),
        Card(
          elevation: 0,
          child: _RoundedInkClip(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.code_outlined),
                  title: Text(
                    strings.text('Show generated code in block editor'),
                  ),
                  subtitle: Text(
                    strings.text(
                      'When off, the block editor hides the generated code preview on desktop and mobile.',
                    ),
                  ),
                  value: state.preferences.showAcopBlockGeneratedCode,
                  onChanged: (value) =>
                      unawaited(onShowBlockCodeChanged(value)),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.wrap_text_outlined),
                  title: Text(strings.text('Wrap long code lines on mobile')),
                  subtitle: Text(
                    strings.text(
                      'When off, the mobile code editor scrolls horizontally instead of wrapping long lines.',
                    ),
                  ),
                  value: state.preferences.wrapAcopCodeEditorOnMobile,
                  onChanged: (value) =>
                      unawaited(onWrapCodeEditorChanged(value)),
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
                  title: Text(
                    developer?.devName ?? strings.text('Not logged in'),
                  ),
                  subtitle: Text(developer?.email ?? ''),
                ),
                const Divider(height: 1),
                _AcopInfoListTile(
                  icon: Icons.numbers_outlined,
                  label: strings.text('Developer ID'),
                  value: developer == null ? '-' : '${developer.devId}',
                ),
                const Divider(height: 1),
                _AcopInfoListTile(
                  icon: Icons.vpn_key_outlined,
                  label: strings.text('API key'),
                  value: developer?.apiKey ?? '-',
                  copyable: developer?.apiKey.isNotEmpty == true,
                ),
                const Divider(height: 1),
                _AcopInfoListTile(
                  icon: Icons.verified_user_outlined,
                  label: strings.text('Status'),
                  value: _acopDeveloperStatusLabel(
                    context,
                    developer?.status ?? 0,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _SettingsSectionTitle(strings.text('ACOP server address')),
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: serverUrl,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => onSaveServer(),
                  decoration: InputDecoration(
                    labelText: strings.text('ACOP server address'),
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
                  children: [
                    OutlinedButton.icon(
                      onPressed: savingServer ? null : onResetServer,
                      icon: const Icon(Icons.restart_alt),
                      label: Text(strings.text('Reset to default')),
                    ),
                    FilledButton.icon(
                      onPressed: savingServer ? null : onSaveServer,
                      icon: savingServer
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(strings.text('Apply server')),
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
                  leading: const Icon(Icons.forum_outlined),
                  title: Text(strings.text('Switch to CsAC chat')),
                  subtitle: Text(
                    strings.text('Return to the normal chat client'),
                  ),
                  onTap: onSwitchToChat,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: Text(strings.text('Logout')),
                  subtitle: Text(strings.text('Clear ACOP session')),
                  iconColor: Theme.of(context).colorScheme.error,
                  onTap: onLogout,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AcopBotTile extends StatelessWidget {
  const _AcopBotTile({
    required this.bot,
    required this.assetBaseUrl,
    required this.onTap,
    required this.onEdit,
    required this.onUploadAvatar,
    required this.onResetToken,
    required this.onDelete,
  });

  final AcopBot bot;
  final String assetBaseUrl;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onUploadAvatar;
  final VoidCallback onResetToken;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final avatarUrl = acopAssetUrl(bot.botAvatar, assetBaseUrl);
    return ListTile(
      leading: _Avatar(
        url: avatarUrl,
        fallback: bot.isOnline ? Icons.smart_toy : Icons.smart_toy_outlined,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
      ),
      title: Text(
        bot.botName.isEmpty ? 'Bot #${bot.botId}' : bot.botName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          'UID ${bot.uid}',
          strings.text(bot.isOnline ? 'Online' : 'Offline'),
          if (bot.botDesc.isNotEmpty) bot.botDesc,
        ].join(' | '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: PopupMenuButton<String>(
        tooltip: strings.text('More'),
        onSelected: (value) {
          switch (value) {
            case 'edit':
              onEdit();
              break;
            case 'avatar':
              onUploadAvatar();
              break;
            case 'token':
              onResetToken();
              break;
            case 'delete':
              onDelete();
              break;
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(value: 'edit', child: Text(strings.text('Edit'))),
          PopupMenuItem(
            value: 'avatar',
            child: Text(strings.text('Upload avatar')),
          ),
          PopupMenuItem(
            value: 'token',
            child: Text(strings.text('Reset token')),
          ),
          PopupMenuItem(value: 'delete', child: Text(strings.text('Delete'))),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _AcopAdminBotTile extends StatelessWidget {
  const _AcopAdminBotTile({required this.bot, required this.assetBaseUrl});

  final AcopBot bot;
  final String assetBaseUrl;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final avatarUrl = acopAssetUrl(bot.botAvatar, assetBaseUrl);
    return ListTile(
      leading: _Avatar(
        url: avatarUrl,
        fallback: Icons.smart_toy_outlined,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
      ),
      title: Text(bot.botName.isEmpty ? 'Bot #${bot.botId}' : bot.botName),
      subtitle: Text(
        [
          'UID ${bot.uid}',
          if (bot.devName.isNotEmpty) bot.devName,
          if (bot.email.isNotEmpty) bot.email,
        ].join(' | '),
      ),
      trailing: Wrap(
        spacing: 6,
        children: [
          _AcopSmallChip(
            label: strings.text(bot.isOnline ? 'Online' : 'Offline'),
            active: bot.isOnline,
          ),
          _AcopSmallChip(label: 'notify', active: bot.canNotify == 1),
          _AcopSmallChip(label: 'http', active: bot.canHttp == 1),
        ],
      ),
    );
  }
}

class _AcopAcrUploadTile extends StatelessWidget {
  const _AcopAcrUploadTile({
    required this.upload,
    required this.onApprove,
    required this.onReject,
  });

  final AcopAcrUpload upload;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final title = upload.fileName.isEmpty
        ? 'ACR #${upload.id}'
        : upload.fileName;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.integration_instructions_outlined),
            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              [
                'ID ${upload.id}',
                if (upload.fileType.isNotEmpty) upload.fileType,
                if (upload.devName.isNotEmpty) upload.devName,
                if (upload.createdAt.isNotEmpty) upload.createdAt,
              ].join(' | '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (upload.content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    upload.content,
                    maxLines: 5,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: onReject,
                  icon: const Icon(Icons.close),
                  label: Text(strings.text('Reject')),
                ),
                FilledButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.check),
                  label: Text(strings.text('Approve')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AcopEmaUploadTile extends StatelessWidget {
  const _AcopEmaUploadTile({
    required this.upload,
    required this.onApprove,
    required this.onReject,
  });

  final AcopEmaUpload upload;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final title = upload.appId.isEmpty
        ? 'EMA #${upload.id}'
        : upload.appId;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.apps_outlined),
            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              [
                'ID ${upload.id}',
                if (upload.devName.isNotEmpty) upload.devName,
                if (upload.createdAt.isNotEmpty) upload.createdAt,
              ].join(' | '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (upload.content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    upload.content,
                    maxLines: 5,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: onReject,
                  icon: const Icon(Icons.close),
                  label: Text(strings.text('Reject')),
                ),
                FilledButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.check),
                  label: Text(strings.text('Approve')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AcopPendingLibTile extends StatelessWidget {
  const _AcopPendingLibTile({
    required this.lib,
    required this.onApprove,
    required this.onReject,
  });

  final AcopLibUpload lib;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final cs = Theme.of(context).colorScheme;
    final statusColor = lib.status == 1 ? Colors.green : lib.status == 2 ? Colors.red : Colors.orange;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.library_books),
            title: Text('${lib.name} v${lib.version}', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              [
                if (lib.devName.isNotEmpty) lib.devName,
                if (lib.createdAt.isNotEmpty) lib.createdAt,
              ].join(' | '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Chip(
              label: Text(lib.statusText, style: TextStyle(color: statusColor, fontSize: 12)),
              visualDensity: VisualDensity.compact,
              side: BorderSide(color: statusColor.withValues(alpha: 0.5)),
            ),
          ),
          if (lib.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                lib.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
            ),
          if (lib.content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Material(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    lib.content,
                    maxLines: 8,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: onReject,
                  icon: const Icon(Icons.close),
                  label: Text(strings.text('Reject')),
                ),
                FilledButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.check),
                  label: Text(strings.text('Approve')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AcopBotDetailScreen extends StatefulWidget {
  const AcopBotDetailScreen({
    super.key,
    required this.state,
    required this.bot,
  });

  final CsacAppState state;
  final AcopBot bot;

  @override
  State<AcopBotDetailScreen> createState() => _AcopBotDetailScreenState();
}

class _AcopBotDetailScreenState extends State<AcopBotDetailScreen> {
  late AcopBot bot = widget.bot;
  List<AcopScript> scripts = const <AcopScript>[];
  List<AcopLogEntry> logs = const <AcopLogEntry>[];
  List<AcopPermissionRequest> permissions = const <AcopPermissionRequest>[];
  bool loadingScripts = false;
  bool loadingLogs = false;
  bool loadingPermissions = false;
  String logLevel = '';
  int logLimit = 50;
  String? scriptsError;
  String? logsError;
  String? permissionsError;

  @override
  void initState() {
    super.initState();
    unawaited(refreshAll());
  }

  void showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> refreshAll() async {
    await Future.wait([refreshScripts(), refreshLogs(), refreshPermissions()]);
    try {
      final loaded = await widget.state.acopClient.getBotInfo(bot.botId);
      if (mounted) {
        setState(() => bot = loaded);
      }
    } catch (_) {
      // The detail page can still show scripts/logs when the optional info call fails.
    }
  }

  Future<void> refreshScripts() async {
    setState(() {
      loadingScripts = true;
      scriptsError = null;
    });
    try {
      final loaded = await widget.state.acopClient.listScripts(bot.botId);
      if (mounted) {
        setState(() => scripts = loaded);
      }
    } catch (err) {
      if (mounted) {
        setState(() => scriptsError = err.toString());
      }
    } finally {
      if (mounted) {
        setState(() => loadingScripts = false);
      }
    }
  }

  Future<void> refreshLogs() async {
    setState(() {
      loadingLogs = true;
      logsError = null;
    });
    try {
      final loaded = await widget.state.acopClient.listLogs(
        botId: bot.botId,
        level: logLevel,
        limit: logLimit,
      );
      if (mounted) {
        setState(() => logs = loaded);
      }
    } catch (err) {
      if (mounted) {
        setState(() => logsError = err.toString());
      }
    } finally {
      if (mounted) {
        setState(() => loadingLogs = false);
      }
    }
  }

  Future<void> refreshPermissions() async {
    setState(() {
      loadingPermissions = true;
      permissionsError = null;
    });
    try {
      final loaded = await widget.state.acopClient.listPermissionRequests(
        bot.botId,
      );
      if (mounted) {
        setState(() => permissions = loaded);
      }
    } catch (err) {
      if (mounted) {
        setState(() => permissionsError = err.toString());
      }
    } finally {
      if (mounted) {
        setState(() => loadingPermissions = false);
      }
    }
  }

  Future<void> createScript() async {
    final strings = context.strings;
    final draft = await Navigator.of(context).push<_AcopScriptDraft>(
      MaterialPageRoute<_AcopScriptDraft>(
        builder: (context) => _AcopScriptEditorScreen(
          state: widget.state,
          showGeneratedCode:
              widget.state.preferences.showAcopBlockGeneratedCode,
          mobileWordWrap: widget.state.preferences.wrapAcopCodeEditorOnMobile,
        ),
      ),
    );
    if (draft == null || !mounted) {
      return;
    }
    try {
      await widget.state.acopClient.createScript(
        botId: bot.botId,
        scriptName: draft.name,
        scriptContent: draft.content,
      );
      await refreshScripts();
      showSnack(strings.text('Script created.'));
    } catch (err) {
      showSnack(err.toString());
    }
  }

  Future<void> editScript(AcopScript script) async {
    final strings = context.strings;
    final loaded = await _loadScriptForEdit(script);
    if (!mounted) {
      return;
    }
    final draft = await Navigator.of(context).push<_AcopScriptDraft>(
      MaterialPageRoute<_AcopScriptDraft>(
        builder: (context) => _AcopScriptEditorScreen(
          state: widget.state,
          script: loaded,
          showGeneratedCode:
              widget.state.preferences.showAcopBlockGeneratedCode,
          mobileWordWrap: widget.state.preferences.wrapAcopCodeEditorOnMobile,
        ),
      ),
    );
    if (draft == null || !mounted) {
      return;
    }
    try {
      await widget.state.acopClient.updateScript(
        scriptId: loaded.scriptId,
        scriptName: draft.name,
        scriptContent: draft.content,
      );
      await refreshScripts();
      showSnack(strings.text('Saved.'));
    } catch (err) {
      showSnack(err.toString());
    }
  }

  Future<AcopScript> _loadScriptForEdit(AcopScript script) async {
    if (script.scriptContent.isNotEmpty) {
      return script;
    }
    try {
      return await widget.state.acopClient.getScript(script.scriptId);
    } catch (_) {
      return script;
    }
  }

  Future<void> deleteScript(AcopScript script) async {
    final strings = context.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.strings.text('Delete script?')),
        content: Text(
          context.strings.format('Delete {name} permanently?', {
            'name': script.scriptName,
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.strings.text('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.strings.text('Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await widget.state.acopClient.deleteScript(script.scriptId);
      await refreshScripts();
      showSnack(strings.text('Deleted.'));
    } catch (err) {
      showSnack(err.toString());
    }
  }

  Future<void> toggleScript(AcopScript script, bool enabled) async {
    try {
      await widget.state.acopClient.toggleScript(
        scriptId: script.scriptId,
        enabled: enabled,
      );
      await refreshScripts();
    } catch (err) {
      showSnack(err.toString());
    }
  }

  Future<void> testScript(AcopScript script) async {
    final draft = await showDialog<_AcopTestEventDraft>(
      context: context,
      builder: (context) => const _AcopTestEventDialog(),
    );
    if (draft == null || !mounted) {
      return;
    }
    try {
      final loaded = await _loadScriptForEdit(script);
      final result = await widget.state.acopClient.testScript(
        scriptId: script.scriptId,
        eventType: draft.eventType,
        eventData: jsonDecode(draft.eventData),
        scriptContent: loaded.scriptContent,
      );
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => _AcopJsonResultDialog(
          title: context.strings.text('Test result'),
          value: result,
        ),
      );
    } catch (err) {
      showSnack(err.toString());
    }
  }

  Future<void> openScriptGuide() {
    return openAcopScriptGuide(context);
  }

  Future<void> requestPermission() async {
    final strings = context.strings;
    final draft = await showDialog<_AcopPermissionDraft>(
      context: context,
      builder: (context) => const _AcopPermissionDialog(),
    );
    if (draft == null || !mounted) {
      return;
    }
    try {
      await widget.state.acopClient.requestPermission(
        botId: bot.botId,
        permType: draft.type,
        reason: draft.reason,
      );
      await refreshPermissions();
      showSnack(strings.text('Permission requested.'));
    } catch (err) {
      showSnack(err.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(bot.botName.isEmpty ? 'Bot #${bot.botId}' : bot.botName),
          bottom: TabBar(
            tabs: [
              Tab(icon: const Icon(Icons.code), text: strings.text('Scripts')),
              Tab(
                icon: const Icon(Icons.article_outlined),
                text: strings.text('Logs'),
              ),
              Tab(
                icon: const Icon(Icons.rule_outlined),
                text: strings.text('Permissions'),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: strings.text('Refresh'),
              onPressed: refreshAll,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: TabBarView(
          children: [
            _AcopScriptsTab(
              scripts: scripts,
              loading: loadingScripts,
              error: scriptsError,
              onRefresh: refreshScripts,
              onCreate: createScript,
              onEdit: editScript,
              onDelete: deleteScript,
              onToggle: toggleScript,
              onTest: testScript,
              onOpenGuide: openScriptGuide,
            ),
            _AcopLogsTab(
              logs: logs,
              loading: loadingLogs,
              error: logsError,
              level: logLevel,
              limit: logLimit,
              onLevelChanged: (value) {
                setState(() => logLevel = value);
                unawaited(refreshLogs());
              },
              onLimitChanged: (value) {
                setState(() => logLimit = value);
                unawaited(refreshLogs());
              },
              onRefresh: refreshLogs,
            ),
            _AcopPermissionsTab(
              permissions: permissions,
              loading: loadingPermissions,
              error: permissionsError,
              onRefresh: refreshPermissions,
              onRequest: requestPermission,
            ),
          ],
        ),
      ),
    );
  }
}

class _AcopScriptsTab extends StatelessWidget {
  const _AcopScriptsTab({
    required this.scripts,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.onCreate,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
    required this.onTest,
    required this.onOpenGuide,
  });

  final List<AcopScript> scripts;
  final bool loading;
  final String? error;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onCreate;
  final Future<void> Function(AcopScript script) onEdit;
  final Future<void> Function(AcopScript script) onDelete;
  final Future<void> Function(AcopScript script, bool enabled) onToggle;
  final Future<void> Function(AcopScript script) onTest;
  final Future<void> Function() onOpenGuide;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _AcopHeaderRow(
            title: strings.text('Scripts'),
            subtitle: strings.text(
              'Create, edit, toggle and test bot scripts.',
            ),
            action: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: onOpenGuide,
                  icon: const Icon(Icons.help_outline),
                  label: Text(strings.text('JavaScript guide')),
                ),
                FilledButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add),
                  label: Text(strings.text('Create script')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (loading)
            const LinearProgressIndicator()
          else if (error != null)
            _AcopErrorPanel(message: error!, onRetry: onRefresh)
          else if (scripts.isEmpty)
            _EmptyPanel(message: strings.text('No scripts yet.'))
          else
            Card(
              elevation: 0,
              child: _RoundedInkClip(
                child: Column(
                  children: [
                    for (var i = 0; i < scripts.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      SwitchListTile(
                        secondary: const Icon(Icons.code),
                        title: Text(
                          scripts[i].scriptName.isEmpty
                              ? 'Script #${scripts[i].scriptId}'
                              : scripts[i].scriptName,
                        ),
                        subtitle: Text(
                          [
                            'ID ${scripts[i].scriptId}',
                            strings.format('Version {version}', {
                              'version': scripts[i].version,
                            }),
                            if (scripts[i].updatedAt > 0)
                              strings.format('Updated {time}', {
                                'time': readableTimestamp(scripts[i].updatedAt),
                              }),
                          ].join(' | '),
                        ),
                        value: scripts[i].isEnabled,
                        onChanged: (value) => onToggle(scripts[i], value),
                        controlAffinity: ListTileControlAffinity.trailing,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => onEdit(scripts[i]),
                              icon: const Icon(Icons.edit_outlined),
                              label: Text(strings.text('Edit')),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => onTest(scripts[i]),
                              icon: const Icon(Icons.play_arrow_outlined),
                              label: Text(strings.text('Test')),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => onDelete(scripts[i]),
                              icon: const Icon(Icons.delete_outline),
                              label: Text(strings.text('Delete')),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AcopLogsTab extends StatelessWidget {
  const _AcopLogsTab({
    required this.logs,
    required this.loading,
    required this.error,
    required this.level,
    required this.limit,
    required this.onLevelChanged,
    required this.onLimitChanged,
    required this.onRefresh,
  });

  final List<AcopLogEntry> logs;
  final bool loading;
  final String? error;
  final String level;
  final int limit;
  final ValueChanged<String> onLevelChanged;
  final ValueChanged<int> onLimitChanged;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _AcopHeaderRow(
            title: strings.text('Logs'),
            subtitle: strings.text(
              'Filter bot runtime logs by level and limit.',
            ),
            action: IconButton.filledTonal(
              tooltip: strings.text('Refresh'),
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  initialValue: level,
                  decoration: InputDecoration(
                    labelText: strings.text('Log level'),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: Text(strings.text('All')),
                    ),
                    const DropdownMenuItem(value: 'log', child: Text('log')),
                    const DropdownMenuItem(value: 'warn', child: Text('warn')),
                    const DropdownMenuItem(
                      value: 'error',
                      child: Text('error'),
                    ),
                  ],
                  onChanged: (value) => onLevelChanged(value ?? ''),
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<int>(
                  initialValue: limit,
                  decoration: InputDecoration(
                    labelText: strings.text('Limit'),
                    border: const OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 50, child: Text('50')),
                    DropdownMenuItem(value: 100, child: Text('100')),
                    DropdownMenuItem(value: 200, child: Text('200')),
                  ],
                  onChanged: (value) => onLimitChanged(value ?? 50),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (loading)
            const LinearProgressIndicator()
          else if (error != null)
            _AcopErrorPanel(message: error!, onRetry: onRefresh)
          else if (logs.isEmpty)
            _EmptyPanel(message: strings.text('No logs.'))
          else
            Card(
              elevation: 0,
              child: _RoundedInkClip(
                child: Column(
                  children: [
                    for (var i = 0; i < logs.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        leading: _AcopLogLevelIcon(level: logs[i].level),
                        title: SelectableText(
                          logs[i].message.isEmpty
                              ? _formatJson(logs[i].raw)
                              : logs[i].message,
                        ),
                        subtitle: Text(logs[i].createdAt),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AcopPermissionsTab extends StatelessWidget {
  const _AcopPermissionsTab({
    required this.permissions,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.onRequest,
  });

  final List<AcopPermissionRequest> permissions;
  final bool loading;
  final String? error;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onRequest;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _AcopHeaderRow(
            title: strings.text('Permissions'),
            subtitle: strings.text(
              'Request notify or HTTP capability for this bot.',
            ),
            action: FilledButton.icon(
              onPressed: onRequest,
              icon: const Icon(Icons.add_moderator_outlined),
              label: Text(strings.text('Request permission')),
            ),
          ),
          const SizedBox(height: 12),
          if (loading)
            const LinearProgressIndicator()
          else if (error != null)
            _AcopErrorPanel(message: error!, onRetry: onRefresh)
          else if (permissions.isEmpty)
            _EmptyPanel(message: strings.text('No permission requests.'))
          else
            Card(
              elevation: 0,
              child: _RoundedInkClip(
                child: Column(
                  children: [
                    for (var i = 0; i < permissions.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.rule_outlined),
                        title: Text(permissions[i].permType),
                        subtitle: Text(
                          [
                            permissions[i].reason,
                            if (permissions[i].adminReply.isNotEmpty)
                              permissions[i].adminReply,
                          ].where((value) => value.isNotEmpty).join(' | '),
                        ),
                        trailing: _AcopPermissionStatusChip(
                          status: permissions[i].status,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AcopHeaderRow extends StatelessWidget {
  const _AcopHeaderRow({required this.title, this.subtitle, this.action});

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final titleWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (subtitle?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
    if (action == null) {
      return titleWidget;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [titleWidget, const SizedBox(height: 10), action!],
          );
        }
        return Row(
          children: [
            Expanded(child: titleWidget),
            const SizedBox(width: 12),
            action!,
          ],
        );
      },
    );
  }
}

class _AcopErrorPanel extends StatelessWidget {
  const _AcopErrorPanel({required this.message, required this.onRetry});

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

class _AcopSmallChip extends StatelessWidget {
  const _AcopSmallChip({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      backgroundColor: active
          ? colors.primaryContainer
          : colors.surfaceContainerHighest,
      labelStyle: TextStyle(
        color: active ? colors.onPrimaryContainer : colors.onSurfaceVariant,
      ),
    );
  }
}

class _AcopPermissionStatusChip extends StatelessWidget {
  const _AcopPermissionStatusChip({required this.status});

  final int status;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = Theme.of(context).colorScheme;
    final (label, activeColor, textColor) = switch (status) {
      1 => (
        strings.text('Approved'),
        colors.primaryContainer,
        colors.onPrimaryContainer,
      ),
      2 => (
        strings.text('Rejected'),
        colors.errorContainer,
        colors.onErrorContainer,
      ),
      _ => (
        strings.text('Pending'),
        colors.secondaryContainer,
        colors.onSecondaryContainer,
      ),
    };
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      backgroundColor: activeColor,
      labelStyle: TextStyle(color: textColor),
    );
  }
}

class _AcopLogLevelIcon extends StatelessWidget {
  const _AcopLogLevelIcon({required this.level});

  final String level;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final normalized = level.toLowerCase();
    if (normalized == 'error') {
      return Icon(Icons.error_outline, color: colors.error);
    }
    if (normalized == 'warn') {
      return Icon(Icons.warning_amber_outlined, color: colors.tertiary);
    }
    return Icon(Icons.article_outlined, color: colors.primary);
  }
}

class _AcopInfoListTile extends StatelessWidget {
  const _AcopInfoListTile({
    required this.icon,
    required this.label,
    required this.value,
    this.copyable = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: SelectableText(value),
      trailing: copyable
          ? IconButton(
              tooltip: context.strings.text('Copy'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: value));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.strings.text('Copied.'))),
                  );
                }
              },
              icon: const Icon(Icons.copy),
            )
          : null,
    );
  }
}

class _AcopBotDraft {
  const _AcopBotDraft({required this.name, required this.description});

  final String name;
  final String description;
}

class _AcopBotDialog extends StatefulWidget {
  const _AcopBotDialog({this.bot});

  final AcopBot? bot;

  @override
  State<_AcopBotDialog> createState() => _AcopBotDialogState();
}

class _AcopBotDialogState extends State<_AcopBotDialog> {
  late final TextEditingController name;
  late final TextEditingController description;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.bot?.botName ?? '');
    description = TextEditingController(text: widget.bot?.botDesc ?? '');
  }

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    super.dispose();
  }

  void submit() {
    if (name.text.trim().isEmpty) {
      return;
    }
    Navigator.of(context).pop(
      _AcopBotDraft(
        name: name.text.trim(),
        description: description.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AlertDialog(
      title: Text(strings.text(widget.bot == null ? 'Create bot' : 'Edit bot')),
      content: _AcopDialogBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: strings.text('Bot name'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: description,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: strings.text('Bot description'),
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
        FilledButton(onPressed: submit, child: Text(strings.text('Save'))),
      ],
    );
  }
}

class _AcopTokenDialog extends StatelessWidget {
  const _AcopTokenDialog({required this.token});

  final String token;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AlertDialog(
      title: Text(strings.text('Bot token')),
      content: _AcopDialogBody(
        child: SelectableText(
          token,
          style: const TextStyle(fontFamily: 'monospace'),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: token));
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(strings.text('Copied.'))));
            }
          },
          icon: const Icon(Icons.copy),
          label: Text(strings.text('Copy')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.text('Done')),
        ),
      ],
    );
  }
}

class _AcopScriptDraft {
  const _AcopScriptDraft({required this.name, required this.content});

  final String name;
  final String content;
}

class _AcopScriptEditorScreen extends StatefulWidget {
  const _AcopScriptEditorScreen({
    required this.state,
    this.script,
    required this.showGeneratedCode,
    required this.mobileWordWrap,
  });

  final CsacAppState state;
  final AcopScript? script;
  final bool showGeneratedCode;
  final bool mobileWordWrap;

  @override
  State<_AcopScriptEditorScreen> createState() =>
      _AcopScriptEditorScreenState();
}

class _AcopScriptEditorScreenState extends State<_AcopScriptEditorScreen> {
  late final TextEditingController name;
  late final CodeLineEditingController content;
  late final String initialName;
  late final String initialContent;
  bool allowPop = false;
  bool draftRefreshScheduled = false;

  @override
  void initState() {
    super.initState();
    initialName = widget.script?.scriptName ?? '';
    initialContent = widget.script?.scriptContent.isNotEmpty == true
        ? widget.script!.scriptContent
        : _defaultAcopScriptTemplate;
    name = TextEditingController(text: initialName);
    content = CodeLineEditingController.fromText(initialContent);
    name.addListener(handleDraftChanged);
    content.addListener(handleDraftChanged);
  }

  @override
  void dispose() {
    name.removeListener(handleDraftChanged);
    content.removeListener(handleDraftChanged);
    name.dispose();
    content.dispose();
    super.dispose();
  }

  bool get hasUnsavedChanges {
    return name.text != initialName || content.text != initialContent;
  }

  void handleDraftChanged() {
    if (!mounted || draftRefreshScheduled) {
      return;
    }
    draftRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      draftRefreshScheduled = false;
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

  bool submit() {
    if (name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.strings.text('Script name is required.')),
        ),
      );
      return false;
    }
    allowPop = true;
    Navigator.of(
      context,
    ).pop(_AcopScriptDraft(name: name.text.trim(), content: content.text));
    return true;
  }

  Future<void> openBlockEditor() async {
    final draft = await Navigator.of(context).push<_AcopBlockDraft>(
      MaterialPageRoute<_AcopBlockDraft>(
        builder: (context) => _AcopBlockEditorScreen(
          initialCode: content.text,
          showGeneratedCode: widget.showGeneratedCode,
        ),
      ),
    );
    if (draft == null || !mounted) {
      return;
    }
    content.text = draft.code;
  }

  Future<void> openVisualBuilder() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text(context.strings.text('Visual script builder')),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: VisualScriptBuilder(
                onCodeGenerated: (code) {
                  Navigator.of(context).pop(code);
                },
              ),
            ),
          ),
        ),
      ),
    );
    if (result != null && mounted) {
      content.text = result;
    }
  }

  Future<void> uploadEmaPackage() async {
    final draft = await showDialog<_AcopEmaDraft>(
      context: context,
      builder: (context) => _AcopEmaDialog(defaultName: name.text),
    );
    if (draft == null || !mounted) {
      return;
    }
    final emaContent = _buildEmaPackageJson(
      appId: draft.appId,
      name: draft.name,
      description: draft.description,
      entryPage: draft.entryPage,
      script: content.text,
    );
    try {
      final result = await widget.state.acopClient.uploadEma(
        fileName: '${draft.appId}.ema',
        content: emaContent,
      );
      if (!mounted) {
        return;
      }
      final message = result['message']?.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message == null || message.trim().isEmpty
                ? context.strings.text('EMA uploaded for review.')
                : message,
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
  }

  Future<void> handlePopAttempt() async {
    if (!hasUnsavedChanges) {
      allowPop = true;
      Navigator.of(context).pop();
      return;
    }
    final action = await showDialog<_AcopUnsavedExitAction>(
      context: context,
      builder: (context) => const _AcopUnsavedChangesDialog(),
    );
    if (!mounted) {
      return;
    }
    switch (action) {
      case _AcopUnsavedExitAction.save:
        submit();
        break;
      case _AcopUnsavedExitAction.discard:
        allowPop = true;
        Navigator.of(context).pop();
        break;
      case _AcopUnsavedExitAction.cancel:
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return PopScope<_AcopScriptDraft>(
      canPop: allowPop || !hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          unawaited(handlePopAttempt());
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            strings.text(
              widget.script == null ? 'Create script' : 'Edit script',
            ),
          ),
          actions: [
            IconButton(
              tooltip: strings.text('JavaScript guide'),
              onPressed: () => openAcopScriptGuide(context),
              icon: const Icon(Icons.help_outline),
            ),
            IconButton(
              tooltip: strings.text('Visual script builder'),
              onPressed: () => openVisualBuilder(),
              icon: const Icon(Icons.view_quilt_outlined),
            ),
            IconButton(
              tooltip: strings.text('JavaScript block editor'),
              onPressed: openBlockEditor,
              icon: const Icon(Icons.account_tree_outlined),
            ),
            IconButton(
              tooltip: strings.text('Upload EMA package'),
              onPressed: uploadEmaPackage,
              icon: const Icon(Icons.upload_file_outlined),
            ),
            TextButton.icon(
              onPressed: submit,
              icon: const Icon(Icons.save_outlined),
              label: Text(strings.text('Save')),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: TextField(
                    controller: name,
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: strings.text('Script name'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: _AcopCodeEditor(
                      controller: content,
                      label: strings.text('Script content'),
                      mobileWordWrap: widget.mobileWordWrap,
                    ),
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

class _AcopTestEventDraft {
  const _AcopTestEventDraft({required this.eventType, required this.eventData});

  final String eventType;
  final String eventData;
}

class _AcopEmaDraft {
  const _AcopEmaDraft({
    required this.appId,
    required this.name,
    required this.description,
    required this.entryPage,
  });

  final String appId;
  final String name;
  final String description;
  final String entryPage;
}

class _AcopEmaDialog extends StatefulWidget {
  const _AcopEmaDialog({required this.defaultName});

  final String defaultName;

  @override
  State<_AcopEmaDialog> createState() => _AcopEmaDialogState();
}

class _AcopEmaDialogState extends State<_AcopEmaDialog> {
  late final TextEditingController appId;
  late final TextEditingController name;
  final description = TextEditingController();
  final entryPage = TextEditingController(text: 'index.html');

  @override
  void initState() {
    super.initState();
    final defaultName = widget.defaultName.trim();
    name = TextEditingController(text: defaultName);
    appId = TextEditingController(
      text: defaultName.isEmpty
          ? 'com.csac.app'
          : 'com.csac.${_sanitizeEmaIdPart(defaultName)}',
    );
  }

  @override
  void dispose() {
    appId.dispose();
    name.dispose();
    description.dispose();
    entryPage.dispose();
    super.dispose();
  }

  void submit() {
    final normalizedAppId = appId.text.trim();
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9_.-]{0,63}$').hasMatch(normalizedAppId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.strings.text(
              'App ID must start with a letter and contain only letters, numbers, underscore, dash or dot.',
            ),
          ),
        ),
      );
      return;
    }
    final appName = name.text.trim();
    if (appName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.text('App name is required.'))),
      );
      return;
    }
    Navigator.of(context).pop(
      _AcopEmaDraft(
        appId: normalizedAppId,
        name: appName,
        description: description.text.trim(),
        entryPage: entryPage.text.trim().isEmpty
            ? 'index.html'
            : entryPage.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AlertDialog(
      title: Text(strings.text('Upload EMA package')),
      content: _AcopDialogBody(
        maxWidth: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: appId,
              decoration: InputDecoration(
                labelText: strings.text('App ID'),
                helperText: 'com.csac.example',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: name,
              decoration: InputDecoration(
                labelText: strings.text('App name'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: description,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: strings.text('Description'),
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: entryPage,
              decoration: InputDecoration(
                labelText: strings.text('Entry page'),
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
        FilledButton.icon(
          onPressed: submit,
          icon: const Icon(Icons.upload_file_outlined),
          label: Text(strings.text('Upload')),
        ),
      ],
    );
  }
}

class _AcopTestEventDialog extends StatefulWidget {
  const _AcopTestEventDialog();

  @override
  State<_AcopTestEventDialog> createState() => _AcopTestEventDialogState();
}

class _AcopTestEventDialogState extends State<_AcopTestEventDialog> {
  final eventType = TextEditingController(text: 'group_message');
  final eventData = TextEditingController(
    text: const JsonEncoder.withIndent(
      '  ',
    ).convert({'message': 'ping', 'group_id': 1, 'user_id': 1000}),
  );

  @override
  void dispose() {
    eventType.dispose();
    eventData.dispose();
    super.dispose();
  }

  void submit() {
    Navigator.of(context).pop(
      _AcopTestEventDraft(
        eventType: eventType.text.trim().isEmpty
            ? 'group_message'
            : eventType.text.trim(),
        eventData: eventData.text.trim().isEmpty ? '{}' : eventData.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AlertDialog(
      title: Text(strings.text('Test script')),
      content: _AcopDialogBody(
        maxWidth: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: eventType,
              decoration: InputDecoration(
                labelText: strings.text('Event type'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: eventData,
              minLines: 8,
              maxLines: 12,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: InputDecoration(
                labelText: strings.text('Event data'),
                alignLabelWithHint: true,
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
        FilledButton(onPressed: submit, child: Text(strings.text('Run test'))),
      ],
    );
  }
}

class _AcopScriptGuideScreen extends StatelessWidget {
  const _AcopScriptGuideScreen();

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    const assetPath = 'assets/acop/bot_script_js_guide.md';
    return Scaffold(
      appBar: AppBar(title: Text(strings.text('JavaScript guide'))),
      body: SafeArea(
        child: FutureBuilder<String>(
          future: rootBundle.loadString(assetPath),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    strings.text('Unable to load the guide.'),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return Markdown(
              data: snapshot.data ?? '',
              selectable: true,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                  .copyWith(
                    h1: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                    h2: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    p: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(height: 1.55),
                    code: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                  ),
            );
          },
        ),
      ),
    );
  }
}

String _buildEmaPackageJson({
  required String appId,
  required String name,
  required String description,
  required String entryPage,
  required String script,
}) {
  final safeEntry = entryPage.trim().isEmpty ? 'index.html' : entryPage.trim();
  final html =
      '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>${htmlEscape.convert(name)}</title>
  <style>
    body { margin: 0; font-family: system-ui, sans-serif; padding: 16px; }
    #app { min-height: 100vh; }
  </style>
</head>
<body>
  <main id="app"></main>
  <script src="main.js"></script>
</body>
</html>
''';
  return const JsonEncoder.withIndent('  ').convert({
    'appId': appId.trim(),
    'name': name.trim(),
    'version': '1.0.0',
    'desc': description.trim(),
    'entryPage': safeEntry,
    'files': [
      {'filename': safeEntry, 'content': html},
      {'filename': 'main.js', 'content': script},
    ],
  });
}

String _sanitizeEmaIdPart(String value) {
  final sanitized = value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9_-]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  if (sanitized.isEmpty || !RegExp(r'^[a-z]').hasMatch(sanitized)) {
    return 'app';
  }
  return sanitized.length > 32 ? sanitized.substring(0, 32) : sanitized;
}

class _AcopPermissionDraft {
  const _AcopPermissionDraft({required this.type, required this.reason});

  final String type;
  final String reason;
}

class _AcopPermissionDialog extends StatefulWidget {
  const _AcopPermissionDialog();

  @override
  State<_AcopPermissionDialog> createState() => _AcopPermissionDialogState();
}

class _AcopPermissionDialogState extends State<_AcopPermissionDialog> {
  final reason = TextEditingController();
  String type = 'notify';

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  void submit() {
    Navigator.of(
      context,
    ).pop(_AcopPermissionDraft(type: type, reason: reason.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AlertDialog(
      title: Text(strings.text('Request permission')),
      content: _AcopDialogBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: type,
              decoration: InputDecoration(
                labelText: strings.text('Permission type'),
                border: const OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'notify', child: Text('notify')),
                DropdownMenuItem(value: 'http', child: Text('http')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => type = value);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              minLines: 3,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: strings.text('Reason'),
                alignLabelWithHint: true,
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
        FilledButton(onPressed: submit, child: Text(strings.text('Submit'))),
      ],
    );
  }
}

class _AcopAdminPermissionDraft {
  const _AcopAdminPermissionDraft({
    required this.requestId,
    required this.action,
    required this.reply,
  });

  final int requestId;
  final String action;
  final String reply;
}

class _AcopAdminPermissionDialog extends StatefulWidget {
  const _AcopAdminPermissionDialog();

  @override
  State<_AcopAdminPermissionDialog> createState() =>
      _AcopAdminPermissionDialogState();
}

class _AcopAdminPermissionDialogState
    extends State<_AcopAdminPermissionDialog> {
  final requestId = TextEditingController();
  final reply = TextEditingController();
  String action = 'approve';

  @override
  void dispose() {
    requestId.dispose();
    reply.dispose();
    super.dispose();
  }

  void submit() {
    final id = int.tryParse(requestId.text.trim());
    if (id == null || id <= 0) {
      return;
    }
    Navigator.of(context).pop(
      _AcopAdminPermissionDraft(
        requestId: id,
        action: action,
        reply: reply.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AlertDialog(
      title: Text(strings.text('Handle permission')),
      content: _AcopDialogBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: requestId,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: strings.text('Request ID'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: action,
              decoration: InputDecoration(
                labelText: strings.text('Action'),
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: 'approve',
                  child: Text(strings.text('Approve')),
                ),
                DropdownMenuItem(
                  value: 'reject',
                  child: Text(strings.text('Reject')),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => action = value);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reply,
              minLines: 3,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: strings.text('Admin reply'),
                alignLabelWithHint: true,
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
        FilledButton(onPressed: submit, child: Text(strings.text('Submit'))),
      ],
    );
  }
}

class _AcopSaveDiagnosticDraft {
  const _AcopSaveDiagnosticDraft({
    required this.name,
    required this.content,
    required this.mode,
  });

  final String name;
  final String content;
  final String mode;
}

class _AcopSaveDiagnosticDialog extends StatefulWidget {
  const _AcopSaveDiagnosticDialog();

  @override
  State<_AcopSaveDiagnosticDialog> createState() =>
      _AcopSaveDiagnosticDialogState();
}

class _AcopSaveDiagnosticDialogState extends State<_AcopSaveDiagnosticDialog> {
  final name = TextEditingController(text: 'diag_test');
  final content = TextEditingController(
    text: "// DIAG test content\nconsole.log('test');",
  );
  String mode = '';

  @override
  void dispose() {
    name.dispose();
    content.dispose();
    super.dispose();
  }

  void submit() {
    Navigator.of(context).pop(
      _AcopSaveDiagnosticDraft(
        name: name.text.trim(),
        content: content.text,
        mode: mode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AlertDialog(
      title: Text(strings.text('Save-chain diagnostic')),
      content: _AcopDialogBody(
        maxWidth: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: InputDecoration(
                labelText: strings.text('Library name'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: mode,
              decoration: InputDecoration(
                labelText: strings.text('Diagnostic mode'),
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(value: '', child: Text(strings.text('All'))),
                const DropdownMenuItem(value: 'direct', child: Text('direct')),
                const DropdownMenuItem(value: 'http', child: Text('http')),
              ],
              onChanged: (value) => setState(() => mode = value ?? ''),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: content,
              minLines: 5,
              maxLines: 10,
              decoration: InputDecoration(
                labelText: strings.text('Library content'),
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
              ),
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.text('Cancel')),
        ),
        FilledButton.icon(
          onPressed: submit,
          icon: const Icon(Icons.play_arrow_outlined),
          label: Text(strings.text('Run diagnostic')),
        ),
      ],
    );
  }
}

class _AcopReviewDraft {
  const _AcopReviewDraft({required this.action, required this.adminNote});

  final String action;
  final String adminNote;
}

class _AcopLibReviewDraft {
  const _AcopLibReviewDraft({
    required this.id,
    required this.action,
    required this.adminNote,
  });

  final int id;
  final String action;
  final String adminNote;
}

class _AcopLibReviewDialog extends StatefulWidget {
  const _AcopLibReviewDialog();

  @override
  State<_AcopLibReviewDialog> createState() => _AcopLibReviewDialogState();
}

class _AcopLibReviewDialogState extends State<_AcopLibReviewDialog> {
  final id = TextEditingController();
  final adminNote = TextEditingController();
  String action = 'approve';

  @override
  void dispose() {
    id.dispose();
    adminNote.dispose();
    super.dispose();
  }

  void submit() {
    final parsed = int.tryParse(id.text.trim());
    if (parsed == null || parsed <= 0) {
      return;
    }
    Navigator.of(context).pop(
      _AcopLibReviewDraft(
        id: parsed,
        action: action,
        adminNote: adminNote.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AlertDialog(
      title: Text(strings.text('Review AJL library')),
      content: _AcopDialogBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: id,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: strings.text('Library ID'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: action,
              decoration: InputDecoration(
                labelText: strings.text('Action'),
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: 'approve',
                  child: Text(strings.text('Approve')),
                ),
                DropdownMenuItem(
                  value: 'reject',
                  child: Text(strings.text('Reject')),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => action = value);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: adminNote,
              minLines: 3,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: strings.text('Admin note'),
                alignLabelWithHint: true,
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
        FilledButton.icon(
          onPressed: submit,
          icon: const Icon(Icons.save_outlined),
          label: Text(strings.text('Submit')),
        ),
      ],
    );
  }
}

class _AcopReviewDialog extends StatefulWidget {
  const _AcopReviewDialog({required this.fileName, required this.action});

  final String fileName;
  final String action;

  @override
  State<_AcopReviewDialog> createState() => _AcopReviewDialogState();
}

class _AcopReviewDialogState extends State<_AcopReviewDialog> {
  final adminNote = TextEditingController();

  @override
  void dispose() {
    adminNote.dispose();
    super.dispose();
  }

  void submit() {
    Navigator.of(context).pop(
      _AcopReviewDraft(action: widget.action, adminNote: adminNote.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final approving = widget.action == 'approve';
    return AlertDialog(
      title: Text(strings.text(approving ? 'Approve ACR?' : 'Reject ACR?')),
      content: _AcopDialogBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              strings.format('Review {name}', {
                'name': widget.fileName.isEmpty ? 'ACR' : widget.fileName,
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: adminNote,
              minLines: 3,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: strings.text('Admin note'),
                alignLabelWithHint: true,
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
        FilledButton.icon(
          onPressed: submit,
          icon: Icon(approving ? Icons.check : Icons.close),
          label: Text(strings.text(approving ? 'Approve' : 'Reject')),
        ),
      ],
    );
  }
}

class _AcopJsonResultDialog extends StatelessWidget {
  const _AcopJsonResultDialog({required this.title, required this.value});

  final String title;
  final Map<String, dynamic> value;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final text = _formatJson(value);
    return AlertDialog(
      title: Text(title),
      content: _AcopDialogBody(
        maxWidth: 680,
        child: SelectableText(
          text,
          style: const TextStyle(fontFamily: 'monospace'),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(strings.text('Copied.'))));
            }
          },
          icon: const Icon(Icons.copy),
          label: Text(strings.text('Copy')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.text('Done')),
        ),
      ],
    );
  }
}

class _AcopCodeEditor extends StatelessWidget {
  const _AcopCodeEditor({
    required this.controller,
    required this.label,
    required this.mobileWordWrap,
  });

  final CodeLineEditingController controller;
  final String label;
  final bool mobileWordWrap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(label, style: theme.textTheme.labelLarge),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ExcludeSemantics(
                child: CodeEditor(
                  controller: controller,
                  toolbarController: _AcopCodeSelectionToolbarController(
                    builder: _buildAcopCodeSelectionToolbar,
                  ),
                  wordWrap: isMobilePlatform ? mobileWordWrap : true,
                  autocompleteSymbols: true,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.all(8),
                  sperator: VerticalDivider(
                    width: 13,
                    thickness: 1,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  indicatorBuilder:
                      (context, editingController, chunkController, notifier) {
                        return DefaultCodeLineNumber(
                          controller: editingController,
                          notifier: notifier,
                          minNumberCount: 2,
                          textStyle: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.62),
                            fontFamily: 'Consolas',
                            fontFamilyFallback: const [
                              'SF Mono',
                              'Menlo',
                              'Monaco',
                              'Liberation Mono',
                              'DejaVu Sans Mono',
                              'Noto Sans Mono',
                              'monospace',
                            ],
                            fontSize: theme.textTheme.bodySmall?.fontSize,
                            height: 1.45,
                          ),
                          focusedTextStyle: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Consolas',
                            fontFamilyFallback: const [
                              'SF Mono',
                              'Menlo',
                              'Monaco',
                              'Liberation Mono',
                              'DejaVu Sans Mono',
                              'Noto Sans Mono',
                              'monospace',
                            ],
                            fontSize: theme.textTheme.bodySmall?.fontSize,
                            height: 1.45,
                          ),
                        );
                      },
                  style: CodeEditorStyle(
                    fontFamily: 'Consolas',
                    fontFamilyFallback: const [
                      'SF Mono',
                      'Menlo',
                      'Monaco',
                      'Liberation Mono',
                      'DejaVu Sans Mono',
                      'Noto Sans Mono CJK SC',
                      'Noto Sans Mono',
                      'monospace',
                    ],
                    fontSize: theme.textTheme.bodyMedium?.fontSize,
                    fontHeight: 1.45,
                    textColor: theme.colorScheme.onSurface,
                    backgroundColor: theme.colorScheme.surface,
                    cursorColor: theme.colorScheme.primary,
                    selectionColor: theme.colorScheme.primary.withValues(
                      alpha: 0.24,
                    ),
                    cursorLineColor: theme.colorScheme.primary.withValues(
                      alpha: 0.06,
                    ),
                    codeTheme: CodeHighlightTheme(
                      languages: {
                        'javascript': CodeHighlightThemeMode(
                          mode: re_highlight_js.langJavascript,
                        ),
                      },
                      theme: re_highlight_github.githubTheme,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AcopCodeSelectionToolbarController
    implements SelectionToolbarController {
  _AcopCodeSelectionToolbarController({required this.builder});

  final ToolbarMenuBuilder builder;
  OverlayEntry? _entry;
  ValueNotifier<bool>? _visibility;
  VoidCallback? _visibilityListener;

  @override
  void hide(BuildContext context) {
    _visibility?.removeListener(_visibilityListener ?? () {});
    _visibility = null;
    _visibilityListener = null;
    _entry?.remove();
    _entry = null;
  }

  @override
  void show({
    required BuildContext context,
    required CodeLineEditingController controller,
    required TextSelectionToolbarAnchors anchors,
    Rect? renderRect,
    required LayerLink layerLink,
    required ValueNotifier<bool> visibility,
  }) {
    hide(context);
    if (!isMobilePlatform) {
      unawaited(
        showMenu<void>(
          context: context,
          position: RelativeRect.fromSize(
            anchors.primaryAnchor & const Size(180, double.infinity),
            MediaQuery.of(context).size,
          ),
          items: [
            _AcopCodeContextMenuItem(
              label: context.strings.text('Copy'),
              onTap: () => unawaited(controller.copy()),
            ),
            _AcopCodeContextMenuItem(
              label: context.strings.text('Cut'),
              onTap: controller.cut,
            ),
            _AcopCodeContextMenuItem(
              label: context.strings.text('Paste'),
              onTap: controller.paste,
            ),
            _AcopCodeContextMenuItem(
              label: context.strings.text('Select all'),
              onTap: controller.selectAll,
            ),
          ],
        ),
      );
      return;
    }
    if (renderRect == null) {
      return;
    }
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      return;
    }
    void dismissToolbar() => hide(context);
    final entry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: dismissToolbar,
              onLongPress: dismissToolbar,
              child: const SizedBox.expand(),
            ),
          ),
          CodeEditorTapRegion(
            child: Directionality(
              textDirection: Directionality.of(context),
              child: ValueListenableBuilder<bool>(
                valueListenable: visibility,
                builder: (context, visible, child) {
                  return CompositedTransformFollower(
                    link: layerLink,
                    showWhenUnlinked: false,
                    offset: -renderRect.topLeft,
                    child: AnimatedOpacity(
                      opacity: visible ? 1 : 0,
                      duration: const Duration(milliseconds: 120),
                      child: child,
                    ),
                  );
                },
                child: builder(
                  context: context,
                  anchors: anchors,
                  controller: controller,
                  onDismiss: dismissToolbar,
                  onRefresh: () => show(
                    context: context,
                    controller: controller,
                    anchors: anchors,
                    renderRect: renderRect,
                    layerLink: layerLink,
                    visibility: visibility,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(entry);
    _entry = entry;
    _visibility = visibility;
    _visibilityListener = () {
      if (!visibility.value) {
        hide(context);
      }
    };
    visibility.addListener(_visibilityListener!);
  }
}

class _AcopCodeContextMenuItem extends PopupMenuItem<void>
    implements PreferredSizeWidget {
  _AcopCodeContextMenuItem({required String label, required VoidCallback onTap})
    : super(onTap: onTap, child: Text(label));

  @override
  Size get preferredSize => const Size(180, 40);
}

Widget _buildAcopCodeSelectionToolbar({
  required BuildContext context,
  required TextSelectionToolbarAnchors anchors,
  required CodeLineEditingController controller,
  required VoidCallback onDismiss,
  required VoidCallback onRefresh,
}) {
  void runAndDismiss(VoidCallback action) {
    action();
    onDismiss();
  }

  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: anchors,
    buttonItems: [
      ContextMenuButtonItem(
        label: context.strings.text('Copy'),
        onPressed: () {
          unawaited(controller.copy());
          onDismiss();
        },
      ),
      ContextMenuButtonItem(
        label: context.strings.text('Cut'),
        onPressed: () => runAndDismiss(controller.cut),
      ),
      ContextMenuButtonItem(
        label: context.strings.text('Paste'),
        onPressed: () => runAndDismiss(controller.paste),
      ),
      ContextMenuButtonItem(
        label: context.strings.text('Select all'),
        onPressed: () => runAndDismiss(controller.selectAll),
      ),
    ],
  );
}

class _AcopDialogBody extends StatelessWidget {
  const _AcopDialogBody({required this.child, this.maxWidth = 520});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: SingleChildScrollView(child: child),
    );
  }
}

String _acopDeveloperStatusLabel(BuildContext context, int status) {
  final strings = context.strings;
  return switch (status) {
    1 => strings.text('Active'),
    2 => strings.text('Banned'),
    _ => strings.text('Pending'),
  };
}

Future<void> openAcopScriptGuide(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const _AcopScriptGuideScreen()),
  );
}

String acopAssetUrl(String value, String baseUrl) {
  final text = value.trim();
  if (text.isEmpty) {
    return '';
  }
  if (text.startsWith('http://') ||
      text.startsWith('https://') ||
      text.startsWith('data:')) {
    return text;
  }
  final base = Uri.tryParse(baseUrl);
  if (base == null || !base.hasScheme || base.host.isEmpty) {
    return normalizeApiUrl(text);
  }
  final origin = base.replace(path: '', query: null, fragment: null);
  if (text.startsWith('/')) {
    return origin.resolve(text).toString();
  }
  return origin.resolve('/${text.replaceFirst(RegExp(r'^/+'), '')}').toString();
}

String _formatJson(Object? value) {
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } catch (_) {
    return '$value';
  }
}

const _defaultAcopScriptTemplate = r'''
bot.command('/help', async (ctx) => {
  await ctx.reply('你好，我是 CsAC Bot。可用指令：/help, /ping')
})

bot.command('/ping', async (ctx) => {
  await ctx.reply('pong')
})

bot.on('private.message', async (ctx) => {
  if (ctx.text.trim() === '测试bot') {
    await ctx.reply('bot正在运行')
  }
})

bot.on('group.message', async (ctx) => {
  if (ctx.text.includes('你好')) {
    await ctx.reply(`你好，${ctx.sender.nickname || ctx.sender.uid}`)
  }
})
''';

const _acopAvatarExtensions = <String>['png', 'jpg', 'jpeg', 'gif', 'webp'];
