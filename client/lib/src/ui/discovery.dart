part of '../../main.dart';

class SpaceFeedScreen extends StatefulWidget {
  const SpaceFeedScreen({
    super.key,
    required this.state,
    this.embedded = false,
    this.focusPostId,
  });

  final CsacAppState state;
  final bool embedded;
  final int? focusPostId;

  @override
  State<SpaceFeedScreen> createState() => _SpaceFeedScreenState();
}

class _SpaceFeedScreenState extends State<SpaceFeedScreen> {
  static const pageSize = 20;

  List<SpacePost> posts = const <SpacePost>[];
  bool loading = true;
  bool loadingMore = false;
  String? error;
  int page = 1;
  int total = 0;
  int? lastFocusedPostId;
  final postKeys = <int, GlobalKey>{};

  bool get hasMore {
    if (posts.isEmpty) {
      return false;
    }
    if (total <= 0) {
      return posts.length >= page * pageSize;
    }
    return posts.length < total;
  }

  @override
  void initState() {
    super.initState();
    unawaited(loadPosts());
  }

  Future<void> loadPosts({bool refresh = true}) async {
    if (refresh) {
      setState(() {
        loading = true;
        error = null;
      });
    } else if (loadingMore || !hasMore) {
      return;
    } else {
      setState(() {
        loadingMore = true;
        error = null;
      });
    }
    try {
      final targetPage = refresh ? 1 : page + 1;
      final loaded = await widget.state.client.spacePosts(
        page: targetPage,
        pageSize: pageSize,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        page = loaded.page <= 0 ? targetPage : loaded.page;
        total = loaded.total;
        posts = refresh ? loaded.posts : _mergeSpacePosts(posts, loaded.posts);
      });
      scheduleFocusPost();
    } catch (err) {
      if (mounted) {
        setState(() => error = err.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
          loadingMore = false;
        });
      }
    }
  }

  Future<void> composePost() async {
    final draft = await showModalBottomSheet<_SpaceDraft>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _SpaceComposeSheet(
        title: context.strings.text('Post update'),
        submitLabel: context.strings.text('Post'),
      ),
    );
    if (draft == null || !mounted) {
      return;
    }
    setState(() => loading = posts.isEmpty);
    try {
      await widget.state.client.sendSpacePost(
        content: draft.content,
        images: draft.uploadFiles,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.text('Post published.'))),
      );
      await loadPosts();
    } catch (err) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(err.toString())));
      setState(() => loading = false);
    }
  }

  Future<void> replyToPost(SpacePost post) async {
    final draft = await showModalBottomSheet<_SpaceDraft>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _SpaceComposeSheet(
        title: context.strings.format('Reply to {name}', {
          'name': post.displayName,
        }),
        submitLabel: context.strings.text('Reply'),
      ),
    );
    if (draft == null || !mounted) {
      return;
    }
    try {
      await widget.state.client.replySpacePost(
        post.id,
        content: draft.content,
        images: draft.uploadFiles,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.text('Reply sent.'))),
      );
      await loadPosts();
    } catch (err) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(err.toString())));
    }
  }

  Future<void> toggleLike(SpacePost post) async {
    try {
      final update = await widget.state.client.toggleSpaceLike(post.id);
      if (!mounted) {
        return;
      }
      setState(() {
        posts = _replaceSpacePost(
          posts,
          post.id,
          (item) =>
              item.copyWith(isLiked: update.isLiked, likesNum: update.likesNum),
        );
      });
    } catch (err) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(err.toString())));
    }
  }

  Future<void> deletePost(SpacePost post) async {
    final strings = context.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          strings.text(post.isReply ? 'Delete reply?' : 'Delete post?'),
        ),
        content: Text(
          strings.text(
            post.isReply
                ? 'This reply will be deleted.'
                : 'This post and its replies will be deleted.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.text('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.text('Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await widget.state.client.deleteSpacePost(post.id);
      if (!mounted) {
        return;
      }
      setState(() => posts = _removeSpacePost(posts, post.id));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.text('Post deleted.'))));
    } catch (err) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(err.toString())));
    }
  }

  Future<void> openPostUser(SpacePost post, Object avatarHeroTag) {
    return openUserProfile(
      context,
      widget.state,
      post.senderUid,
      avatarHeroTag: avatarHeroTag,
    );
  }

  @override
  void didUpdateWidget(covariant SpaceFeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusPostId != widget.focusPostId) {
      scheduleFocusPost(force: true);
    }
  }

  void scheduleFocusPost({bool force = false}) {
    final postId = widget.focusPostId ?? 0;
    if (postId <= 0) {
      return;
    }
    if (!force &&
        lastFocusedPostId == postId &&
        postKeys[postId]?.currentContext != null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final keyContext = postKeys[postId]?.currentContext;
      if (keyContext == null) {
        return;
      }
      lastFocusedPostId = postId;
      Scrollable.ensureVisible(
        keyContext,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
    });
  }

  Future<void> openPostQr(SpacePost post) {
    final strings = context.strings;
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CsacQrShareScreen(
          appBarTitle: strings.text('Post QR code'),
          link: csacSpacePostDeepLink(post.id),
          cardTitle: post.displayName,
          cardSubtitle: strings.format('Post #{id}', {'id': post.id}),
          avatarUrl: post.avatar,
          fallbackIcon: Icons.public_rounded,
          helperText: strings.text('Scan to open this post in CsAC.'),
          semanticsLabel: strings.text('CsAC post QR code'),
          shareTitle: strings.text('Share post QR code'),
          shareSubject: strings.text('CsAC post QR code'),
          fileName: 'csac-post-${post.id}.png',
          copySnackText: strings.text('Post link copied.'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final body = Column(
      children: [
        if (error != null)
          MaterialBanner(
            content: Text(error!),
            actions: [
              TextButton(
                onPressed: () => loadPosts(),
                child: Text(strings.text('Retry')),
              ),
              TextButton(
                onPressed: () => setState(() => error = null),
                child: Text(strings.text('Dismiss')),
              ),
            ],
          ),
        if (loading && posts.isNotEmpty) const LinearProgressIndicator(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: loadPosts,
            child: loading && posts.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 220),
                      Center(child: CircularProgressIndicator()),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                    itemCount: posts.isEmpty
                        ? 1
                        : posts.length + (hasMore || loadingMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (posts.isEmpty) {
                        return _EmptyPanel(
                          message: strings.text('No space posts yet.'),
                        );
                      }
                      if (index >= posts.length) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child: loadingMore
                                ? const CircularProgressIndicator()
                                : OutlinedButton.icon(
                                    onPressed: () => loadPosts(refresh: false),
                                    icon: const Icon(
                                      Icons.expand_more_outlined,
                                    ),
                                    label: Text(strings.text('Load more')),
                                  ),
                          ),
                        );
                      }
                      final post = posts[index];
                      final avatarHeroTag = userAvatarHeroTag(
                        post.senderUid,
                        'space-post-${post.id}',
                      );
                      final postKey = postKeys.putIfAbsent(
                        post.id,
                        () => GlobalKey(),
                      );
                      return _MotionListItem(
                        index: index,
                        child: KeyedSubtree(
                          key: postKey,
                          child: _SpacePostCard(
                            post: post,
                            currentUserId: widget.state.user?.uid ?? 0,
                            avatarHeroTag: avatarHeroTag,
                            onOpenUser: () => openPostUser(post, avatarHeroTag),
                            onLike: () => toggleLike(post),
                            onReply: () => replyToPost(post),
                            onDelete: () => deletePost(post),
                            onShareQr: () => openPostQr(post),
                            onReplyLike: toggleLike,
                            onReplyDelete: deletePost,
                            onReplyOpenUser: (reply, tag) =>
                                openPostUser(reply, tag),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.text('Space')),
        actions: [
          IconButton(
            tooltip: strings.text('Refresh'),
            onPressed: loading ? null : loadPosts,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(top: !widget.embedded, child: body),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: composePost,
        icon: const Icon(Icons.edit_outlined),
        label: Text(strings.text('Post')),
      ),
    );
  }
}

class _SpacePostCard extends StatelessWidget {
  const _SpacePostCard({
    required this.post,
    required this.currentUserId,
    required this.avatarHeroTag,
    required this.onOpenUser,
    required this.onLike,
    required this.onReply,
    required this.onDelete,
    required this.onShareQr,
    required this.onReplyLike,
    required this.onReplyDelete,
    required this.onReplyOpenUser,
  });

  final SpacePost post;
  final int currentUserId;
  final Object avatarHeroTag;
  final VoidCallback onOpenUser;
  final VoidCallback onLike;
  final VoidCallback onReply;
  final VoidCallback onDelete;
  final VoidCallback onShareQr;
  final ValueChanged<SpacePost> onReplyLike;
  final ValueChanged<SpacePost> onReplyDelete;
  final void Function(SpacePost post, Object avatarHeroTag) onReplyOpenUser;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final strings = context.strings;
    final canDelete = currentUserId > 0 && currentUserId == post.senderUid;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onOpenUser,
                  child: _Avatar(
                    url: post.avatar,
                    fallback: Icons.person_rounded,
                    radius: 22,
                    heroTag: avatarHeroTag,
                    backgroundColor: colors.primaryContainer,
                    foregroundColor: colors.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (post.createdAt.isNotEmpty)
                        Text(
                          post.createdAt,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                if (canDelete)
                  IconButton(
                    tooltip: strings.text('Delete'),
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            if (post.content.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              _SpaceMarkdownContent(text: post.content.trim()),
            ],
            if (post.images.isNotEmpty) ...[
              const SizedBox(height: 12),
              _SpaceImageGrid(postId: post.id, images: post.images),
            ],
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  onPressed: onLike,
                  icon: Icon(
                    post.isLiked ? Icons.favorite : Icons.favorite_border,
                  ),
                  label: Text(
                    '${strings.text(post.isLiked ? 'Unlike' : 'Like')} ${post.likesNum}',
                  ),
                ),
                TextButton.icon(
                  onPressed: onReply,
                  icon: const Icon(Icons.reply_outlined),
                  label: Text(strings.text('Reply')),
                ),
                TextButton.icon(
                  onPressed: onShareQr,
                  icon: const Icon(Icons.qr_code_2_outlined),
                  label: Text(strings.text('QR code')),
                ),
              ],
            ),
            if (post.replies.isNotEmpty) ...[
              const SizedBox(height: 4),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                  child: Column(
                    children: [
                      for (var i = 0; i < post.replies.length; i++) ...[
                        _SpaceReplyTile(
                          reply: post.replies[i],
                          currentUserId: currentUserId,
                          onLike: () => onReplyLike(post.replies[i]),
                          onDelete: () => onReplyDelete(post.replies[i]),
                          onOpenUser: (tag) =>
                              onReplyOpenUser(post.replies[i], tag),
                        ),
                        if (i != post.replies.length - 1)
                          Divider(color: colors.outlineVariant),
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
}

class _SpaceReplyTile extends StatelessWidget {
  const _SpaceReplyTile({
    required this.reply,
    required this.currentUserId,
    required this.onLike,
    required this.onDelete,
    required this.onOpenUser,
  });

  final SpacePost reply;
  final int currentUserId;
  final VoidCallback onLike;
  final VoidCallback onDelete;
  final ValueChanged<Object> onOpenUser;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = Theme.of(context).colorScheme;
    final canDelete = currentUserId > 0 && currentUserId == reply.senderUid;
    final avatarHeroTag = userAvatarHeroTag(
      reply.senderUid,
      'space-reply-${reply.id}',
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            customBorder: const CircleBorder(),
            onTap: () => onOpenUser(avatarHeroTag),
            child: _Avatar(
              url: reply.avatar,
              fallback: Icons.person_rounded,
              radius: 16,
              heroTag: avatarHeroTag,
              backgroundColor: colors.primaryContainer,
              foregroundColor: colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 2,
                  children: [
                    Text(
                      reply.displayName,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (reply.createdAt.isNotEmpty)
                      Text(
                        reply.createdAt,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                if (reply.content.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _SpaceMarkdownContent(text: reply.content.trim()),
                ],
                if (reply.images.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _SpaceImageGrid(postId: reply.id, images: reply.images),
                ],
                const SizedBox(height: 2),
                Wrap(
                  spacing: 2,
                  children: [
                    TextButton.icon(
                      onPressed: onLike,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: Icon(
                        reply.isLiked ? Icons.favorite : Icons.favorite_border,
                        size: 18,
                      ),
                      label: Text(
                        '${strings.text(reply.isLiked ? 'Unlike' : 'Like')} ${reply.likesNum}',
                      ),
                    ),
                    if (canDelete)
                      TextButton.icon(
                        onPressed: onDelete,
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: Text(strings.text('Delete')),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpaceMarkdownContent extends StatelessWidget {
  const _SpaceMarkdownContent({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _ChatMarkdownText(
      text: text,
      textColor: colors.onSurface,
      secondaryTextColor: colors.onSurfaceVariant,
    );
  }
}

class _SpaceMarkdownEditor extends StatefulWidget {
  const _SpaceMarkdownEditor({
    required this.controller,
    required this.hintText,
  });

  final TextEditingController controller;
  final String hintText;

  @override
  State<_SpaceMarkdownEditor> createState() => _SpaceMarkdownEditorState();
}

class _SpaceMarkdownEditorState extends State<_SpaceMarkdownEditor> {
  final focusNode = FocusNode();
  bool preview = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(handleTextChanged);
  }

  @override
  void didUpdateWidget(covariant _SpaceMarkdownEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(handleTextChanged);
      widget.controller.addListener(handleTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(handleTextChanged);
    focusNode.dispose();
    super.dispose();
  }

  void handleTextChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  TextSelection safeSelection() {
    final selection = widget.controller.selection;
    final textLength = widget.controller.text.length;
    if (!selection.isValid) {
      return TextSelection.collapsed(offset: textLength);
    }
    final start = selection.start.clamp(0, textLength);
    final end = selection.end.clamp(0, textLength);
    return TextSelection(baseOffset: start, extentOffset: end);
  }

  void replaceSelection(
    String replacement, {
    required int selectedStart,
    required int selectedEnd,
  }) {
    final text = widget.controller.text;
    final selection = safeSelection();
    final start = math.min(selection.start, selection.end);
    final end = math.max(selection.start, selection.end);
    widget.controller.value = TextEditingValue(
      text: text.replaceRange(start, end, replacement),
      selection: TextSelection(
        baseOffset: selectedStart,
        extentOffset: selectedEnd,
      ),
    );
    focusNode.requestFocus();
  }

  void wrapSelection(String prefix, String suffix, String placeholder) {
    final text = widget.controller.text;
    final selection = safeSelection();
    final start = math.min(selection.start, selection.end);
    final end = math.max(selection.start, selection.end);
    final selected = text.substring(start, end);
    final body = selected.isEmpty ? placeholder : selected;
    final replacement = '$prefix$body$suffix';
    final selectedStart = start + prefix.length;
    replaceSelection(
      replacement,
      selectedStart: selectedStart,
      selectedEnd: selectedStart + body.length,
    );
  }

  void insertBlock(String before, String after, String placeholder) {
    final text = widget.controller.text;
    final selection = safeSelection();
    final start = math.min(selection.start, selection.end);
    final end = math.max(selection.start, selection.end);
    final selected = text.substring(start, end);
    final body = selected.isEmpty ? placeholder : selected;
    final replacement = '$before$body$after';
    final selectedStart = start + before.length;
    replaceSelection(
      replacement,
      selectedStart: selectedStart,
      selectedEnd: selectedStart + body.length,
    );
  }

  void prefixSelectedLines(String Function(int index) prefixForLine) {
    final text = widget.controller.text;
    final selection = safeSelection();
    final start = math.min(selection.start, selection.end);
    final end = math.max(selection.start, selection.end);
    final lineStart = text.lastIndexOf('\n', math.max(0, start - 1)) + 1;
    var lineEnd = text.indexOf('\n', end);
    if (lineEnd < 0) {
      lineEnd = text.length;
    }
    final segment = text.substring(lineStart, lineEnd);
    final lines = segment.split('\n');
    final replacement = [
      for (var i = 0; i < lines.length; i++) '${prefixForLine(i)}${lines[i]}',
    ].join('\n');
    widget.controller.value = TextEditingValue(
      text: text.replaceRange(lineStart, lineEnd, replacement),
      selection: TextSelection(
        baseOffset: lineStart,
        extentOffset: lineStart + replacement.length,
      ),
    );
    focusNode.requestFocus();
  }

  void insertLink() {
    final strings = context.strings;
    final text = widget.controller.text;
    final selection = safeSelection();
    final start = math.min(selection.start, selection.end);
    final end = math.max(selection.start, selection.end);
    final selected = text.substring(start, end);
    final label = selected.isEmpty ? strings.text('Text') : selected;
    const url = 'https://';
    final replacement = '[$label]($url)';
    widget.controller.value = TextEditingValue(
      text: text.replaceRange(start, end, replacement),
      selection: TextSelection(
        baseOffset: start + label.length + 3,
        extentOffset: start + label.length + 3 + url.length,
      ),
    );
    focusNode.requestFocus();
  }

  void applyAction(_SpaceMarkdownAction action) {
    final strings = context.strings;
    switch (action) {
      case _SpaceMarkdownAction.bold:
        wrapSelection('**', '**', strings.text('Text'));
        break;
      case _SpaceMarkdownAction.italic:
        wrapSelection('*', '*', strings.text('Text'));
        break;
      case _SpaceMarkdownAction.strikethrough:
        wrapSelection('~~', '~~', strings.text('Text'));
        break;
      case _SpaceMarkdownAction.heading:
        prefixSelectedLines((_) => '## ');
        break;
      case _SpaceMarkdownAction.quote:
        prefixSelectedLines((_) => '> ');
        break;
      case _SpaceMarkdownAction.bulletList:
        prefixSelectedLines((_) => '- ');
        break;
      case _SpaceMarkdownAction.numberedList:
        prefixSelectedLines((index) => '${index + 1}. ');
        break;
      case _SpaceMarkdownAction.inlineCode:
        wrapSelection('`', '`', strings.text('code'));
        break;
      case _SpaceMarkdownAction.codeBlock:
        insertBlock('```\n', '\n```', strings.text('code'));
        break;
      case _SpaceMarkdownAction.link:
        insertLink();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = Theme.of(context).colorScheme;
    final content = widget.controller.text.trim();
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColoredBox(
              color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Row(
                  children: [
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment<bool>(
                          value: false,
                          icon: const Icon(Icons.edit_outlined),
                          label: Text(strings.text('Edit')),
                        ),
                        ButtonSegment<bool>(
                          value: true,
                          icon: const Icon(Icons.visibility_outlined),
                          label: Text(strings.text('Preview')),
                        ),
                      ],
                      selected: {preview},
                      showSelectedIcon: false,
                      onSelectionChanged: (value) {
                        setState(() => preview = value.first);
                        if (!preview) {
                          focusNode.requestFocus();
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final action in _SpaceMarkdownAction.values)
                              _SpaceMarkdownActionButton(
                                action: action,
                                enabled: !preview,
                                onPressed: () => applyAction(action),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            if (preview)
              Padding(
                padding: const EdgeInsets.all(12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 150),
                  child: content.isEmpty
                      ? _EmptyPanel(
                          message: strings.text('Nothing to preview.'),
                        )
                      : _SpaceMarkdownContent(text: content),
                ),
              )
            else
              TextField(
                controller: widget.controller,
                focusNode: focusNode,
                minLines: 5,
                maxLines: 10,
                autofocus: true,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _SpaceMarkdownAction {
  bold,
  italic,
  strikethrough,
  heading,
  quote,
  bulletList,
  numberedList,
  inlineCode,
  codeBlock,
  link,
}

class _SpaceMarkdownActionButton extends StatelessWidget {
  const _SpaceMarkdownActionButton({
    required this.action,
    required this.enabled,
    required this.onPressed,
  });

  final _SpaceMarkdownAction action;
  final bool enabled;
  final VoidCallback onPressed;

  String tooltip(CsacStrings strings) {
    switch (action) {
      case _SpaceMarkdownAction.bold:
        return strings.text('Bold');
      case _SpaceMarkdownAction.italic:
        return strings.text('Italic');
      case _SpaceMarkdownAction.strikethrough:
        return strings.text('Strikethrough');
      case _SpaceMarkdownAction.heading:
        return strings.text('Heading');
      case _SpaceMarkdownAction.quote:
        return strings.text('Quote');
      case _SpaceMarkdownAction.bulletList:
        return strings.text('Bulleted list');
      case _SpaceMarkdownAction.numberedList:
        return strings.text('Numbered list');
      case _SpaceMarkdownAction.inlineCode:
        return strings.text('Inline code');
      case _SpaceMarkdownAction.codeBlock:
        return strings.text('Code block');
      case _SpaceMarkdownAction.link:
        return strings.text('Insert link');
    }
  }

  IconData get icon {
    switch (action) {
      case _SpaceMarkdownAction.bold:
        return Icons.format_bold;
      case _SpaceMarkdownAction.italic:
        return Icons.format_italic;
      case _SpaceMarkdownAction.strikethrough:
        return Icons.format_strikethrough;
      case _SpaceMarkdownAction.heading:
        return Icons.title;
      case _SpaceMarkdownAction.quote:
        return Icons.format_quote;
      case _SpaceMarkdownAction.bulletList:
        return Icons.format_list_bulleted;
      case _SpaceMarkdownAction.numberedList:
        return Icons.format_list_numbered;
      case _SpaceMarkdownAction.inlineCode:
        return Icons.code;
      case _SpaceMarkdownAction.codeBlock:
        return Icons.data_object;
      case _SpaceMarkdownAction.link:
        return Icons.link;
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip(context.strings),
      visualDensity: VisualDensity.compact,
      iconSize: 20,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon),
    );
  }
}

class _SpaceImageGrid extends StatelessWidget {
  const _SpaceImageGrid({required this.postId, required this.images});

  final int postId;
  final List<String> images;

  @override
  Widget build(BuildContext context) {
    final count = images.length;
    final columns = count == 1 ? 1 : (count <= 4 ? 2 : 3);
    final maxWidth = count == 1 ? 320.0 : (count <= 4 ? 380.0 : 450.0);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: count,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
          ),
          itemBuilder: (context, index) {
            final url = images[index];
            final heroTag = 'space-image:$postId:$index';
            return InkWell(
              onTap: () => showImagePreview(context, url, heroTag: heroTag),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Hero(
                  tag: heroTag,
                  child: Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const ColoredBox(
                      color: Colors.black12,
                      child: Center(child: Icon(Icons.broken_image_outlined)),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SpaceComposeSheet extends StatefulWidget {
  const _SpaceComposeSheet({required this.title, required this.submitLabel});

  final String title;
  final String submitLabel;

  @override
  State<_SpaceComposeSheet> createState() => _SpaceComposeSheetState();
}

class _SpaceComposeSheetState extends State<_SpaceComposeSheet> {
  static const maxImages = 9;
  static const maxImageBytes = 5 * 1024 * 1024;

  final content = TextEditingController();
  final picker = ImagePicker();
  final images = <_SpaceImageDraft>[];
  bool picking = false;
  String? error;

  @override
  void dispose() {
    content.dispose();
    super.dispose();
  }

  Future<void> pickImages() async {
    if (picking || images.length >= maxImages) {
      return;
    }
    setState(() {
      picking = true;
      error = null;
    });
    try {
      final picked = await picker.pickMultiImage(imageQuality: 90);
      if (!mounted || picked.isEmpty) {
        return;
      }
      var skippedLarge = false;
      for (final file in picked.take(maxImages - images.length)) {
        final bytes = await file.readAsBytes();
        if (bytes.length > maxImageBytes) {
          skippedLarge = true;
          continue;
        }
        images.add(
          _SpaceImageDraft(
            fileName: pickedImageFileName(file, ImageSource.gallery),
            bytes: bytes,
          ),
        );
      }
      setState(() {
        error = skippedLarge
            ? context.strings.text('Some images exceed 5 MB.')
            : null;
      });
    } catch (err) {
      if (mounted) {
        setState(() => error = err.toString());
      }
    } finally {
      if (mounted) {
        setState(() => picking = false);
      }
    }
  }

  void submit() {
    if (content.text.trim().isEmpty && images.isEmpty) {
      setState(
        () => error = context.strings.text(
          'Please enter text or choose at least one image.',
        ),
      );
      return;
    }
    if (isMobilePlatform) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    Navigator.of(
      context,
    ).pop(_SpaceDraft(content: content.text.trim(), images: List.of(images)));
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(18, 0, 18, bottom + 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            _SpaceMarkdownEditor(
              controller: content,
              hintText: strings.text("What's new?"),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: picking || images.length >= maxImages
                      ? null
                      : pickImages,
                  icon: picking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.photo_library_outlined),
                  label: Text(strings.text('Choose images')),
                ),
                const SizedBox(width: 10),
                Text(
                  strings.format('{count}/9 images', {'count': images.length}),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            if (images.isNotEmpty) ...[
              const SizedBox(height: 12),
              _SpaceSelectedImageGrid(
                images: images,
                onRemove: (index) => setState(() => images.removeAt(index)),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(strings.text('Cancel')),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: submit,
                  icon: const Icon(Icons.send_outlined),
                  label: Text(widget.submitLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SpaceSelectedImageGrid extends StatelessWidget {
  const _SpaceSelectedImageGrid({required this.images, required this.onRemove});

  final List<_SpaceImageDraft> images;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: images.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemBuilder: (context, index) {
        return Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(images[index].bytes, fit: BoxFit.cover),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton.filledTonal(
                tooltip: context.strings.text('Remove image'),
                visualDensity: VisualDensity.compact,
                onPressed: () => onRemove(index),
                icon: const Icon(Icons.close, size: 18),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SpaceDraft {
  const _SpaceDraft({required this.content, required this.images});

  final String content;
  final List<_SpaceImageDraft> images;

  List<CsacUploadFile> get uploadFiles {
    return [
      for (final image in images)
        CsacUploadFile(
          fieldName: 'images',
          bytes: image.bytes,
          fileName: image.fileName,
        ),
    ];
  }
}

class _SpaceImageDraft {
  const _SpaceImageDraft({required this.fileName, required this.bytes});

  final String fileName;
  final Uint8List bytes;
}

List<SpacePost> _mergeSpacePosts(
  List<SpacePost> existing,
  List<SpacePost> incoming,
) {
  final byId = <int, SpacePost>{for (final post in existing) post.id: post};
  for (final post in incoming) {
    byId[post.id] = post;
  }
  final merged = byId.values.toList();
  merged.sort((a, b) {
    final byTime = timestampForSort(
      b.createdAt,
    ).compareTo(timestampForSort(a.createdAt));
    return byTime == 0 ? b.id.compareTo(a.id) : byTime;
  });
  return merged;
}

List<SpacePost> _replaceSpacePost(
  List<SpacePost> posts,
  int postId,
  SpacePost Function(SpacePost post) replace,
) {
  return [
    for (final post in posts)
      if (post.id == postId)
        replace(post)
      else
        post.copyWith(
          replies: [
            for (final reply in post.replies)
              if (reply.id == postId) replace(reply) else reply,
          ],
        ),
  ];
}

List<SpacePost> _removeSpacePost(List<SpacePost> posts, int postId) {
  return [
    for (final post in posts)
      if (post.id != postId)
        post.copyWith(
          replies: [
            for (final reply in post.replies)
              if (reply.id != postId) reply,
          ],
        ),
  ];
}

class AddFriendScreen extends StatefulWidget {
  const AddFriendScreen({super.key, required this.state});

  final CsacAppState state;

  @override
  State<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends State<AddFriendScreen> {
  final uid = TextEditingController();
  final message = TextEditingController(text: '请求添加你为好友');
  UserProfile? preview;
  bool sending = false;
  bool searching = false;
  String? error;

  @override
  void dispose() {
    uid.dispose();
    message.dispose();
    super.dispose();
  }

  Future<void> lookup() async {
    final target = int.tryParse(uid.text.trim()) ?? 0;
    if (target <= 0) {
      setState(() => error = context.strings.text('Enter a valid UID.'));
      return;
    }
    setState(() {
      searching = true;
      error = null;
      preview = null;
    });
    try {
      final loaded = await widget.state.loadUserProfile(target);
      if (!mounted) {
        return;
      }
      setState(() => preview = loaded);
    } catch (err) {
      if (mounted) {
        setState(() => error = err.toString());
      }
    } finally {
      if (mounted) {
        setState(() => searching = false);
      }
    }
  }

  Future<void> submit() async {
    final target = int.tryParse(uid.text.trim()) ?? 0;
    if (target <= 0) {
      setState(() => error = context.strings.text('Enter a valid UID.'));
      return;
    }
    setState(() {
      sending = true;
      error = null;
    });
    try {
      await widget.state.sendFriendRequest(target, message.text);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.text('Friend request sent.'))),
      );
      Navigator.of(context).pop();
    } catch (err) {
      if (mounted) {
        setState(() => error = err.toString());
      }
    } finally {
      if (mounted) {
        setState(() => sending = false);
      }
    }
  }

  Future<void> openPreviewProfile() async {
    final profile = preview;
    if (profile == null) {
      return;
    }
    await openUserProfile(context, widget.state, profile.uid);
    if (mounted) {
      await lookup();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.strings.text('Add friend'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            TextField(
              controller: uid,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => lookup(),
              decoration: InputDecoration(
                labelText: context.strings.text('User UID'),
                prefixIcon: const Icon(Icons.tag),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: searching ? null : lookup,
              icon: searching
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: Text(context.strings.text('Lookup user')),
            ),
            if (preview != null) ...[
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                child: ListTile(
                  onTap: openPreviewProfile,
                  leading: _Avatar(
                    url: preview!.avatar,
                    fallback: Icons.person_rounded,
                  ),
                  title: Text(preview!.displayName),
                  subtitle: Text(
                    preview!.subtitle.isEmpty
                        ? 'UID ${preview!.uid}'
                        : preview!.subtitle,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: message,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: context.strings.text('Request message'),
                prefixIcon: const Icon(Icons.message_outlined),
                border: const OutlineInputBorder(),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: sending ? null : submit,
              icon: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: Text(context.strings.text('Send request')),
            ),
          ],
        ),
      ),
    );
  }
}

class JoinGroupScreen extends StatefulWidget {
  const JoinGroupScreen({super.key, required this.state});

  final CsacAppState state;

  @override
  State<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends State<JoinGroupScreen> {
  final roomId = TextEditingController();
  final code = TextEditingController();
  final answer = TextEditingController();
  final search = TextEditingController();
  List<GroupProfile> publicGroups = const <GroupProfile>[];
  bool loading = true;
  bool sending = false;
  String? error;

  @override
  void initState() {
    super.initState();
    loadPublicGroups();
  }

  @override
  void dispose() {
    roomId.dispose();
    code.dispose();
    answer.dispose();
    search.dispose();
    super.dispose();
  }

  Future<void> loadPublicGroups() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final loaded = await widget.state.loadPublicGroups();
      if (!mounted) {
        return;
      }
      setState(() => publicGroups = loaded);
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

  Future<void> submit({int? groupId}) async {
    final target = groupId ?? int.tryParse(roomId.text.trim()) ?? 0;
    if (target <= 0) {
      setState(() => error = context.strings.text('Enter a valid room ID.'));
      return;
    }
    setState(() {
      sending = true;
      error = null;
    });
    try {
      await widget.state.applyJoinGroup(
        target,
        code: code.text,
        answer: answer.text,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.text('Join request sent.'))),
      );
      Navigator.of(context).pop();
    } catch (err) {
      if (mounted) {
        setState(() => error = err.toString());
      }
    } finally {
      if (mounted) {
        setState(() => sending = false);
      }
    }
  }

  void useGroup(GroupProfile group) {
    roomId.text = '${group.id}';
    if (group.code.isNotEmpty) {
      code.text = group.code;
    }
    if (group.question.isNotEmpty) {
      answer.selection = TextSelection.collapsed(offset: answer.text.length);
    }
  }

  List<GroupProfile> filteredPublicGroups() {
    final query = search.text.trim().toLowerCase();
    if (query.isEmpty) {
      return publicGroups;
    }
    return publicGroups.where((group) {
      final target =
          '${group.id} ${group.name} ${group.subtitle} ${group.description} ${group.notice}'
              .toLowerCase();
      return target.contains(query);
    }).toList();
  }

  void openGroupDetail(GroupProfile group) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConversationDetailScreen(
          state: widget.state,
          conversation: Conversation(
            type: ConversationType.group,
            id: group.id,
            name: group.name,
            avatar: group.avatar,
            subtitle: group.subtitle,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.strings.text('Join group')),
        actions: [
          IconButton(
            tooltip: context.strings.text('Refresh'),
            onPressed: loading ? null : loadPublicGroups,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: loadPublicGroups,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              TextField(
                controller: roomId,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.strings.text('Room ID'),
                  prefixIcon: const Icon(Icons.tag),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: code,
                decoration: InputDecoration(
                  labelText: context.strings.text('Invite code'),
                  prefixIcon: const Icon(Icons.key_outlined),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: answer,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: context.strings.text('Answer'),
                  prefixIcon: const Icon(Icons.question_answer_outlined),
                  border: const OutlineInputBorder(),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: sending ? null : submit,
                icon: sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.group_add),
                label: Text(context.strings.text('Apply to join')),
              ),
              const SizedBox(height: 20),
              Text(
                context.strings.text('Public groups'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: context.strings.text('Search public groups'),
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              if (loading)
                const LinearProgressIndicator(minHeight: 2)
              else if (filteredPublicGroups().isEmpty)
                _EmptyPanel(message: context.strings.text('No public groups.'))
              else
                for (final group in filteredPublicGroups())
                  Card(
                    elevation: 0,
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.secondaryContainer,
                        child: Icon(
                          Icons.groups_rounded,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSecondaryContainer,
                        ),
                      ),
                      title: Text(group.name),
                      subtitle: Text(
                        [
                          context.strings.format('Room {id}', {'id': group.id}),
                          group.subtitle,
                          group.description,
                        ].where((part) => part.isNotEmpty).join(' | '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: TextButton(
                        onPressed: sending
                            ? null
                            : () {
                                useGroup(group);
                                submit(groupId: group.id);
                              },
                        child: Text(context.strings.text('Join')),
                      ),
                      onTap: () => useGroup(group),
                      onLongPress: () => openGroupDetail(group),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key, required this.state});

  final CsacAppState state;

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final roomName = TextEditingController();
  bool creating = false;
  String? error;

  @override
  void dispose() {
    roomName.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final name = roomName.text.trim();
    if (name.isEmpty) {
      setState(() => error = context.strings.text('Room name is required.'));
      return;
    }
    setState(() {
      creating = true;
      error = null;
    });
    try {
      final group = await widget.state.createGroup(name);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.strings.format('Group created: {name}', {
              'name': group.name,
            }),
          ),
        ),
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ConversationDetailScreen(
            state: widget.state,
            conversation: Conversation(
              type: ConversationType.group,
              id: group.id,
              name: group.name,
              avatar: group.avatar,
              subtitle: group.subtitle,
            ),
          ),
        ),
      );
    } catch (err) {
      if (mounted) {
        setState(() => error = err.toString());
      }
    } finally {
      if (mounted) {
        setState(() => creating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(title: Text(strings.text('Create group'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            TextField(
              controller: roomName,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => submit(),
              decoration: InputDecoration(
                labelText: strings.text('Room name'),
                prefixIcon: const Icon(Icons.groups_outlined),
                border: const OutlineInputBorder(),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: creating ? null : submit,
              icon: creating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add),
              label: Text(strings.text('Create group')),
            ),
          ],
        ),
      ),
    );
  }
}

enum _SearchTab { all, messages, conversations, space, users }

class _SpaceSearchResult {
  const _SpaceSearchResult({required this.post, required this.snippet});

  final SpacePost post;
  final String snippet;
}

class _UserSearchResult {
  const _UserSearchResult({
    required this.uid,
    required this.name,
    this.avatar = '',
    this.subtitle = '',
    this.conversation,
  });

  final int uid;
  final String name;
  final String avatar;
  final String subtitle;
  final Conversation? conversation;
}

class MessageSearchScreen extends StatefulWidget {
  const MessageSearchScreen({
    super.key,
    required this.state,
    this.embedded = false,
    this.initialQuery = '',
    this.conversation,
  });

  final CsacAppState state;
  final bool embedded;
  final String initialQuery;
  final Conversation? conversation;

  @override
  State<MessageSearchScreen> createState() => _MessageSearchScreenState();
}

class _MessageSearchScreenState extends State<MessageSearchScreen> {
  final search = TextEditingController();
  final sender = TextEditingController();
  SearchScope scope = SearchScope.all;
  _SearchTab tab = _SearchTab.all;
  MessageSearchDateRange dateRange = MessageSearchDateRange.any;
  List<MessageSearchResult> results = const <MessageSearchResult>[];
  List<Conversation> conversationResults = const <Conversation>[];
  List<_SpaceSearchResult> spaceResults = const <_SpaceSearchResult>[];
  List<_UserSearchResult> userResults = const <_UserSearchResult>[];
  bool loading = false;
  bool filtersExpanded = false;
  String? error;
  Timer? debounce;

  bool get scopedToConversation => widget.conversation != null;

  bool get filterOnlySearch =>
      scope == SearchScope.image ||
      scope == SearchScope.link ||
      scope == SearchScope.code ||
      scope == SearchScope.essence ||
      sender.text.trim().isNotEmpty ||
      dateRange != MessageSearchDateRange.any ||
      scopedToConversation;

  int get totalCount =>
      results.length +
      conversationResults.length +
      spaceResults.length +
      userResults.length;

  @override
  void initState() {
    super.initState();
    search.text = widget.initialQuery.trim();
    sender.addListener(scheduleSearch);
    runSearch();
  }

  @override
  void didUpdateWidget(covariant MessageSearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextQuery = widget.initialQuery.trim();
    if (nextQuery != oldWidget.initialQuery.trim() &&
        nextQuery != search.text.trim()) {
      search.text = nextQuery;
      runSearch();
    }
    if (widget.conversation?.id != oldWidget.conversation?.id ||
        widget.conversation?.type != oldWidget.conversation?.type) {
      runSearch();
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    sender.dispose();
    super.dispose();
  }

  void scheduleSearch() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 250), runSearch);
  }

  Future<void> runSearch() async {
    setState(() {});
    final query = search.text.trim();
    if (query.isEmpty && !filterOnlySearch) {
      setState(() {
        results = const <MessageSearchResult>[];
        conversationResults = const <Conversation>[];
        spaceResults = const <_SpaceSearchResult>[];
        userResults = const <_UserSearchResult>[];
        loading = false;
        error = null;
      });
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final filter = MessageSearchFilter(
        scope: scope,
        conversation: widget.conversation,
        senderQuery: sender.text,
        dateRange: dateRange,
      );
      final loaded = await widget.state.searchMessages(
        query,
        scope,
        filter: filter,
      );
      final loadedConversations = scopedToConversation
          ? const <Conversation>[]
          : searchConversations(query);
      final loadedUsers = scopedToConversation
          ? const <_UserSearchResult>[]
          : await searchUsers(query, loadedConversations);
      final loadedSpace = scopedToConversation
          ? const <_SpaceSearchResult>[]
          : await searchSpacePosts(query);
      if (!mounted) {
        return;
      }
      setState(() {
        results = loaded;
        conversationResults = loadedConversations;
        userResults = loadedUsers;
        spaceResults = loadedSpace;
      });
    } catch (err) {
      if (!mounted) {
        return;
      }
      setState(() => error = err.toString());
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  void setScope(SearchScope value) {
    setState(() => scope = value);
    runSearch();
  }

  void setDateRange(MessageSearchDateRange value) {
    setState(() => dateRange = value);
    runSearch();
  }

  void setTab(_SearchTab value) {
    setState(() => tab = value);
  }

  List<Conversation> searchConversations(String rawQuery) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return const <Conversation>[];
    }
    return widget.state.conversations
        .where((conversation) {
          final target = [
            conversation.name,
            conversation.subtitle,
            conversation.statusSubtitle,
            conversation.lastMessagePreview,
            conversation.searchText,
            '${conversation.id}',
          ].join(' ').toLowerCase();
          return target.contains(query);
        })
        .take(30)
        .toList();
  }

  Future<List<_UserSearchResult>> searchUsers(
    String rawQuery,
    List<Conversation> conversations,
  ) async {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return const <_UserSearchResult>[];
    }
    final found = <_UserSearchResult>[];
    final seen = <int>{};
    for (final conversation in conversations) {
      if (conversation.type != ConversationType.private ||
          !seen.add(conversation.id)) {
        continue;
      }
      found.add(
        _UserSearchResult(
          uid: conversation.id,
          name: conversation.name,
          avatar: conversation.avatar,
          subtitle: conversation.subtitle.isEmpty
              ? 'UID ${conversation.id}'
              : conversation.subtitle,
          conversation: conversation,
        ),
      );
    }
    final uid = int.tryParse(query);
    if (uid != null && uid > 0 && !seen.contains(uid)) {
      final uidSubtitle = context.strings.text('Open user profile by UID');
      try {
        final profile = await widget.state.loadUserProfile(uid);
        found.insert(
          0,
          _UserSearchResult(
            uid: profile.uid,
            name: profile.displayName,
            avatar: profile.avatar,
            subtitle: profile.subtitle.isEmpty
                ? 'UID ${profile.uid}'
                : profile.subtitle,
          ),
        );
      } catch (_) {
        found.insert(
          0,
          _UserSearchResult(uid: uid, name: 'UID $uid', subtitle: uidSubtitle),
        );
      }
    }
    return found.take(30).toList();
  }

  Future<List<_SpaceSearchResult>> searchSpacePosts(String rawQuery) async {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return const <_SpaceSearchResult>[];
    }
    final found = <_SpaceSearchResult>[];
    const pageSize = 30;
    for (var page = 1; page <= 3 && found.length < 30; page++) {
      final loaded = await widget.state.client.spacePosts(
        page: page,
        pageSize: pageSize,
      );
      if (loaded.posts.isEmpty) {
        break;
      }
      for (final post in loaded.posts) {
        if (spacePostMatches(post, query)) {
          found.add(
            _SpaceSearchResult(
              post: post,
              snippet: spacePostSnippet(post, rawQuery),
            ),
          );
          if (found.length >= 30) {
            break;
          }
        }
      }
      if (loaded.posts.length < pageSize) {
        break;
      }
    }
    return found;
  }

  bool spacePostMatches(SpacePost post, String query) {
    final target = [
      post.displayName,
      post.content,
      post.createdAt,
      '${post.senderUid}',
      '${post.id}',
      for (final reply in post.replies) reply.displayName,
      for (final reply in post.replies) reply.content,
    ].join(' ').toLowerCase();
    return target.contains(query);
  }

  String spacePostSnippet(SpacePost post, String query) {
    final source = post.content.trim().isNotEmpty
        ? post.content.trim()
        : post.images.isNotEmpty
        ? context.strings.text('Images')
        : post.displayName;
    return searchSnippet(source, query);
  }

  String searchSnippet(String text, String query, {int max = 120}) {
    final body = text.trim();
    if (body.isEmpty) {
      return context.strings.text('(empty)');
    }
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return body.length <= max ? body : '${body.substring(0, max)}...';
    }
    final index = body.toLowerCase().indexOf(needle);
    if (index < 0) {
      return body.length <= max ? body : '${body.substring(0, max)}...';
    }
    final start = (index - 36).clamp(0, body.length);
    final end = (index + needle.length + 72).clamp(0, body.length);
    return '${start > 0 ? '...' : ''}${body.substring(start, end)}${end < body.length ? '...' : ''}';
  }

  Future<void> openResult(MessageSearchResult result) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          state: widget.state,
          conversation: result.conversation,
          focusMessageId: result.message.id,
        ),
      ),
    );
  }

  Future<void> openConversationResult(Conversation conversation) async {
    await widget.state.markConversationRead(conversation);
    widget.state.setActiveConversation(conversation);
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ChatScreen(state: widget.state, conversation: conversation),
      ),
    );
  }

  Future<void> openSpaceResult(_SpaceSearchResult result) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SpaceFeedScreen(state: widget.state, focusPostId: result.post.id),
      ),
    );
  }

  Future<void> openUserResult(_UserSearchResult result) async {
    final conversation = result.conversation;
    if (conversation != null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => UserProfileScreen(
            state: widget.state,
            uid: result.uid,
            avatarHeroTag: conversationAvatarHeroTag(conversation),
          ),
        ),
      );
      return;
    }
    await openUserProfile(context, widget.state, result.uid);
  }

  Future<void> openResultQr(MessageSearchResult result) {
    final strings = context.strings;
    final conversation = result.conversation;
    final message = result.message;
    final link = conversation.type == ConversationType.group
        ? csacGroupMessageDeepLink(conversation.id, message.id)
        : csacPrivateMessageDeepLink(conversation.id, message.id);
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CsacQrShareScreen(
          appBarTitle: strings.text('Search result QR code'),
          link: link,
          cardTitle: conversation.name,
          cardSubtitle: strings.format('Message #{id} from {name}', {
            'id': message.id,
            'name': message.sender,
          }),
          avatarUrl: conversation.avatar,
          fallbackIcon: conversation.type == ConversationType.group
              ? Icons.groups_rounded
              : Icons.person_rounded,
          helperText: strings.text('Scan to open this search result in CsAC.'),
          semanticsLabel: strings.text('CsAC search result QR code'),
          shareTitle: strings.text('Share search result QR code'),
          shareSubject: strings.text('CsAC search result QR code'),
          fileName:
              'csac-search-result-${conversation.type.name}-${conversation.id}-${message.id}.png',
          copySnackText: strings.text('Search result link copied.'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final visibleResults = visibleResultWidgets(strings);
    final body = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: TextField(
            controller: search,
            onChanged: (_) => scheduleSearch(),
            autofocus: !widget.embedded,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => runSearch(),
            decoration: InputDecoration(
              hintText: scopedToConversation
                  ? strings.text('Search this conversation')
                  : strings.text('Search messages, chats, posts and users'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: strings.text('Filters'),
                    onPressed: () =>
                        setState(() => filtersExpanded = !filtersExpanded),
                    icon: Icon(
                      filtersExpanded ? Icons.tune : Icons.tune_outlined,
                    ),
                  ),
                  if (search.text.trim().isNotEmpty)
                    IconButton(
                      tooltip: strings.text('Clear'),
                      onPressed: () {
                        search.clear();
                        runSearch();
                      },
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        if (scopedToConversation)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: _SearchScopeBanner(conversation: widget.conversation!),
          ),
        SizedBox(
          height: 46,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            children: [
              _ScopeChip(
                label: strings.text('All'),
                selected: scope == SearchScope.all,
                onSelected: () => setScope(SearchScope.all),
              ),
              _ScopeChip(
                label: strings.text('Friends'),
                selected: scope == SearchScope.private,
                onSelected: () => setScope(SearchScope.private),
              ),
              _ScopeChip(
                label: strings.text('Groups'),
                selected: scope == SearchScope.group,
                onSelected: () => setScope(SearchScope.group),
              ),
              _ScopeChip(
                label: strings.text('Images'),
                selected: scope == SearchScope.image,
                onSelected: () => setScope(SearchScope.image),
              ),
              _ScopeChip(
                label: strings.text('Links'),
                selected: scope == SearchScope.link,
                onSelected: () => setScope(SearchScope.link),
              ),
              _ScopeChip(
                label: strings.text('Code'),
                selected: scope == SearchScope.code,
                onSelected: () => setScope(SearchScope.code),
              ),
              _ScopeChip(
                label: strings.text('Essence'),
                selected: scope == SearchScope.essence,
                onSelected: () => setScope(SearchScope.essence),
              ),
            ],
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: _SearchFiltersPanel(
            sender: sender,
            dateRange: dateRange,
            onDateRangeChanged: setDateRange,
            onApply: runSearch,
          ),
          crossFadeState: filtersExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 180),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            children: [
              _SearchTabChip(
                label: strings.text('All'),
                count: totalCount,
                selected: tab == _SearchTab.all,
                onSelected: () => setTab(_SearchTab.all),
              ),
              _SearchTabChip(
                label: strings.text('Messages'),
                count: results.length,
                selected: tab == _SearchTab.messages,
                onSelected: () => setTab(_SearchTab.messages),
              ),
              if (!scopedToConversation) ...[
                _SearchTabChip(
                  label: strings.text('Conversations'),
                  count: conversationResults.length,
                  selected: tab == _SearchTab.conversations,
                  onSelected: () => setTab(_SearchTab.conversations),
                ),
                _SearchTabChip(
                  label: strings.text('Space'),
                  count: spaceResults.length,
                  selected: tab == _SearchTab.space,
                  onSelected: () => setTab(_SearchTab.space),
                ),
                _SearchTabChip(
                  label: strings.text('Users'),
                  count: userResults.length,
                  selected: tab == _SearchTab.users,
                  onSelected: () => setTab(_SearchTab.users),
                ),
              ],
            ],
          ),
        ),
        if (loading) const LinearProgressIndicator(minHeight: 2),
        if (error != null)
          MaterialBanner(
            content: Text(error!),
            actions: [
              TextButton(
                onPressed: () => setState(() => error = null),
                child: Text(strings.text('Dismiss')),
              ),
            ],
          ),
        Expanded(
          child: visibleResults.isEmpty
              ? _EmptyPanel(
                  message: search.text.trim().isEmpty && !filterOnlySearch
                      ? strings.text(
                          'Type to search messages, chats, posts or users.',
                        )
                      : strings.text('No matching results.'),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 18),
                  children: visibleResults,
                ),
        ),
      ],
    );
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: Text(
                scopedToConversation
                    ? strings.text('Search this conversation')
                    : strings.text('Global search'),
              ),
            ),
      body: SafeArea(top: widget.embedded, child: body),
    );
  }

  List<Widget> visibleResultWidgets(CsacStrings strings) {
    final widgets = <Widget>[];
    void addSection(String title, int count, List<Widget> children) {
      if (children.isEmpty) {
        return;
      }
      widgets.add(_SearchSectionHeader(title: title, count: count));
      widgets.addAll(children);
    }

    if (tab == _SearchTab.all || tab == _SearchTab.messages) {
      addSection(strings.text('Messages'), results.length, [
        for (var i = 0; i < results.length; i++)
          _MotionListItem(
            index: i,
            child: _SearchResultTile(
              result: results[i],
              preferences: widget.state.preferences,
              onTap: () => openResult(results[i]),
              onShareQr: () => openResultQr(results[i]),
            ),
          ),
      ]);
    }
    if (tab == _SearchTab.all || tab == _SearchTab.conversations) {
      addSection(strings.text('Conversations'), conversationResults.length, [
        for (var i = 0; i < conversationResults.length; i++)
          _MotionListItem(
            index: i,
            child: _ConversationSearchTile(
              conversation: conversationResults[i],
              onTap: () => openConversationResult(conversationResults[i]),
            ),
          ),
      ]);
    }
    if (tab == _SearchTab.all || tab == _SearchTab.space) {
      addSection(strings.text('Space'), spaceResults.length, [
        for (var i = 0; i < spaceResults.length; i++)
          _MotionListItem(
            index: i,
            child: _SpaceSearchTile(
              result: spaceResults[i],
              onTap: () => openSpaceResult(spaceResults[i]),
            ),
          ),
      ]);
    }
    if (tab == _SearchTab.all || tab == _SearchTab.users) {
      addSection(strings.text('Users'), userResults.length, [
        for (var i = 0; i < userResults.length; i++)
          _MotionListItem(
            index: i,
            child: _UserSearchTile(
              result: userResults[i],
              onTap: () => openUserResult(userResults[i]),
            ),
          ),
      ]);
    }
    return widgets;
  }
}

class _SearchScopeBanner extends StatelessWidget {
  const _SearchScopeBanner({required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.filter_alt_outlined, color: colors.onSecondaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.strings.format('Limited to {name}', {
                  'name': conversation.name,
                }),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.onSecondaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchFiltersPanel extends StatelessWidget {
  const _SearchFiltersPanel({
    required this.sender,
    required this.dateRange,
    required this.onDateRangeChanged,
    required this.onApply,
  });

  final TextEditingController sender;
  final MessageSearchDateRange dateRange;
  final ValueChanged<MessageSearchDateRange> onDateRangeChanged;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: sender,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onApply(),
            decoration: InputDecoration(
              labelText: strings.text('Sender nickname or UID'),
              prefixIcon: const Icon(Icons.person_search_outlined),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _ScopeChip(
                  label: strings.text('Any time'),
                  selected: dateRange == MessageSearchDateRange.any,
                  onSelected: () =>
                      onDateRangeChanged(MessageSearchDateRange.any),
                ),
                _ScopeChip(
                  label: strings.text('Today'),
                  selected: dateRange == MessageSearchDateRange.today,
                  onSelected: () =>
                      onDateRangeChanged(MessageSearchDateRange.today),
                ),
                _ScopeChip(
                  label: strings.text('Last 7 days'),
                  selected: dateRange == MessageSearchDateRange.sevenDays,
                  onSelected: () =>
                      onDateRangeChanged(MessageSearchDateRange.sevenDays),
                ),
                _ScopeChip(
                  label: strings.text('Last 30 days'),
                  selected: dateRange == MessageSearchDateRange.thirtyDays,
                  onSelected: () =>
                      onDateRangeChanged(MessageSearchDateRange.thirtyDays),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchTabChip extends StatelessWidget {
  const _SearchTabChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text('$label ($count)'),
        selected: selected,
        onSelected: (_) => onSelected(),
      ),
    );
  }
}

class _SearchSectionHeader extends StatelessWidget {
  const _SearchSectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.onSurface,
              ),
            ),
          ),
          Text(
            '$count',
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
      ),
    );
  }
}

class _ConversationSearchTile extends StatelessWidget {
  const _ConversationSearchTile({
    required this.conversation,
    required this.onTap,
  });

  final Conversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: _RoundedInkClip(
        child: ListTile(
          onTap: onTap,
          leading: _ConversationAvatarHero(
            conversation: conversation,
            enabled: false,
          ),
          title: Text(
            conversation.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            [
              conversation.type == ConversationType.group
                  ? context.strings.text('Group chat')
                  : context.strings.text('Private chat'),
              conversation.lastMessagePreview,
              conversation.subtitle,
            ].where((part) => part.trim().isNotEmpty).join(' | '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
    );
  }
}

class _SpaceSearchTile extends StatelessWidget {
  const _SpaceSearchTile({required this.result, required this.onTap});

  final _SpaceSearchResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final post = result.post;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: _RoundedInkClip(
        child: ListTile(
          onTap: onTap,
          leading: _Avatar(url: post.avatar, fallback: Icons.dynamic_feed),
          title: Text(
            post.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [
                  context.strings.format('Post #{id}', {'id': post.id}),
                  post.createdAt,
                ].where((part) => part.trim().isNotEmpty).join(' | '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                result.snippet,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          trailing: post.images.isNotEmpty
              ? const Icon(Icons.image_outlined)
              : const Icon(Icons.chevron_right),
        ),
      ),
    );
  }
}

class _UserSearchTile extends StatelessWidget {
  const _UserSearchTile({required this.result, required this.onTap});

  final _UserSearchResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: _RoundedInkClip(
        child: ListTile(
          onTap: onTap,
          leading: _Avatar(url: result.avatar, fallback: Icons.person_rounded),
          title: Text(
            result.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            result.subtitle.isEmpty ? 'UID ${result.uid}' : result.subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.result,
    required this.preferences,
    required this.onTap,
    required this.onShareQr,
  });

  final MessageSearchResult result;
  final CsacPreferences preferences;
  final VoidCallback onTap;
  final VoidCallback onShareQr;

  @override
  Widget build(BuildContext context) {
    final isGroup = result.conversation.type == ConversationType.group;
    final message = result.message;
    final time = displayMessageTime(message, preferences);
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: _RoundedInkClip(
        child: ListTile(
          onTap: onTap,
          leading: CircleAvatar(
            backgroundColor: isGroup
                ? colors.secondaryContainer
                : colors.primaryContainer,
            child: Icon(
              isGroup ? Icons.groups_rounded : Icons.person_rounded,
              color: isGroup
                  ? colors.onSecondaryContainer
                  : colors.onPrimaryContainer,
            ),
          ),
          title: Text(
            result.conversation.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${message.sender}${time.isEmpty ? '' : ' · $time'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                result.snippet,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: context.strings.text('Share QR code'),
                onPressed: onShareQr,
                icon: const Icon(Icons.qr_code_2_outlined),
              ),
              Icon(
                message.imageUrl.isNotEmpty
                    ? Icons.image_outlined
                    : message.isEssence
                    ? Icons.star_outline
                    : Icons.chevron_right,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
