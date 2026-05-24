(function () {
  'use strict';

  var app = document.getElementById('app');
  var modalRoot = document.getElementById('modal-root');
  var toastRoot = document.getElementById('toast-root');
  var DEFAULT_AVATAR = 'default.png';
  var appIcon = 'icon/favicon.ico?v=20260511j';
  var MOBILE_LAYOUT_KEY = 'csac-mobile-layout-v2';
  var imageFileRe = /\.(?:avif|bmp|gif|ico|jpe?g|png|svg|webp)(?:[?#].*)?$/i;
  var failedAvatars = Object.create(null);

  var state = {
    booted: false,
    user: null,
    groups: [],
    friends: [],
    notifications: {},
    active: { type: '', id: 0 },
    roomMeta: null,
    roomMembers: [],
    roomMessages: [],
    roomHasMore: false,
    roomOldestId: 0,
    roomLatestId: 0,
    privateMessages: [],
    privateHasMore: false,
    privateOldestId: 0,
    privateLatestId: 0,
    privateFriend: null,
    essence: [],
    essenceStats: null,
    applications: [],
    reply: null,
    pollTimer: 0,
    recorder: null,
    recorderChunks: [],
    recording: null,
    routeHistory: [],
    adminToken: '',
    adminTokenExpire: 0
  };

  var navItems = [
    ['dashboard', '总览', '#/dashboard'],
    ['groups', '群组', '#/groups'],
    ['essence', '精华', '#/essence'],
    ['friends', '好友', '#/friends'],
    ['notices', '通知', '#/notices'],
    ['profile', '个人', '#/profile']
  ];

  function esc(value) {
    return String(value === undefined || value === null ? '' : value)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  function br(value) {
    return esc(value).replace(/\n/g, '<br>');
  }

  function int(value) {
    var number = parseInt(value, 10);
    return Number.isFinite(number) ? number : 0;
  }

  function uid() {
    return int(state.user && state.user.uid);
  }

  function text(value, fallback) {
    var out = String(value === undefined || value === null ? '' : value).trim();
    return out || fallback || '';
  }

  function plain(value) {
    return text(value, '').replace(/<[^>]*>/g, '');
  }

  function routeUrl(route) {
    return '#/' + route.replace(/^\/+/, '');
  }

  function setHash(route) {
    var target = routeUrl(route);
    if (window.location.hash === target) {
      renderRoute();
      return;
    }
    window.location.hash = target;
  }

  function parseHash() {
    var raw = window.location.hash.replace(/^#\/?/, '');
    if (!raw) {
      return { name: state.user ? 'dashboard' : 'login', parts: [], query: new URLSearchParams() };
    }
    var split = raw.split('?');
    var path = split[0].replace(/^\/+|\/+$/g, '');
    var parts = path ? path.split('/').map(decodeURIComponent) : [];
    return {
      name: parts[0] || (state.user ? 'dashboard' : 'login'),
      parts: parts,
      query: new URLSearchParams(split[1] || '')
    };
  }

  function currentName() {
    return parseHash().name;
  }

  function currentHashRoute() {
    return window.location.hash || '#/dashboard';
  }

  function pushRouteHistory(route) {
    var value = String(route || '').trim();
    if (!value) {
      return;
    }
    if (state.routeHistory[0] !== value) {
      state.routeHistory.unshift(value);
      if (state.routeHistory.length > 8) {
        state.routeHistory.length = 8;
      }
    }
  }

  function setEntryRoute(route) {
    try {
      sessionStorage.setItem('csac-entry-route', route || '');
    } catch (error) {}
  }

  function entryRoute() {
    try {
      return sessionStorage.getItem('csac-entry-route') || '';
    } catch (error) {
      return '';
    }
  }

  function defaultBackRoute() {
    var entry = entryRoute();
    if (entry && entry !== currentHashRoute()) {
      return entry;
    }
    var active = state.active && state.active.type;
    if (active === 'group') {
      return '#/groups';
    }
    if (active === 'private') {
      return '#/friends';
    }
    if (active === 'essence') {
      return '#/groups';
    }
    return '#/dashboard';
  }

  function goBackRoute() {
    var target = state.routeHistory.shift() || defaultBackRoute();
    window.location.hash = target;
  }

  function refreshActiveView() {
    if (state.active.type === 'group') {
      return renderGroupRoute(state.active.id);
    }
    if (state.active.type === 'private') {
      return renderPrivate(state.active.id);
    }
    if (state.active.type === 'essence') {
      return renderEssenceRoute(state.active.id, parseHash().query);
    }
    return renderRoute();
  }

  function clearPoll() {
    if (state.pollTimer) {
      window.clearInterval(state.pollTimer);
      state.pollTimer = 0;
    }
  }

  function toast(message, type) {
    var node = document.createElement('div');
    node.className = 'toast ' + (type || '');
    node.textContent = message || '操作完成';
    toastRoot.appendChild(node);
    window.setTimeout(function () {
      node.remove();
    }, 3600);
  }

  function closeModal() {
    modalRoot.innerHTML = '';
  }

  function openModal(title, body, footer) {
    modalRoot.innerHTML =
      '<div class="modal-backdrop" data-action="modal-close">' +
        '<div class="modal" role="dialog" aria-modal="true" data-modal-box>' +
          '<div class="modal-head">' +
            '<h3>' + esc(title) + '</h3>' +
            '<button class="icon-button" type="button" data-action="modal-close" aria-label="关闭">x</button>' +
          '</div>' +
          '<div class="modal-body">' + body + '</div>' +
          (footer ? '<div class="modal-foot">' + footer + '</div>' : '') +
        '</div>' +
      '</div>';
  }

  function openDrawer(title, body) {
    modalRoot.innerHTML =
      '<div class="modal-backdrop drawer-backdrop" data-action="modal-close">' +
        '<aside class="drawer" role="dialog" aria-modal="true" data-modal-box>' +
          '<div class="modal-head">' +
            '<h3>' + esc(title) + '</h3>' +
            '<button class="icon-button" type="button" data-action="modal-close" aria-label="关闭">x</button>' +
          '</div>' +
          '<div class="drawer-body">' + body + '</div>' +
        '</aside>' +
      '</div>';
  }

  function confirmDialog(title, message, onConfirm) {
    openModal(
      title,
      '<p>' + br(message) + '</p>',
      '<button class="button ghost" type="button" data-action="modal-close">取消</button>' +
      '<button class="button danger" type="button" data-action="confirm-modal">确认</button>'
    );
    modalRoot.querySelector('[data-action="confirm-modal"]').addEventListener('click', async function () {
      closeModal();
      await onConfirm();
    }, { once: true });
  }

  function applyTheme() {
    var theme = localStorage.getItem('csac-theme') || 'light';
    document.documentElement.classList.toggle('dark', theme === 'dark');
    applyMobileLayout();
  }

  function toggleTheme() {
    var next = document.documentElement.classList.contains('dark') ? 'light' : 'dark';
    localStorage.setItem('csac-theme', next);
    applyTheme();
  }

  function prefersMobileLayout() {
    var saved = localStorage.getItem(MOBILE_LAYOUT_KEY);
    if (saved === 'telegram') {
      return true;
    }
    if (saved === 'classic') {
      return false;
    }
    return window.matchMedia && window.matchMedia('(max-width: 760px), (max-width: 980px) and (pointer: coarse)').matches;
  }

  function isMobileTelegram() {
    return document.documentElement.classList.contains('mobile-telegram');
  }

  function applyMobileLayout() {
    document.documentElement.classList.toggle('mobile-telegram', prefersMobileLayout());
  }

  function mobileLayoutLabel() {
    return prefersMobileLayout() ? '经典' : '移动版';
  }

  function toggleMobileLayout() {
    var next = prefersMobileLayout() ? 'classic' : 'telegram';
    localStorage.setItem(MOBILE_LAYOUT_KEY, next);
    applyMobileLayout();
    toast(next === 'telegram' ? '已切换到移动版' : '已切换到经典版');
    renderRoute();
  }

  function initials(name) {
    var value = text(name, 'U');
    return esc(value.slice(0, 2).toUpperCase());
  }

  function isExternalAsset(url) {
    return /^(https?:)?\/\//i.test(url) || url.startsWith('data:') || url.startsWith('blob:');
  }

  function assetUrl(value, fallback) {
    var url = text(value, fallback || '');
    if (!url) {
      return '';
    }
    if (isExternalAsset(url)) {
      return url;
    }
    return url.replace(/\\/g, '/').replace(/^\/+/, '');
  }

  function avatarUrl(value) {
    var url = assetUrl(value, DEFAULT_AVATAR);
    if (!url || failedAvatars[url]) {
      return DEFAULT_AVATAR;
    }
    if (isExternalAsset(url)) {
      return url;
    }
    var path = url.split(/[?#]/)[0];
    if (!path || path === '.' || path.endsWith('/') || path.endsWith('.')) {
      return DEFAULT_AVATAR;
    }
    if (path !== DEFAULT_AVATAR && !imageFileRe.test(path)) {
      return DEFAULT_AVATAR;
    }
    return url;
  }

  window.csacAvatarFallback = function (img) {
    var original = img.getAttribute('data-original-src') || img.getAttribute('src') || '';
    if (original && original !== DEFAULT_AVATAR) {
      failedAvatars[original] = true;
    }
    if (img.getAttribute('src') !== DEFAULT_AVATAR) {
      img.setAttribute('src', DEFAULT_AVATAR);
      return;
    }
    img.classList.add('is-broken');
    img.removeAttribute('src');
  };

  function avatar(user, sizeClass) {
    var name = text(user && (user.display_name || user.nickname || user.username), '用户');
    var size = sizeClass || '';
    var src = avatarUrl(user && user.avatar);
    var loading = size.indexOf('avatar-sm') === -1 ? 'eager' : 'lazy';
    return '<div class="avatar ' + esc(size) + '" title="' + esc(name) + '">' +
      '<img src="' + esc(src) + '" alt="" loading="' + loading + '" decoding="async" referrerpolicy="no-referrer" data-original-src="' + esc(src) + '" onerror="window.csacAvatarFallback&&window.csacAvatarFallback(this)">' +
      '<span>' + initials(name) + '</span>' +
    '</div>';
  }

  function groupName(group) {
    return text(group && group.room_name, '群组 ' + int(group && (group.room_id || group.id)));
  }

  function roomBanInfo(room) {
    if (!room) {
      return null;
    }
    if (room.room_ban_info && room.room_ban_info.banned) {
      return room.room_ban_info;
    }
    if (int(room.ban_until) > Math.floor(Date.now() / 1000)) {
      return {
        banned: true,
        until: int(room.ban_until),
        until_text: text(room.ban_until_text, ''),
        reason: text(room.ban_reason, '违反相关规定')
      };
    }
    return null;
  }

  function roomBanBox(room) {
    var ban = roomBanInfo(room);
    if (!ban) {
      return '';
    }
    return '<div class="error-box room-ban-box">群组已封禁' +
      (ban.until_text ? '至 ' + esc(ban.until_text) : '') +
      '<br>原因：' + esc(text(ban.reason, '违反相关规定')) + '</div>';
  }

  function friendName(friend) {
    return text(friend && (friend.display_name || friend.remark || friend.nickname || friend.username), '用户 ' + int(friend && (friend.friend_id || friend.uid)));
  }

  function groupWithOwnerFallback(group, owner) {
    var next = Object.assign({}, group || {});
    var ownerUid = int(owner && owner.uid);
    if (!text(next.owner_name, '') || text(next.owner_name, '') === '未知') {
      next.owner_name = text(owner && (owner.nickname || owner.username), ownerUid ? 'UID ' + ownerUid : '未知');
    }
    if (!int(next.owner_uid) && ownerUid) {
      next.owner_uid = ownerUid;
    }
    if (ownerUid && int(next.owner_uid) === ownerUid && int(next.member_count) < 1) {
      next.member_count = 1;
    }
    return next;
  }

  function formObject(form) {
    var data = {};
    new FormData(form).forEach(function (value, key) {
      if (value instanceof File) {
        if (value.name) {
          data[key] = value;
        }
      } else {
        data[key] = String(value).trim();
      }
    });
    Array.from(form.querySelectorAll('input[type="checkbox"]')).forEach(function (box) {
      data[box.name] = box.checked ? '1' : '0';
    });
    return data;
  }

  async function apiGet(route, params, silent) {
    var data = await API.get(route, params || {});
    return handleResponse(data, silent);
  }

  async function apiPost(route, body, silent) {
    var data = body instanceof FormData
      ? await API.postFormData(route, body)
      : await API.post(route, body || {});
    return handleResponse(data, silent);
  }

  function handleResponse(data, silent) {
    if (data && data._status === 401) {
      state.user = null;
      clearPoll();
      if (!silent) {
        toast('请先登录', 'warning');
      }
      renderAuth('login');
      throw new Error('unauthorized');
    }
    if (data && data._status === 403 && data.ban_info) {
      state.user = null;
      clearPoll();
      toast('账号已封禁：' + text(data.ban_info.reason, '无原因'), 'error');
      renderAuth('login');
      throw new Error('banned');
    }
    if (data && data._status === 403 && data.room_ban_info) {
      if (!silent) {
        toast('群组已封禁：' + text(data.room_ban_info.reason, '无原因'), 'error');
      }
      throw new Error('room_banned');
    }
    if (data && data.challenge) {
      if (!silent) {
        toast(text(data.message, '服务器安全验证中，请稍后重试'), 'warning');
      }
      throw new Error('challenge');
    }
    if (!data || data.success !== true) {
      if (!silent) {
        toast(text(data && data.message, '请求失败'), 'error');
      }
      throw new Error(text(data && data.message, 'request failed'));
    }
    return data;
  }

  function isAuthError(error) {
    return error && (error.message === 'unauthorized' || error.message === 'banned' || error.message === 'room_banned' || error.message === 'challenge');
  }

  function rethrowAuth(error, fallback) {
    if (isAuthError(error)) {
      throw error;
    }
    return fallback;
  }

  async function loadSession() {
    var data = await API.get('user/get_info');
    if (data && data._status === 403 && data.ban_info) {
      handleResponse(data, true);
    }
    if (data && data.success) {
      state.user = data.user;
      await refreshShellData(true);
      return true;
    }
    state.user = null;
    return false;
  }

  async function refreshShellData(silent) {
    if (!state.user) {
      return;
    }
    var results = await Promise.all([
      API.get('user/get_groups'),
      API.get('user/get_friends'),
      API.get('user/get_notifications')
    ]);
    results.forEach(function (result) {
      if (result && (result._status === 401 || (result._status === 403 && result.ban_info))) {
        handleResponse(result, silent);
      }
    });
    if (results[0] && results[0].success) {
      state.groups = results[0].groups || [];
    } else if (!silent) {
      toast(text(results[0] && results[0].message, '群组加载失败'), 'error');
    }
    if (results[1] && results[1].success) {
      state.friends = results[1].friends || [];
    } else if (!silent) {
      toast(text(results[1] && results[1].message, '好友加载失败'), 'error');
    }
    if (results[2] && results[2].success) {
      state.notifications = results[2];
    }
  }

  function authLayout(mode) {
    var isLogin = mode !== 'register';
    return '<div class="auth-page">' +
      '<section class="auth-panel">' +
        '<div class="brand-row">' +
          '<div class="brand-mark"><img src="' + appIcon + '" alt=""></div>' +
          '<div>CsAC<br><span>UniCsAC 在线聊天</span></div>' +
        '</div>' +
        '<div style="height:28px"></div>' +
        '<h1>' + (isLogin ? '登录' : '注册') + '</h1>' +
        '<p class="muted">' + (isLogin ? '使用 CsAC 账号进入聊天。' : '创建账号后会自动登录。') + '</p>' +
        '<div style="height:18px"></div>' +
        (isLogin ? loginForm() : registerForm()) +
        '<div style="height:12px"></div>' +
        '<button class="button ghost" type="button" data-action="theme-toggle">切换主题</button>' +
        '<button class="button ghost mobile-style-button" type="button" data-action="mobile-layout-toggle">' + mobileLayoutLabel() + '</button>' +
      '</section>' +
      '<section class="auth-side">' +
        '<div class="auth-side-inner">' +
          '<h1>统一前端，统一 API。</h1>' +
          '<p>当前客户端仅调用 /rpc/UniCsAC.php，旧散入口已经从前端完全移除。</p>' +
        '</div>' +
      '</section>' +
    '</div>';
  }

  function loginForm() {
    return '<form data-form="login" class="stack">' +
      '<div class="field"><label>账号</label><input class="input" name="username" autocomplete="username" required></div>' +
      '<div class="field"><label>密码</label><input class="input" type="password" name="pwd" autocomplete="current-password" required></div>' +
      '<button class="button primary" type="submit">登录</button>' +
      '<button class="button ghost" type="button" data-action="route" data-route="register">创建账号</button>' +
    '</form>';
  }

  function registerForm() {
    return '<form data-form="register" class="stack">' +
      '<div class="field"><label>账号</label><input class="input" name="username" autocomplete="username" required minlength="3" maxlength="32"></div>' +
      '<div class="field"><label>昵称</label><input class="input" name="nickname" required maxlength="16"></div>' +
      '<div class="field"><label>密码</label><input class="input" type="password" name="pwd" autocomplete="new-password" required minlength="6"></div>' +
      '<div class="field"><label>确认密码</label><input class="input" type="password" name="confirm_pwd" autocomplete="new-password" required minlength="6"></div>' +
      '<div class="field"><label>头像</label><input class="input" type="file" name="avatar" accept="image/*"></div>' +
      '<button class="button primary" type="submit">注册并进入</button>' +
      '<button class="button ghost" type="button" data-action="route" data-route="login">已有账号</button>' +
    '</form>';
  }

  function renderAuth(mode) {
    clearPoll();
    state.active = { type: '', id: 0 };
    app.className = '';
    app.innerHTML = authLayout(mode);
  }

  function navHtml(mobile) {
    var current = currentName();
    return navItems.map(function (item) {
      var active = current === item[0] || (item[0] === 'groups' && current === 'group') || (item[0] === 'friends' && current === 'private');
      var badge = item[0] === 'notices' && int(state.notifications.total_unread)
        ? '<span class="badge danger">' + int(state.notifications.total_unread) + '</span>'
        : '';
      var label = esc(item[1]);
      return '<a class="nav-button ' + (active ? 'is-active' : '') + '" href="' + item[2] + '">' + label + badge + '</a>';
    }).join('') + (uid() === 1 && !mobile ? '<a class="nav-button ' + (current === 'admin' ? 'is-active' : '') + '" href="#/admin">封禁管理</a>' : '') +
      (!mobile ? '<a class="nav-button ' + (current === 'bug' ? 'is-active' : '') + '" href="#/bug">反馈</a>' : '');
  }

  function mobileRouteTitle() {
    var name = currentName();
    if (name === 'dashboard') {
      return text(state.user && (state.user.nickname || state.user.username), '用户');
    }
    var titles = {
      groups: '群组',
      essence: '精华',
      friends: '好友',
      notices: '通知',
      profile: '个人资料',
      user: '用户资料',
      report: '举报',
      bug: '反馈',
      admin: '封禁管理'
    };
    return titles[name] || 'CsAC';
  }

  function mobileRouteSubTitle() {
    var name = currentName();
    if (name === 'dashboard') {
      return state.groups.length + ' 个群组 · ' + state.friends.length + ' 位好友';
    }
    if (name === 'groups') {
      return '查找、加入和创建群组';
    }
    if (name === 'friends') {
      return '好友请求和私聊入口';
    }
    if (name === 'notices') {
      return int(state.notifications.total_unread) ? int(state.notifications.total_unread) + ' 条未读通知' : '没有未读通知';
    }
    return 'UniCsAC 在线聊天';
  }

  function mobileSearchForms() {
    return '<div class="mobile-search-modal">' +
      '<form data-form="go-group" class="mobile-search-form">' +
        '<label>群组 ID</label>' +
        '<div><input class="input" name="room_id" inputmode="numeric" placeholder="输入群组 ID" required><button class="button primary" type="submit">打开</button></div>' +
      '</form>' +
      '<form data-form="go-user" class="mobile-search-form">' +
        '<label>用户 UID</label>' +
        '<div><input class="input" name="uid" inputmode="numeric" placeholder="输入用户 UID" required><button class="button primary" type="submit">查看</button></div>' +
      '</form>' +
    '</div>';
  }

  function openMobileSearch() {
    openModal('搜索', mobileSearchForms());
    window.requestAnimationFrame(function () {
      var input = modalRoot.querySelector('.mobile-search-form .input');
      if (input) {
        input.focus();
      }
    });
  }

  function mobileShell(main, layoutClass) {
    var user = state.user || {};
    app.className = '';
    app.innerHTML =
      '<div class="mobile-shell ' + esc(layoutClass || '') + '">' +
        '<header class="mobile-appbar">' +
          '<button class="mobile-avatar-button" type="button" data-action="route" data-route="profile" aria-label="个人资料">' + avatar(user, 'avatar-sm') + '</button>' +
          '<div class="mobile-app-title"><strong>' + esc(mobileRouteTitle()) + '</strong><span>' + esc(mobileRouteSubTitle()) + '</span></div>' +
          '<button class="mobile-round-button" type="button" data-action="open-mobile-search" aria-label="搜索">搜</button>' +
          '<button class="mobile-mode-button" type="button" data-action="mobile-layout-toggle">' + mobileLayoutLabel() + '</button>' +
        '</header>' +
        '<main class="mobile-content">' + main + '</main>' +
        '<nav class="mobile-nav">' + navHtml(true) + '</nav>' +
      '</div>';
  }

  function loadMoreLabel(stateKey, busy) {
    return busy ? '加载中…' : '加载更多';
  }

  function shell(main, layoutClass) {
    if (isMobileTelegram() && layoutClass !== 'is-chat-view') {
      mobileShell(main, layoutClass);
      return;
    }
    var user = state.user || {};
    var conversations = conversationHtml();
    app.className = '';
    app.innerHTML =
      '<div class="app-layout ' + esc(layoutClass || '') + '">' +
        '<aside class="sidebar">' +
          '<div class="brand-row"><div class="brand-mark"><img src="' + appIcon + '" alt=""></div><div>CsAC<br><span>UniCsAC</span></div><div class="brand-actions"><button class="button ghost mobile-style-button" type="button" data-action="mobile-layout-toggle">' + mobileLayoutLabel() + '</button></div></div>' +
          '<div class="user-card">' + avatar(user) +
            '<div class="item-text"><strong>' + esc(text(user.nickname, '未命名用户')) + '</strong><span class="muted small">UID ' + uid() + '</span></div>' +
          '</div>' +
          '<nav class="nav-list">' + navHtml(false) + '</nav>' +
          '<div class="quick-search">' +
            '<form data-form="go-group"><input class="input" name="room_id" inputmode="numeric" placeholder="群组 ID"><button class="button secondary" type="submit">打开</button></form>' +
            '<form data-form="go-user"><input class="input" name="uid" inputmode="numeric" placeholder="用户 UID"><button class="button secondary" type="submit">查看</button></form>' +
          '</div>' +
          '<div class="conversation-section">' + conversations + '</div>' +
          '<div class="inline-actions">' +
            '<button class="button ghost" type="button" data-action="mobile-layout-toggle">' + mobileLayoutLabel() + '</button>' +
            '<button class="button ghost" type="button" data-action="theme-toggle">主题</button>' +
            '<button class="button danger" type="button" data-action="logout">退出</button>' +
          '</div>' +
        '</aside>' +
        '<main class="content">' + main + '</main>' +
        '<nav class="mobile-nav">' + navHtml(true) + '</nav>' +
      '</div>';
  }

  function conversationHtml() {
    var groupItems = state.groups.slice(0, 8).map(function (group) {
      var roomId = int(group.room_id || group.id);
      return '<a class="list-item" href="#/group/' + roomId + '">' +
        '<div class="item-main"><div class="avatar avatar-sm">#</div><div class="item-text"><strong>' + esc(groupName(group)) + '</strong><span class="muted small">' + int(group.member_count) + ' 人</span></div></div>' +
        (int(group.unread_count) ? '<span class="badge danger">' + int(group.unread_count) + '</span>' : '') +
      '</a>';
    }).join('');
    var friendItems = state.friends.slice(0, 8).map(function (friend) {
      var fid = int(friend.friend_id);
      return '<a class="list-item" href="#/private/' + fid + '">' +
        '<div class="item-main">' + avatar(friend, 'avatar-sm') + '<div class="item-text"><strong>' + esc(friendName(friend)) + '</strong><span class="muted small">' + esc(plain(friend.online_status)) + '</span></div></div>' +
        (int(friend.unread_count) ? '<span class="badge danger">' + int(friend.unread_count) + '</span>' : '') +
      '</a>';
    }).join('');
    return '<div class="section-head"><h3>最近会话</h3></div>' +
      '<div class="stack">' + (groupItems || friendItems ? groupItems + friendItems : '<div class="empty">暂无会话</div>') + '</div>';
  }

  function pageTitle(title, desc, actions) {
    return '<div class="page-title ' + (actions ? 'has-actions' : '') + '"><div><h1>' + esc(title) + '</h1>' + (desc ? '<p>' + esc(desc) + '</p>' : '') + '</div>' +
      (actions ? '<div class="inline-actions">' + actions + '</div>' : '') +
    '</div>';
  }

  function groupCard(group, publicList) {
    var roomId = int(group.room_id || group.id);
    var joinType = ['未知', '自由加入', '邀请码', '固定口令', '审核加入'][int(group.join_type)] || '未知';
    var hasPublicFlag = group && Object.prototype.hasOwnProperty.call(group, 'show_in_list');
    var meta = [
      '群主：' + text(group && group.owner_name, '未知'),
      int(group && group.member_count) + ' 人',
      joinType
    ];
    var badges = '<span class="badge">#' + roomId + '</span>' +
      (hasPublicFlag ? '<span class="badge ' + (int(group.show_in_list) ? '' : 'warning') + '">' + (int(group.show_in_list) ? '公开' : '私密') + '</span>' : '');
    var notice = text(group && group.notice, '');
    return '<div class="card group-card" data-action="route" data-route="group/' + roomId + '" role="button" tabindex="0">' +
      '<div class="section-head"><h3 class="truncate">' + esc(groupName(group)) + '</h3><div class="inline-actions group-card-badges">' + badges + (roomBanInfo(group) ? '<span class="badge danger">封禁</span>' : '') + '</div></div>' +
      '<p class="muted group-intro">' + esc(text(group && group.intro, '暂无简介')) + '</p>' +
      (roomBanInfo(group) ? '<div class="reply-chip danger">已封禁：' + esc(text(roomBanInfo(group).reason, '违反相关规定')) + '</div>' : '') +
      (notice ? '<div class="reply-chip group-notice">' + br(notice) + '</div>' : '') +
      '<div class="muted small group-meta">' + esc(meta.join(' · ')) + '</div>' +
      '<div class="inline-actions group-actions">' +
        '<button class="button primary" type="button" data-action="route" data-route="group/' + roomId + '">' + (publicList ? '查看/加入' : '进入聊天') + '</button>' +
        '<button class="button ghost" type="button" data-action="report-group" data-room-id="' + roomId + '" data-room-name="' + esc(groupName(group)) + '">举报</button>' +
      '</div>' +
    '</div>';
  }

  function friendCard(friend) {
    var fid = int(friend.friend_id);
    return '<div class="list-item friend-row" data-action="route" data-route="private/' + fid + '" role="button" tabindex="0">' +
      '<div class="item-main">' + avatar(friend) +
        '<div class="item-text"><strong>' + esc(friendName(friend)) + '</strong><span class="muted small">@' + esc(text(friend.username, '')) + ' · UID ' + fid + '</span></div>' +
      '</div>' +
      '<div class="inline-actions">' +
        (int(friend.unread_count) ? '<span class="badge danger">' + int(friend.unread_count) + '</span>' : '') +
        '<button class="button primary" type="button" data-action="route" data-route="private/' + fid + '">私聊</button>' +
        '<button class="button ghost" type="button" data-action="route" data-route="user/' + fid + '">资料</button>' +
      '</div>' +
    '</div>';
  }

  async function renderDashboard() {
    await refreshShellData(true);
    if (isMobileTelegram()) {
      renderMobileDashboard();
      return;
    }
    var main = pageTitle('工作台', '集中管理聊天、群组、通知和个人资料。', '<button class="button primary" data-action="route" data-route="groups">浏览群组</button>') +
      '<section class="grid">' +
        '<div class="panel metric"><span class="muted">我的群组</span><strong>' + state.groups.length + '</strong><a href="#/groups">查看群组</a></div>' +
        '<div class="panel metric"><span class="muted">好友</span><strong>' + state.friends.length + '</strong><a href="#/friends">好友管理</a></div>' +
        '<div class="panel metric"><span class="muted">未读通知</span><strong>' + int(state.notifications.total_unread) + '</strong><a href="#/notices">处理通知</a></div>' +
      '</section>' +
      '<section class="two-col" style="margin-top:14px">' +
        '<div class="panel">' +
          '<div class="section-head"><h2>群组</h2><button class="button secondary" data-action="open-create-group">创建群组</button></div>' +
          '<div class="stack">' + (state.groups.length ? state.groups.map(function (g) { return groupCard(g, false); }).join('') : '<div class="empty">还没有加入群组</div>') + '</div>' +
        '</div>' +
        '<div class="panel">' +
          '<div class="section-head"><h2>好友</h2><button class="button secondary" data-action="open-add-friend">添加好友</button></div>' +
          '<div class="stack">' + (state.friends.length ? state.friends.slice(0, 8).map(friendCard).join('') : '<div class="empty">还没有好友</div>') + '</div>' +
        '</div>' +
      '</section>';
    shell(main);
  }

  function mobileConversationRows() {
    var rows = [];
    state.groups.forEach(function (group) {
      var roomId = int(group.room_id || group.id);
      rows.push({
        type: 'group',
        route: 'group/' + roomId,
        title: groupName(group),
        subtitle: roomBanInfo(group) ? '群组已封禁 · ' + text(roomBanInfo(group).reason, '违反相关规定') : int(group.member_count) + ' 人 · ' + text(group.intro, '暂无简介'),
        badge: int(group.unread_count),
        meta: roomId ? '#' + roomId : '',
        danger: !!roomBanInfo(group),
        initial: '#'
      });
    });
    state.friends.forEach(function (friend) {
      var fid = int(friend.friend_id);
      rows.push({
        type: 'friend',
        route: 'private/' + fid,
        title: friendName(friend),
        subtitle: plain(friend.online_status) || ('UID ' + fid),
        badge: int(friend.unread_count),
        meta: 'UID ' + fid,
        avatar: friend.avatar,
        nickname: friendName(friend)
      });
    });
    rows.sort(function (a, b) {
      return int(b.badge) - int(a.badge);
    });
    return rows;
  }

  function mobileRow(item) {
    var badge = item.badge ? '<span class="mobile-unread">' + (item.badge > 99 ? '99+' : item.badge) + '</span>' : '';
    var meta = item.meta ? '<span class="mobile-row-time">' + esc(item.meta) + '</span>' : '';
    var visual = item.type === 'friend'
      ? avatar({ nickname: item.nickname, avatar: item.avatar }, 'avatar-sm')
      : '<div class="mobile-row-icon">' + esc(item.initial || '#') + '</div>';
    return '<div class="mobile-conversation-row ' + (item.danger ? 'is-danger' : '') + '" data-action="route" data-route="' + esc(item.route) + '" role="button" tabindex="0">' +
      visual +
      '<div class="mobile-row-main"><div class="mobile-row-title">' + esc(item.title) + '</div><div class="mobile-row-subtitle">' + esc(item.subtitle) + '</div></div>' +
      '<div class="mobile-row-meta">' + meta + badge + '<span class="mobile-chevron">›</span></div>' +
    '</div>';
  }

  function renderMobileDashboard() {
    var rows = mobileConversationRows();
    var notices = int(state.notifications.total_unread);
    var main =
      '<section class="mobile-home">' +
        '<button class="mobile-search-bar" type="button" data-action="open-mobile-search">UID / 群组 ID</button>' +
        '<div class="mobile-section-label">会话</div>' +
        '<div class="mobile-list">' +
          (notices ? '<div class="mobile-conversation-row" data-action="route" data-route="notices"><div class="mobile-row-icon notice">!</div><div class="mobile-row-main"><div class="mobile-row-title">通知</div><div class="mobile-row-subtitle">有 ' + notices + ' 条通知待处理</div></div><div class="mobile-row-meta"><span class="mobile-row-time">未读</span><span class="mobile-unread">' + (notices > 99 ? '99+' : notices) + '</span><span class="mobile-chevron">›</span></div></div>' : '') +
          (rows.length ? rows.map(mobileRow).join('') : '<div class="empty">暂无会话</div>') +
        '</div>' +
      '</section>';
    shell(main, 'mobile-home-view');
  }

  async function renderGroups() {
    await refreshShellData(true);
    var publicData = await apiGet('group/get_public_list', {}, true).catch(function (error) { return rethrowAuth(error, { groups: [] }); });
    var publicGroups = publicData.groups || [];
    var main = pageTitle('群组', '创建、加入和管理公开群组。', '<button class="button primary" data-action="open-create-group">创建群组</button>') +
      '<section class="panel">' +
        '<div class="section-head"><h2>我的群组</h2></div>' +
        '<div class="grid">' + (state.groups.length ? state.groups.map(function (g) { return groupCard(g, false); }).join('') : '<div class="empty">还没有加入群组</div>') + '</div>' +
      '</section>' +
      '<section class="panel">' +
        '<div class="section-head"><h2>公开群组</h2><button class="button ghost" data-action="refresh">刷新</button></div>' +
        '<div class="grid">' + (publicGroups.length ? publicGroups.map(function (g) { return groupCard(g, true); }).join('') : '<div class="empty">没有公开群组</div>') + '</div>' +
      '</section>';
    shell(main);
  }

  function essenceRoomPicker() {
    return '<section class="panel">' +
      '<div class="section-head"><h2>选择群组</h2><span class="badge">' + state.groups.length + '</span></div>' +
      '<div class="grid">' + (state.groups.length ? state.groups.map(function (g) {
        var roomId = int(g.room_id || g.id);
        return '<div class="card group-card" data-action="route" data-route="essence/' + roomId + '" role="button" tabindex="0">' +
          '<div class="section-head"><h3 class="truncate">' + esc(groupName(g)) + '</h3>' + (roomBanInfo(g) ? '<span class="badge danger">封禁</span>' : '<span class="badge">#' + roomId + '</span>') + '</div>' +
          '<p class="muted group-intro">' + esc(text(g.intro, '暂无简介')) + '</p>' +
          '<div class="inline-actions group-actions"><button class="button primary" data-action="route" data-route="essence/' + roomId + '"' + (roomBanInfo(g) ? ' disabled' : '') + '>查看精华</button></div>' +
        '</div>';
      }).join('') : '<div class="empty">加入群组后可查看精华</div>') + '</div>' +
    '</section>';
  }

  async function renderEssenceRoute(roomId, query) {
    await refreshShellData(true);
    if (!roomId) {
      shell(pageTitle('精华', '自动统计各群精华内容。') + essenceRoomPicker());
      return;
    }
    state.active = { type: 'essence', id: roomId };
    var type = query && query.get('type') || 'week';
    var view = await apiGet('group/get_group_view_info', { room_id: roomId });
    state.roomMeta = view;
    if (roomBanInfo(view.room)) {
      renderBannedGroup(view);
      return;
    }
    if (!view.is_in_group) {
      renderGroupJoin(view);
      return;
    }
    var data = await apiGet('essence/get_essence', { room_id: roomId });
    var stats = await apiGet('essence/get_essence_stats', { room_id: roomId, type: type });
    state.essence = data.essence_list || [];
    state.essenceStats = stats;
    var tabs = [
      ['today', '今天'],
      ['week', '近7天'],
      ['month', '近一月'],
      ['all', '全部']
    ].map(function (tab) {
      return '<button class="tab-button ' + (type === tab[0] ? 'is-active' : '') + '" data-action="route" data-route="essence/' + roomId + '?type=' + tab[0] + '">' + tab[1] + '</button>';
    }).join('');
    var main = pageTitle('精华 · ' + groupName(view.room), '自动统计群内精华消息。', '<button class="button secondary" data-action="route" data-route="group/' + roomId + '">返回聊天</button>') +
      '<section class="panel">' +
        '<div class="section-head"><h2>统计</h2><div class="inline-actions">' + tabs + '</div></div>' +
        essenceStatsHtml(stats) +
      '</section>' +
      '<section class="panel">' +
        '<div class="section-head"><h2>精华消息</h2><span class="badge">' + state.essence.length + '</span></div>' +
        '<div class="stack essence-list">' + (state.essence.length ? state.essence.map(essenceRow).join('') : '<div class="empty">暂无精华消息</div>') + '</div>' +
      '</section>';
    shell(main);
  }

  function essenceStatsHtml(stats) {
    stats = stats || {};
    var rank = stats.rank || [];
    return '<div class="grid essence-stats">' +
      '<div class="panel metric soft"><span class="muted">' + esc(text(stats.type_name, '当前周期')) + '</span><strong>' + int(stats.total) + '</strong><span class="small muted">精华总数</span></div>' +
      '<div class="panel metric soft"><span class="muted">文本</span><strong>' + int(stats.text_count) + '</strong><span class="small muted">文字消息</span></div>' +
      '<div class="panel metric soft"><span class="muted">图片</span><strong>' + int(stats.image_count) + '</strong><span class="small muted">图片消息</span></div>' +
      '<div class="panel metric soft"><span class="muted">语音</span><strong>' + int(stats.voice_count) + '</strong><span class="small muted">语音消息</span></div>' +
    '</div>' +
    '<div class="rank-list">' + (rank.length ? rank.map(function (row) {
      return '<div class="list-item compact"><div class="item-main"><span class="badge">#' + int(row.rank) + '</span><div class="item-text"><strong>' + esc(text(row.nickname, '成员')) + '</strong><span class="muted small">UID ' + int(row.uid) + '</span></div></div><span class="badge warning">' + int(row.count) + '</span></div>';
    }).join('') : '<div class="empty">当前周期暂无贡献排行</div>') + '</div>' +
    (stats.latest_set_time ? '<p class="muted small">最近设置：' + esc(stats.latest_set_time) + '</p>' : '');
  }

  function essenceRow(item) {
    return '<article class="list-item essence-item">' +
      '<div class="item-main">' + avatar(item, 'avatar-sm') +
        '<div class="item-text">' +
          '<strong>' + esc(text(item.nickname, '成员')) + '</strong>' +
          '<span class="muted small">由 ' + esc(text(item.set_nick, '管理员')) + ' 设置 · ' + esc(text(item.set_time, '')) + '</span>' +
          '<div class="message-bubble essence-bubble">' + messageContent(item) + '</div>' +
        '</div>' +
      '</div>' +
    '</article>';
  }

  async function renderGroupRoute(roomId) {
    state.active = { type: 'group', id: roomId };
    state.reply = state.reply && state.reply.type === 'group' && state.reply.roomId === roomId ? state.reply : null;
    var view = await apiGet('group/get_group_view_info', { room_id: roomId });
    state.roomMeta = view;
    if (roomBanInfo(view.room)) {
      renderBannedGroup(view);
      return;
    }
    if (!view.is_in_group) {
      renderGroupJoin(view);
      return;
    }
    await loadGroupChat(roomId);
    renderGroupChat();
    startGroupPoll(roomId);
  }

  function renderGroupJoin(view) {
    var room = view.room || {};
    var roomId = int(room.room_id || room.id);
    var ban = roomBanInfo(room);
    var joinType = int(room.join_type);
    var extra = '';
    if (joinType === 2 || joinType === 3) {
      extra = '<div class="field"><label>' + (joinType === 2 ? '邀请码' : '固定口令') + '</label><input class="input" name="code" required></div>';
    }
    if (joinType === 4) {
      extra = '<div class="field"><label>' + esc(text(room.ask_question, '申请说明')) + '</label><textarea class="textarea" name="answer" required></textarea></div>';
    }
    var main = pageTitle(groupName(room), '群组资料和加入申请。') +
      '<section class="two-col">' +
        '<div class="panel">' +
          '<h2>群组资料</h2>' +
          '<p>' + br(text(room.intro, '暂无简介')) + '</p>' +
          '<p class="muted">群主：' + esc(text(room.owner_name, '未知')) + ' · 群组 ID：' + roomId + '</p>' +
          (room.notice ? '<div class="reply-chip">' + br(room.notice) + '</div>' : '') +
        '</div>' +
        '<div class="panel">' +
          '<h2>加入群组</h2>' +
          (ban ? roomBanBox(room) : view.has_apply ? '<div class="empty">申请已提交，等待管理员审核</div>' :
            '<form class="stack" data-form="join-group">' +
              '<input type="hidden" name="room_id" value="' + roomId + '">' + extra +
              '<button class="button primary" type="submit">提交</button>' +
            '</form>') +
        '</div>' +
      '</section>';
    shell(main);
  }

  function renderBannedGroup(view) {
    var room = view.room || {};
    var roomId = int(room.room_id || room.id);
    var actions = '<button class="button secondary" data-action="route" data-route="groups">返回群组</button>' +
      (view.is_in_group ? '<button class="button warning" data-action="leave-group" data-room-id="' + roomId + '">退出群组</button>' : '') +
      '<button class="button ghost" data-action="report-group" data-room-id="' + roomId + '" data-room-name="' + esc(groupName(room)) + '">举报</button>';
    var main = pageTitle(groupName(room), '该群组当前不可聊天。', actions) +
      '<section class="two-col">' +
        '<div class="panel">' +
          roomBanBox(room) +
          '<h2>群组资料</h2>' +
          '<p>' + br(text(room.intro, '暂无简介')) + '</p>' +
          '<p class="muted">群主：' + esc(text(room.owner_name, '未知')) + ' · 群组 ID：' + roomId + '</p>' +
          (room.notice ? '<div class="reply-chip">' + br(room.notice) + '</div>' : '') +
        '</div>' +
        '<div class="panel">' +
          '<h2>使用状态</h2>' +
          '<div class="empty">群组封禁期间，成员无法发送消息、查看聊天记录、管理成员或设置精华。</div>' +
        '</div>' +
      '</section>';
    shell(main);
  }

  async function loadGroupChat(roomId) {
    var tasks = [
      apiGet('message/get_group_msg', { room_id: roomId, limit: 80 }, true),
      apiGet('group/get_members', { room_id: roomId }, true),
      apiGet('essence/get_essence', { room_id: roomId }, true).catch(function (error) { return rethrowAuth(error, { essence_list: [], can_remove: false }); })
    ];
    if (state.roomMeta && state.roomMeta.is_admin) {
      tasks.push(apiGet('group/get_applications', { room_id: roomId }, true).catch(function (error) { return rethrowAuth(error, { applications: [] }); }));
    }
    var data = await Promise.all(tasks);
    state.roomMessages = data[0].messages || [];
    state.roomHasMore = !!data[0].has_more;
    state.roomOldestId = state.roomMessages.length ? int(state.roomMessages[0].id) : 0;
    state.roomLatestId = state.roomMessages.length ? int(state.roomMessages[state.roomMessages.length - 1].id) : 0;
    state.roomMembers = data[1].members || [];
    state.essence = data[2].essence_list || [];
    state.applications = data[3] ? (data[3].applications || data[3].requests || []) : [];
  }

  function renderGroupChat() {
    var view = state.roomMeta || {};
    var room = view.room || {};
    var roomId = int(room.room_id || room.id);
    var main =
      '<section class="chat-route">' +
        '<div class="chat-panel">' +
          '<header class="chat-header">' +
            '<button class="icon-button chat-back" type="button" data-action="chat-back" aria-label="返回">‹</button>' +
            '<div class="chat-title chat-title-main">' +
              '<h1>' + esc(groupName(room)) + '</h1><div class="muted small">#' + roomId + ' · ' + state.roomMembers.length + ' 人</div>' +
            '</div>' +
            '<div class="inline-actions chat-tools">' +
              '<button class="button secondary" data-action="open-group-details">资料</button>' +
              '<button class="button ghost" data-action="route" data-route="essence/' + roomId + '">精华</button>' +
              '<button class="button ghost mark-read" data-action="mark-group-read" data-room-id="' + roomId + '">已读</button>' +
            '</div>' +
          '</header>' +
          '<div class="message-list" id="message-list" data-chat-type="group" data-room-id="' + roomId + '">' + messagesHtml(state.roomMessages, 'group') + '</div>' +
          composerHtml('group', roomId) +
        '</div>' +
      '</section>';
    shell(main, 'is-chat-view');
    updateChatUnreadState('group', roomId);
    scrollMessages();
  }

  function groupSideHtml(view) {
    var room = view.room || {};
    var roomId = int(room.room_id || room.id);
    var invite = view.can_view_invite ? '<div class="reply-chip">邀请码：' + esc(text(room.invite_code, '无')) + '</div>' : '';
    return '<div class="panel">' +
      '<div class="section-head"><h2>群资料</h2><span class="badge">' + (view.is_owner ? '群主' : view.is_admin ? '管理' : '成员') + '</span></div>' +
      '<p>' + br(text(room.intro, '暂无简介')) + '</p>' + invite +
      (room.notice ? '<div class="reply-chip">' + br(room.notice) + '</div>' : '') +
      '<div class="inline-actions">' +
        '<button class="button ghost" data-action="route" data-route="essence/' + roomId + '">精华</button>' +
        '<button class="button warning" data-action="leave-group" data-room-id="' + roomId + '">退群</button>' +
        '<button class="button ghost" data-action="report-group" data-room-id="' + roomId + '" data-room-name="' + esc(groupName(room)) + '">举报</button>' +
      '</div>' +
    '</div>' +
    '<div class="panel">' +
      '<div class="section-head"><h2>成员</h2><span class="badge">' + state.roomMembers.length + '</span></div>' +
      '<div class="stack">' + (state.roomMembers.length ? state.roomMembers.map(memberRow).join('') : '<div class="empty">暂无成员</div>') + '</div>' +
    '</div>' +
    (view.is_admin ? groupAdminHtml(room, view) : '');
  }

  function memberRow(member) {
    var roomId = int(state.roomMeta && state.roomMeta.room && state.roomMeta.room.room_id);
    var target = int(member.uid);
    var canAdmin = state.roomMeta && state.roomMeta.is_admin && target !== uid();
    var role = member.is_owner ? '群主' : member.is_admin ? '管理员' : '成员';
    return '<div class="list-item">' +
      '<div class="item-main">' + avatar(member, 'avatar-sm') +
        '<div class="item-text"><strong>' + esc(text(member.nickname, '成员')) + '</strong><span class="muted small">UID ' + target + ' · ' + role + (member.is_muted ? ' · 已禁言' : '') + '</span></div>' +
      '</div>' +
      '<div class="inline-actions">' +
        '<button class="button ghost" data-action="route" data-route="user/' + target + '">资料</button>' +
        (canAdmin ? '<button class="button warning" data-action="open-mute" data-room-id="' + roomId + '" data-uid="' + target + '">禁言</button>' : '') +
        (canAdmin && !member.is_owner ? '<button class="button danger" data-action="kick-member" data-room-id="' + roomId + '" data-uid="' + target + '">踢出</button>' : '') +
        (state.roomMeta && state.roomMeta.is_owner && !member.is_owner ? '<button class="button ghost" data-action="toggle-admin" data-room-id="' + roomId + '" data-uid="' + target + '" data-admin="' + (member.is_admin ? '1' : '0') + '">' + (member.is_admin ? '撤管' : '设管') + '</button>' : '') +
      '</div>' +
    '</div>';
  }

  function openNoticeRoute(notice) {
    var route = text(notice && notice.route, '') || text(notice && notice.link, '');
    if (!route) {
      return;
    }
    if (route.indexOf('#/') !== 0) {
      var match = route.match(/\/#\/(.+)$/);
      route = match ? '#/' + match[1] : route;
    }
    if (route.indexOf('#/') === 0) {
      var next = route.slice(2);
      if (next) {
        setHash(next);
      }
    }
  }

  function groupAdminHtml(room, view) {
    var roomId = int(room.room_id || room.id);
    return '<div class="panel">' +
      '<div class="section-head"><h2>群管理</h2><span class="badge warning">管理</span></div>' +
      '<form data-form="edit-group-info" class="stack">' +
        '<input type="hidden" name="room_id" value="' + roomId + '">' +
        '<div class="field"><label>群名</label><input class="input" name="room_name" value="' + esc(room.room_name) + '" required></div>' +
        '<div class="field"><label>简介</label><textarea class="textarea" name="intro">' + esc(room.intro) + '</textarea></div>' +
        '<div class="field"><label>公告</label><textarea class="textarea" name="notice">' + esc(room.notice) + '</textarea></div>' +
        '<button class="button primary" type="submit">保存资料</button>' +
      '</form>' +
      '<form data-form="group-settings" class="stack" style="margin-top:12px">' +
        '<input type="hidden" name="room_id" value="' + roomId + '">' +
        '<div class="field"><label>加入方式</label><select class="select" name="join_type">' +
          optionHtml(1, '自由加入', room.join_type) + optionHtml(2, '一次性邀请码', room.join_type) + optionHtml(3, '固定口令', room.join_type) + optionHtml(4, '审核加入', room.join_type) +
        '</select></div>' +
        '<div class="field"><label>固定口令</label><input class="input" name="fixed_code" value="' + esc(room.fixed_code) + '"></div>' +
        '<div class="field"><label>审核问题</label><input class="input" name="question" value="' + esc(room.ask_question) + '"></div>' +
        '<div class="field"><label>审核答案</label><input class="input" name="answer"></div>' +
        '<label><input type="checkbox" name="show_in_list" ' + (int(room.show_in_list) ? 'checked' : '') + '> 公开展示</label>' +
        '<label><input type="checkbox" name="allow_invite" ' + (int(room.allow_invite) ? 'checked' : '') + '> 成员可见邀请码</label>' +
        '<button class="button primary" type="submit">保存设置</button>' +
      '</form>' +
      '<div class="inline-actions" style="margin-top:12px">' +
        '<button class="button ghost" data-action="reset-invite" data-room-id="' + roomId + '">重置邀请码</button>' +
        (view.is_owner ? '<button class="button danger" data-action="disband-group" data-room-id="' + roomId + '">解散群组</button>' : '') +
      '</div>' +
      (view.is_owner ? '<form data-form="group-transfer" class="stack" style="margin-top:12px">' +
        '<input type="hidden" name="room_id" value="' + roomId + '">' +
        '<div class="field"><label>转让给成员 UID</label><input class="input" name="target_uid" inputmode="numeric" required></div>' +
        '<button class="button warning" type="submit">发送转让申请</button>' +
      '</form>' : '') +
    '</div>' +
    '<div class="panel">' +
      '<div class="section-head"><h2>入群申请</h2><span class="badge">' + state.applications.length + '</span></div>' +
      '<div class="stack">' + (state.applications.length ? state.applications.map(function (app) {
        return '<div class="list-item">' +
          '<div class="item-main">' + avatar(app, 'avatar-sm') + '<div class="item-text"><strong>' + esc(app.nickname) + '</strong><span class="muted small">UID ' + int(app.uid) + ' · ' + esc(app.apply_time) + '</span><span class="small">' + esc(app.answer_content) + '</span></div></div>' +
          '<div class="inline-actions"><button class="button primary" data-action="handle-apply" data-id="' + int(app.id) + '" data-result="pass">通过</button><button class="button danger" data-action="handle-apply" data-id="' + int(app.id) + '" data-result="refuse">拒绝</button></div>' +
        '</div>';
      }).join('') : '<div class="empty">暂无申请</div>') + '</div>' +
    '</div>';
  }

  function optionHtml(value, label, current) {
    return '<option value="' + value + '" ' + (int(current) === value ? 'selected' : '') + '>' + esc(label) + '</option>';
  }

  function messagesHtml(messages, type) {
    var hasMore = type === 'group' ? state.roomHasMore : state.privateHasMore;
    var loadMore = hasMore ? '<button class="message-load-more" type="button" data-action="load-more-messages" data-type="' + type + '">加载更早消息</button>' : '';
    if (!messages || messages.length === 0) {
      return loadMore + '<div class="empty">暂无消息</div>';
    }
    return loadMore + messages.map(function (message) {
      var mine = type === 'group' ? int(message.uid) === uid() : int(message.from_uid) === uid();
      var sender = text(message.nickname, mine ? '我' : '用户');
      var time = text(message.add_time || (message.created_at ? new Date(int(message.created_at) * 1000).toLocaleString() : ''), '');
      var roomId = int(state.active.id);
      var msgId = int(message.id);
      var canRecall = type === 'group' ? message.can_recall : mine;
      var canEssence = type === 'group' && state.roomMeta && state.roomMeta.is_admin;
      return '<article class="message ' + (mine ? 'is-mine' : '') + '">' +
        avatar({ nickname: sender, avatar: message.avatar }, 'avatar-sm') +
        '<div class="message-body">' +
          '<div class="message-head"><strong>' + esc(sender) + '</strong><span>' + esc(time) + '</span>' + (message.is_essence ? '<span class="badge warning">精华</span>' : '') + '</div>' +
          '<div class="message-bubble">' + messageContent(message) + '</div>' +
          '<div class="message-actions">' +
            '<button class="message-action" data-action="reply-message" data-type="' + type + '" data-id="' + msgId + '" data-room-id="' + roomId + '" data-label="' + esc(sender) + '">回复</button>' +
            (canRecall ? '<button class="message-action" data-action="recall-message" data-type="' + type + '" data-id="' + msgId + '" data-room-id="' + roomId + '">撤回</button>' : '') +
            (canEssence ? '<button class="message-action" data-action="toggle-essence" data-id="' + msgId + '" data-room-id="' + roomId + '">' + (message.is_essence ? '取消精华' : '设精华') + '</button>' : '') +
          '</div>' +
        '</div>' +
      '</article>';
    }).join('');
  }

  function renderMessageList(listEl, messages, type, prepend) {
    if (!listEl) {
      return;
    }
    var html = prepend ? messages.map(function (message) {
      var mine = type === 'group' ? int(message.uid) === uid() : int(message.from_uid) === uid();
      var sender = text(message.nickname, mine ? '我' : '用户');
      var time = text(message.add_time || (message.created_at ? new Date(int(message.created_at) * 1000).toLocaleString() : ''), '');
      var roomId = int(state.active.id);
      var msgId = int(message.id);
      var canRecall = type === 'group' ? message.can_recall : mine;
      var canEssence = type === 'group' && state.roomMeta && state.roomMeta.is_admin;
      return '<article class="message ' + (mine ? 'is-mine' : '') + '">' +
        avatar({ nickname: sender, avatar: message.avatar }, 'avatar-sm') +
        '<div class="message-body">' +
          '<div class="message-head"><strong>' + esc(sender) + '</strong><span>' + esc(time) + '</span>' + (message.is_essence ? '<span class="badge warning">精华</span>' : '') + '</div>' +
          '<div class="message-bubble">' + messageContent(message) + '</div>' +
          '<div class="message-actions">' +
            '<button class="message-action" data-action="reply-message" data-type="' + type + '" data-id="' + msgId + '" data-room-id="' + roomId + '" data-label="' + esc(sender) + '">回复</button>' +
            (canRecall ? '<button class="message-action" data-action="recall-message" data-type="' + type + '" data-id="' + msgId + '" data-room-id="' + roomId + '">撤回</button>' : '') +
            (canEssence ? '<button class="message-action" data-action="toggle-essence" data-id="' + msgId + '" data-room-id="' + roomId + '">' + (message.is_essence ? '取消精华' : '设精华') + '</button>' : '') +
          '</div>' +
        '</div>' +
      '</article>';
    }).join('') : messagesHtml(messages, type);
    if (prepend) {
      var oldTop = listEl.scrollHeight;
      var loader = listEl.querySelector('.message-load-more');
      if (loader) {
        loader.remove();
      }
      listEl.insertAdjacentHTML('afterbegin', html);
      if (type === 'group' ? state.roomHasMore : state.privateHasMore) {
        listEl.insertAdjacentHTML('afterbegin', '<button class="message-load-more" type="button" data-action="load-more-messages" data-type="' + type + '">加载更早消息</button>');
      }
      listEl.scrollTop += listEl.scrollHeight - oldTop;
      return;
    }
    listEl.innerHTML = html;
  }

  async function loadMoreMessages(type) {
    var list = document.getElementById('message-list');
    if (!list) {
      return;
    }
    var roomId = int(list.dataset.roomId);
    var friendId = int(list.dataset.friendId);
    if (type === 'group') {
      if (!state.roomHasMore || !state.roomOldestId) {
        toast('没有更多消息');
        return;
      }
      var groupData = await apiGet('message/get_group_msg', { room_id: roomId, before_id: state.roomOldestId, limit: 80 }, true);
      var moreGroup = groupData.messages || [];
      if (!moreGroup.length) {
        state.roomHasMore = false;
        toast('没有更多消息');
        return;
      }
      state.roomMessages = moreGroup.concat(state.roomMessages);
      state.roomOldestId = int(moreGroup[0].id);
      state.roomHasMore = !!groupData.has_more;
      renderMessageList(list, moreGroup, 'group', true);
      return;
    }
    if (!state.privateHasMore || !state.privateOldestId) {
      toast('没有更多消息');
      return;
    }
    var privateData = await apiGet('message/get_private_msg', { friend_id: friendId, before_id: state.privateOldestId, limit: 80 }, true);
    var morePrivate = privateData.messages || [];
    if (!morePrivate.length) {
      state.privateHasMore = false;
      toast('没有更多消息');
      return;
    }
    state.privateMessages = morePrivate.concat(state.privateMessages);
    state.privateOldestId = int(morePrivate[0].id);
    state.privateHasMore = !!privateData.has_more;
    renderMessageList(list, morePrivate, 'private', true);
  }

  function parseMentionIds(value) {
    return String(value || '')
      .split(',')
      .map(function (item) { return int(item); })
      .filter(function (item, index, arr) { return item > 0 && arr.indexOf(item) === index; })
      .slice(0, 20);
  }

  function updateChatUnreadState(type, targetId) {
    if (type === 'group') {
      apiPost('message/mark_read', {
        room_id: targetId,
        last_msg_id: state.roomLatestId
      }, true).then(function () {
        state.groups.forEach(function (group) {
          if (int(group.room_id || group.id) === int(targetId)) {
            group.unread_count = 0;
          }
        });
        return refreshShellData(true);
      }).catch(function () {});
      return;
    }
    apiPost('message/mark_read', {
      friend_id: targetId
    }, true).then(function () {
      state.friends.forEach(function (friend) {
        if (int(friend.friend_id || friend.uid) === int(targetId)) {
          friend.unread_count = 0;
        }
      });
      return refreshShellData(true);
    }).catch(function () {});
  }

  function messageContent(message) {
    if (int(message.is_recalled)) {
      return '<span class="muted">消息已撤回</span>';
    }
    var reply = message.reply_content ? '<div class="reply-chip">' + replyPreview(message) + '</div>' : '';
    var mentions = mentionPreview(message);
    var type = int(message.msg_type);
    var content = text(message.content, '');
    var image = text(message.image_url, '') || (type === 2 ? content : '');
    var voice = text(message.voice_url, '') || (type === 3 ? content : '');
    if (type === 2 && image) {
      return reply + mentions + '<img class="message-media" src="' + esc(assetUrl(image)) + '" alt="图片消息" loading="lazy">';
    }
    if (type === 3 && voice) {
      return reply + mentions + '<audio controls preload="metadata" src="' + esc(assetUrl(voice)) + '"></audio><div class="muted small">' + int(message.duration || message.voice_duration) + ' 秒</div>';
    }
    return reply + mentions + br(content);
  }

  function replyPreview(message) {
    var label = esc(text(message.reply_nickname, '引用'));
    var value = text(message.reply_content, '');
    if (imageFileRe.test(value)) {
      return label + '：<img class="reply-image" src="' + esc(assetUrl(value)) + '" alt="引用图片" loading="lazy">';
    }
    return label + '：' + esc(value);
  }

  function mentionPreview(message) {
    var value = text(message.mention_uids, '');
    if (!value) {
      return '';
    }
    var chips = value.split(',').map(function (item) {
      return int(item);
    }).filter(Boolean).slice(0, 8).map(function (target) {
      return '<span class="mention-chip">@' + target + '</span>';
    }).join('');
    return chips ? '<div class="mention-line">' + chips + '</div>' : '';
  }

  function composerHtml(type, targetId) {
    if (type === 'group' && state.roomMeta && roomBanInfo(state.roomMeta.room)) {
      return '<div class="composer disabled-composer">' + roomBanBox(state.roomMeta.room) + '</div>';
    }
    var reply = state.reply && state.reply.type === type
      ? '<div class="reply-chip">回复 ' + esc(state.reply.label) + '<button class="message-action" type="button" data-action="clear-reply">取消</button></div>'
      : '';
    var recording = state.recording && state.recording.type === type && state.recording.id === targetId;
    return '<form class="composer" data-form="send-message" enctype="multipart/form-data">' +
      '<input type="hidden" name="chat_type" value="' + type + '">' +
      '<input type="hidden" name="target_id" value="' + targetId + '">' +
      (state.reply && state.reply.type === type ? '<input type="hidden" name="reply_to" value="' + int(state.reply.id) + '">' : '') +
      reply +
      '<div class="composer-grid">' +
        '<button class="icon-button voice-button" type="button" data-action="voice-toggle" data-type="' + type + '" data-id="' + targetId + '">' + (recording ? '停止' : '语音') + '</button>' +
        '<textarea class="textarea" name="content" placeholder="输入消息"></textarea>' +
        (type === 'group' ? '<input class="input" name="mention_uids" placeholder="@UID，多个逗号分隔">' : '') +
        '<label class="button ghost send-image">图片<input class="hide" type="file" name="img" accept="image/*"></label>' +
        '<button class="button primary" type="submit">发送</button>' +
      '</div>' +
    '</form>';
  }

  function scrollMessages() {
    window.requestAnimationFrame(function () {
      var list = document.getElementById('message-list');
      if (list) {
        list.scrollTop = list.scrollHeight;
      }
    });
  }

  function updateMessageList(messages, type) {
    var list = document.getElementById('message-list');
    if (!list) {
      return;
    }
    var nearBottom = list.scrollHeight - list.scrollTop - list.clientHeight < 120;
    list.innerHTML = messagesHtml(messages, type);
    if (nearBottom) {
      scrollMessages();
    }
  }

  function startGroupPoll(roomId) {
    clearPoll();
    state.pollTimer = window.setInterval(async function () {
      if (state.active.type !== 'group' || state.active.id !== roomId) {
        clearPoll();
        return;
      }
      var data = await API.get('message/get_group_msg', { room_id: roomId, after_id: state.roomLatestId, limit: 80 });
      if (data && (data._status === 401 || (data._status === 403 && data.ban_info))) {
        handleResponse(data, true);
        return;
      }
      if (data && data._status === 403 && data.room_ban_info) {
        toast('群组已封禁，聊天已停止', 'error');
        clearPoll();
        renderRoute();
        return;
      }
      if (data && data.success) {
        var incoming = data.messages || [];
        if (incoming.length) {
          state.roomMessages = state.roomMessages.concat(incoming);
          state.roomLatestId = int(state.roomMessages[state.roomMessages.length - 1].id);
          updateMessageList(state.roomMessages, 'group');
          updateChatUnreadState('group', roomId);
        }
      }
    }, 4500);
  }

  function startPrivatePoll(friendId) {
    clearPoll();
    state.pollTimer = window.setInterval(async function () {
      if (state.active.type !== 'private' || state.active.id !== friendId) {
        clearPoll();
        return;
      }
      var data = await API.get('message/get_private_msg', { friend_id: friendId, after_id: state.privateLatestId, limit: 80 });
      if (data && (data._status === 401 || (data._status === 403 && data.ban_info))) {
        handleResponse(data, true);
        return;
      }
      if (data && data.success && data.messages && data.messages.length) {
        state.privateMessages = state.privateMessages.concat(data.messages);
        state.privateLatestId = int(state.privateMessages[state.privateMessages.length - 1].id);
        updateMessageList(state.privateMessages, 'private');
        updateChatUnreadState('private', friendId);
      }
    }, 3500);
  }

  async function renderPrivate(friendId) {
    state.active = { type: 'private', id: friendId };
    state.reply = state.reply && state.reply.type === 'private' && state.reply.friendId === friendId ? state.reply : null;
    var friend = state.friends.find(function (item) { return int(item.friend_id) === friendId; });
    if (!friend) {
      var info = await apiGet('user/get_info', { uid: friendId }, true).catch(function (error) { return rethrowAuth(error, { user: { uid: friendId, nickname: '用户 ' + friendId } }); });
      friend = info.user;
      friend.friend_id = friendId;
    }
    state.privateFriend = friend;
    var data = await apiGet('message/get_private_msg', { friend_id: friendId, limit: 80 });
    state.privateMessages = data.messages || [];
    state.privateHasMore = !!data.has_more;
    state.privateOldestId = state.privateMessages.length ? int(state.privateMessages[0].id) : 0;
    state.privateLatestId = state.privateMessages.length ? int(state.privateMessages[state.privateMessages.length - 1].id) : 0;
    var main =
      '<section class="chat-route">' +
        '<div class="chat-panel">' +
          '<header class="chat-header">' +
            '<button class="icon-button chat-back" type="button" data-action="chat-back" aria-label="返回">‹</button>' +
            '<div class="chat-title chat-title-main">' +
              '<h1>' + esc(friendName(friend)) + '</h1><div class="muted small">UID ' + friendId + '</div>' +
            '</div>' +
            '<div class="inline-actions chat-tools">' +
              '<button class="button secondary" data-action="open-private-details">资料</button>' +
            '</div>' +
          '</header>' +
          '<div class="message-list" id="message-list" data-chat-type="private" data-friend-id="' + friendId + '">' + messagesHtml(state.privateMessages, 'private') + '</div>' +
          composerHtml('private', friendId) +
        '</div>' +
      '</section>';
    shell(main, 'is-chat-view');
    updateChatUnreadState('private', friendId);
    scrollMessages();
    startPrivatePoll(friendId);
  }

  function privateSideHtml(friend) {
    var friendId = int(friend && (friend.friend_id || friend.uid));
    return '<div class="panel">' +
      '<div class="section-head"><h2>好友资料</h2></div>' +
      '<div class="user-card">' + avatar(friend, 'avatar-lg') + '<div><strong>' + esc(friendName(friend)) + '</strong><div class="muted small">@' + esc(text(friend && friend.username, '')) + '</div></div></div>' +
      '<div class="inline-actions" style="margin-top:12px">' +
        '<button class="button ghost" data-action="route" data-route="user/' + friendId + '">资料页</button>' +
        '<button class="button ghost" data-action="open-remark" data-uid="' + friendId + '" data-remark="' + esc((friend && friend.remark) || '') + '">备注</button>' +
        '<button class="button danger" data-action="delete-friend" data-uid="' + friendId + '">删除</button>' +
        '<button class="button warning" data-action="block-friend" data-uid="' + friendId + '">拉黑</button>' +
      '</div>' +
    '</div>';
  }

  async function renderFriends() {
    await refreshShellData(true);
    var reqData = await apiGet('friend/get_friend_requests', {}, true).catch(function (error) { return rethrowAuth(error, { requests: [] }); });
    var delData = await apiGet('friend/get_deleted_notices', {}, true).catch(function (error) { return rethrowAuth(error, { notices: [] }); });
    var requests = reqData.requests || [];
    var deleted = delData.notices || [];
    var main = pageTitle('好友', '处理好友、恢复请求和私聊入口。', '<button class="button primary" data-action="open-add-friend">添加好友</button>') +
      '<section class="panel">' +
        '<div class="section-head"><h2>好友请求</h2><span class="badge">' + requests.length + '</span></div>' +
        '<div class="stack">' + (requests.length ? requests.map(requestRow).join('') : '<div class="empty">暂无好友请求</div>') + '</div>' +
      '</section>' +
      '<section class="panel">' +
        '<div class="section-head"><h2>最近删除</h2><span class="badge">' + deleted.length + '</span></div>' +
        '<div class="stack">' + (deleted.length ? deleted.map(deletedRow).join('') : '<div class="empty">暂无删除记录</div>') + '</div>' +
      '</section>' +
      '<section class="panel">' +
        '<div class="section-head"><h2>我的好友</h2><span class="badge">' + state.friends.length + '</span></div>' +
        '<div class="stack">' + (state.friends.length ? state.friends.map(friendCard).join('') : '<div class="empty">还没有好友</div>') + '</div>' +
      '</section>';
    shell(main);
  }

  function requestRow(req) {
    return '<div class="list-item">' +
      '<div class="item-main">' + avatar(req, 'avatar-sm') + '<div class="item-text"><strong>' + esc(req.nickname) + '</strong><span class="muted small">UID ' + int(req.from_uid) + ' · ' + esc(req.content) + '</span></div></div>' +
      '<div class="inline-actions"><button class="button primary" data-action="handle-friend-request" data-id="' + int(req.id) + '" data-result="agree">同意</button><button class="button danger" data-action="handle-friend-request" data-id="' + int(req.id) + '" data-result="refuse">拒绝</button></div>' +
    '</div>';
  }

  function deletedRow(item) {
    var fid = int(item.friend_id);
    var mine = int(item.delete_by) === uid();
    return '<div class="list-item">' +
      '<div class="item-main">' + avatar(item, 'avatar-sm') + '<div class="item-text"><strong>' + esc(item.nickname) + '</strong><span class="muted small">' + esc(item.delete_time) + '</span></div></div>' +
      '<div class="inline-actions">' +
        '<button class="button primary" data-action="' + (mine ? 'direct-recover' : 'recover-friend') + '" data-uid="' + fid + '">' + (mine ? '直接恢复' : '申请恢复') + '</button>' +
      '</div>' +
    '</div>';
  }

  async function renderNotices() {
    var data = await apiGet('user/get_notice_list');
    var notices = data.notices || [];
    var main = pageTitle('通知', '系统通知、好友提醒和管理员消息。', '<button class="button primary" data-action="mark-all-notices">全部已读</button>') +
      '<section class="panel">' +
        '<div class="stack">' + (notices.length ? notices.map(function (notice) {
          var route = text(notice.route, '') || text(notice.link, '');
          var action = route ? ' data-action="open-notice" data-id="' + int(notice.id) + '" data-route="' + esc(route) + '"' : ' data-action="mark-notice" data-id="' + int(notice.id) + '"';
          return '<div class="list-item notice-row ' + (int(notice.is_read) ? '' : 'unread') + '"' + action + ' role="button" tabindex="0">' +
            '<div class="item-text"><strong>' + esc(notice.title) + '</strong><div class="muted small">' + esc(notice.add_time) + '</div><div class="notice-content">' + br(notice.content) + '</div>' + (notice.link ? '<div class="small">' + esc(notice.link) + '</div>' : '') + '</div>' +
            '<div class="inline-actions">' + (int(notice.is_read) ? '<span class="badge">已读</span>' : '<button class="button secondary" data-action="mark-notice" data-id="' + int(notice.id) + '">标记已读</button>') + '</div>' +
          '</div>';
        }).join('') : '<div class="empty">暂无通知</div>') + '</div>' +
      '</section>';
    shell(main);
  }

  async function renderProfile() {
    var info = await apiGet('user/get_info');
    var created = await apiGet('user/get_created_groups', {}, true).catch(function (error) { return rethrowAuth(error, { groups: [] }); });
    var user = info.user || state.user;
    var ownedGroups = (created.groups || []).map(function (g) { return groupWithOwnerFallback(g, user); });
    var main = pageTitle('个人资料', '修改资料、密码和头像。') +
      '<section class="two-col">' +
        '<div class="panel">' +
          '<div class="user-card">' + avatar(user, 'avatar-lg') + '<div><h2>' + esc(user.nickname) + '</h2><div class="muted">UID ' + int(user.uid) + ' · @' + esc(user.username) + '</div></div></div>' +
          '<form data-form="update-nickname" class="stack" style="margin-top:14px"><div class="field"><label>昵称</label><input class="input" name="nickname" value="' + esc(user.nickname) + '" maxlength="16" required></div><button class="button primary" type="submit">保存昵称</button></form>' +
          '<form data-form="update-avatar" class="stack" style="margin-top:14px"><div class="field"><label>头像</label><input class="input" type="file" name="avatar" accept="image/*" required></div><button class="button primary" type="submit">上传头像</button></form>' +
        '</div>' +
        '<div class="panel">' +
          '<h2>账号安全</h2>' +
          '<form data-form="update-password" class="stack">' +
            '<div class="field"><label>原密码</label><input class="input" type="password" name="old_password" autocomplete="current-password" required></div>' +
            '<div class="field"><label>新密码</label><input class="input" type="password" name="new_password" autocomplete="new-password" minlength="6" required></div>' +
            '<div class="field"><label>确认新密码</label><input class="input" type="password" name="confirm_password" autocomplete="new-password" minlength="6" required></div>' +
            '<button class="button primary" type="submit">修改密码</button>' +
          '</form>' +
          '<div class="inline-actions" style="margin-top:14px"><button class="button danger" data-action="delete-account">注销账号</button></div>' +
        '</div>' +
      '</section>' +
      '<section class="panel">' +
        '<div class="section-head"><h2>我创建的群组</h2><span class="badge">' + ownedGroups.length + '</span></div>' +
        '<div class="grid">' + (ownedGroups.length ? ownedGroups.map(function (g) { return groupCard(g, false); }).join('') : '<div class="empty">暂无创建的群组</div>') + '</div>' +
      '</section>';
    shell(main);
  }

  async function renderUser(uidValue) {
    var data = await apiGet('user/get_info', { uid: uidValue });
    var user = data.user || {};
    var created = await apiGet('user/get_created_groups', { uid: uidValue }, true).catch(function (error) { return rethrowAuth(error, { groups: [] }); });
    var ownedGroups = (created.groups || []).map(function (g) { return groupWithOwnerFallback(g, user); });
    var actions = user.is_self
      ? '<button class="button primary" data-action="route" data-route="profile">编辑资料</button>'
      : user.is_friend
        ? '<button class="button primary" data-action="route" data-route="private/' + uidValue + '">私聊</button>'
        : user.can_add_friend
          ? '<button class="button primary" data-action="send-friend-direct" data-uid="' + uidValue + '">添加好友</button>'
          : '<span class="badge warning">不可添加</span>';
    var main = pageTitle(text(user.nickname, '用户资料'), 'UID ' + uidValue, actions) +
      '<section class="two-col">' +
        '<div class="panel">' +
          '<div class="user-card">' + avatar(user, 'avatar-lg') + '<div><h2>' + esc(user.nickname) + '</h2><div class="muted">@' + esc(user.username) + '</div><div class="muted small">' + esc(plain(user.online_status)) + '</div></div></div>' +
          '<div class="inline-actions" style="margin-top:12px">' +
            (!user.is_self ? '<button class="button ghost" data-action="report-user" data-uid="' + uidValue + '" data-name="' + esc(user.nickname) + '">举报</button>' : '') +
          '</div>' +
        '</div>' +
        '<div class="panel"><h2>创建的群组</h2><div class="stack">' + (ownedGroups.length ? ownedGroups.map(function (g) { return groupCard(g, true); }).join('') : '<div class="empty">暂无公开创建群组</div>') + '</div></div>' +
      '</section>';
    shell(main);
  }

  function renderBug() {
    var main = pageTitle('反馈', '提交使用过程中遇到的问题。') +
      '<section class="panel"><form data-form="bug-report" class="stack">' +
        '<div class="field"><label>标题</label><input class="input" name="title" required></div>' +
        '<div class="field"><label>描述</label><textarea class="textarea" name="description" required></textarea></div>' +
        '<button class="button primary" type="submit">提交反馈</button>' +
      '</form></section>';
    shell(main);
  }

  function renderReport(query) {
    var type = query.get('type') || 'user';
    var id = query.get('id') || '';
    var name = query.get('name') || '';
    var main = pageTitle('举报', '举报用户或群组。') +
      '<section class="panel"><form data-form="submit-report" class="stack">' +
        '<div class="field"><label>类型</label><select class="select" name="type">' + optionHtmlText('user', '用户', type) + optionHtmlText('group', '群组', type) + '</select></div>' +
        '<div class="field"><label>目标 ID</label><input class="input" name="target_id" value="' + esc(id) + '" inputmode="numeric" required></div>' +
        '<div class="field"><label>目标名称</label><input class="input" name="target_name" value="' + esc(name) + '"></div>' +
        '<div class="field"><label>原因</label><textarea class="textarea" name="reason" minlength="10" required></textarea></div>' +
        '<label><input type="checkbox" name="anonymous"> 匿名提交</label>' +
        '<button class="button primary" type="submit">提交举报</button>' +
      '</form></section>';
    shell(main);
  }

  function optionHtmlText(value, label, current) {
    return '<option value="' + esc(value) + '" ' + (String(current) === String(value) ? 'selected' : '') + '>' + esc(label) + '</option>';
  }

  async function renderAdmin() {
    if (uid() !== 1) {
      shell(pageTitle('无权限', '仅管理员可访问。') + '<div class="error-box">当前账号不是管理员。</div>');
      return;
    }
    var valid = state.adminToken && state.adminTokenExpire > Date.now();
    var data = valid ? await apiGet('admin/admin_ban', { token: state.adminToken }, true).catch(function (error) { return rethrowAuth(error, null); }) : null;
    var body = data
      ? adminPanelHtml(data)
      : '<section class="panel"><p class="muted">管理员接口需要 5 分钟临时令牌。</p><button class="button primary" data-action="admin-token">生成令牌并进入</button></section>';
    shell(pageTitle('封禁管理', '用户与群组封禁。') + body);
  }

  function adminPanelHtml(data) {
    return '<section class="grid">' +
      '<div class="panel"><h2>封禁用户</h2><form data-form="admin-ban-user" class="stack">' +
        '<div class="field"><label>用户 UID</label><input class="input" name="user_id" inputmode="numeric" required></div>' +
        '<div class="field"><label>天数</label><input class="input" name="ban_days" inputmode="numeric" required></div>' +
        '<div class="field"><label>原因</label><input class="input" name="ban_reason" required></div>' +
        '<button class="button danger" type="submit">封禁用户</button></form></div>' +
      '<div class="panel"><h2>封禁群组</h2><form data-form="admin-ban-room" class="stack">' +
        '<div class="field"><label>群组 ID</label><input class="input" name="room_id" inputmode="numeric" required></div>' +
        '<div class="field"><label>天数</label><input class="input" name="ban_days" inputmode="numeric" required></div>' +
        '<div class="field"><label>原因</label><input class="input" name="ban_reason" required></div>' +
        '<button class="button danger" type="submit">封禁群组</button></form></div>' +
    '</section>' +
    '<section class="panel"><div class="section-head"><h2>已封禁用户</h2><span class="badge">' + (data.users || []).length + '</span></div>' + tableUsers(data.users || []) + '</section>' +
    '<section class="panel"><div class="section-head"><h2>已封禁群组</h2><span class="badge">' + (data.rooms || []).length + '</span></div>' + tableRooms(data.rooms || []) + '</section>';
  }

  function tableUsers(rows) {
    if (!rows.length) {
      return '<div class="empty">暂无封禁用户</div>';
    }
    return '<div class="table-wrap"><table class="data-table"><thead><tr><th>UID</th><th>昵称</th><th>原因</th><th>到期</th><th></th></tr></thead><tbody>' + rows.map(function (row) {
      return '<tr><td>' + int(row.id) + '</td><td>' + esc(row.nickname) + '</td><td>' + esc(row.ban_reason) + '</td><td>' + esc(row.ban_until_date) + '</td><td><button class="button secondary" data-action="admin-unban-user" data-uid="' + int(row.id) + '">解封</button></td></tr>';
    }).join('') + '</tbody></table></div>';
  }

  function tableRooms(rows) {
    if (!rows.length) {
      return '<div class="empty">暂无封禁群组</div>';
    }
    return '<div class="table-wrap"><table class="data-table"><thead><tr><th>群 ID</th><th>群名</th><th>原因</th><th>到期</th><th></th></tr></thead><tbody>' + rows.map(function (row) {
      return '<tr><td>' + int(row.id) + '</td><td>' + esc(row.room_name) + '</td><td>' + esc(row.ban_reason) + '</td><td>' + esc(row.ban_until_date) + '</td><td><button class="button secondary" data-action="admin-unban-room" data-room-id="' + int(row.id) + '">解封</button></td></tr>';
    }).join('') + '</tbody></table></div>';
  }

  function showEssenceModal() {
    openModal('精华消息', state.essence.length ? '<div class="stack">' + state.essence.map(function (item) {
      return '<div class="list-item"><div class="item-text"><strong>' + esc(item.nickname) + '</strong><div class="muted small">' + esc(item.set_nick) + ' · ' + esc(item.set_time) + '</div><div class="message-bubble">' + messageContent(item) + '</div></div></div>';
    }).join('') + '</div>' : '<div class="empty">暂无精华消息</div>');
  }

  function openCreateGroup() {
    openModal('创建群组',
      '<form data-form="create-group" class="stack">' +
        '<div class="field"><label>群组名称</label><input class="input" name="room_name" maxlength="32" required></div>' +
        '<button class="button primary" type="submit">创建</button>' +
      '</form>');
  }

  function openAddFriend(uidValue) {
    openModal('添加好友',
      '<form data-form="add-friend" class="stack">' +
        '<div class="field"><label>用户 UID</label><input class="input" name="friend_id" inputmode="numeric" value="' + esc(uidValue || '') + '" required></div>' +
        '<div class="field"><label>验证消息</label><input class="input" name="message" value="请求添加你为好友"></div>' +
        '<button class="button primary" type="submit">发送请求</button>' +
      '</form>');
  }

  function openRemark(uidValue, remark) {
    openModal('修改备注',
      '<form data-form="update-remark" class="stack">' +
        '<input type="hidden" name="friend_id" value="' + int(uidValue) + '">' +
        '<div class="field"><label>备注</label><input class="input" name="remark" value="' + esc(remark || '') + '"></div>' +
        '<button class="button primary" type="submit">保存</button>' +
      '</form>');
  }

  function openMute(roomId, targetUid) {
    openModal('成员禁言',
      '<form data-form="mute-member" class="stack">' +
        '<input type="hidden" name="room_id" value="' + int(roomId) + '">' +
        '<input type="hidden" name="target_uid" value="' + int(targetUid) + '">' +
        '<div class="field"><label>分钟数</label><input class="input" name="minutes" inputmode="numeric" value="10"></div>' +
        '<button class="button warning" type="submit" name="action" value="mute">禁言</button>' +
        '<button class="button secondary" type="button" data-action="unmute-member" data-room-id="' + int(roomId) + '" data-uid="' + int(targetUid) + '">解除禁言</button>' +
      '</form>');
  }

  async function submitForm(form) {
    var type = form.dataset.form;
    var data = formObject(form);
    if (type === 'login') {
      var login = await apiPost('auth/login', data);
      state.user = login.user || null;
      toast(login.message || '登录成功');
      await loadSession().catch(function () {
        return refreshShellData(true);
      });
      setHash('dashboard');
      return;
    }
    if (type === 'register') {
      var fd = new FormData(form);
      var reg = await apiPost('auth/register', fd);
      state.user = reg.user || null;
      toast(reg.message || '注册成功');
      await loadSession().catch(function () {
        return refreshShellData(true);
      });
      setHash('dashboard');
      return;
    }
    if (type === 'go-group') {
      closeModal();
      setHash('group/' + int(data.room_id));
      return;
    }
    if (type === 'go-user') {
      closeModal();
      setHash('user/' + int(data.uid));
      return;
    }
    if (type === 'create-group') {
      var created = await apiPost('group/create', { room_name: data.room_name });
      closeModal();
      toast(created.message || '群组已创建');
      await refreshShellData(true);
      setHash('group/' + int(created.room_id || created.id));
      return;
    }
    if (type === 'join-group') {
      await apiPost('group/apply_join', data);
      toast('请求已提交');
      await refreshShellData(true);
      renderRoute();
      return;
    }
    if (type === 'send-message') {
      await sendMessage(form);
      return;
    }
    if (type === 'add-friend') {
      await apiPost('friend/send_request', data);
      closeModal();
      toast('好友请求已发送');
      await refreshShellData(true);
      renderRoute();
      return;
    }
    if (type === 'update-remark') {
      await apiPost('friend/update_remark', data);
      closeModal();
      toast('备注已更新');
      await refreshShellData(false);
      renderRoute();
      return;
    }
    if (type === 'edit-group-info') {
      await apiPost('group/edit_info', data);
      toast('群资料已保存');
      renderRoute();
      return;
    }
    if (type === 'group-settings') {
      await apiPost('group/update_settings', data);
      toast('群设置已保存');
      renderRoute();
      return;
    }
    if (type === 'group-transfer') {
      await apiPost('group/transfer', data);
      toast('转让申请已发送');
      form.reset();
      return;
    }
    if (type === 'mute-member') {
      await apiPost('group/mute_member', Object.assign(data, { action: 'mute' }));
      closeModal();
      toast('禁言已设置');
      renderRoute();
      return;
    }
    if (type === 'update-nickname') {
      await apiPost('user/update_profile', { action: 'nickname', nickname: data.nickname });
      toast('昵称已更新');
      await loadSession();
      renderRoute();
      return;
    }
    if (type === 'update-avatar') {
      var avatarData = new FormData(form);
      avatarData.set('action', 'avatar');
      await apiPost('user/update_profile', avatarData);
      toast('头像已更新');
      await loadSession();
      renderRoute();
      return;
    }
    if (type === 'update-password') {
      await apiPost('user/update_profile', Object.assign(data, { action: 'password' }));
      toast('密码已修改');
      form.reset();
      return;
    }
    if (type === 'bug-report') {
      await apiPost('bug_report', data);
      toast('反馈已提交');
      form.reset();
      return;
    }
    if (type === 'submit-report') {
      var report = {
        type: data.type,
        reason: data.reason,
        anonymous: data.anonymous,
        nickname: data.type === 'user' ? data.target_name : '',
        username: data.type === 'user' ? data.target_name : '',
        room_name: data.type === 'group' ? data.target_name : ''
      };
      if (data.type === 'user') {
        report.uid = int(data.target_id);
      } else {
        report.rid = int(data.target_id);
      }
      await apiPost('report/submit_report', report);
      toast('举报已提交');
      setHash('dashboard');
      return;
    }
    if (type === 'admin-ban-user') {
      await adminPost({ action: 'ban_user', user_id: data.user_id, ban_days: data.ban_days, ban_reason: data.ban_reason });
      renderRoute();
      return;
    }
    if (type === 'admin-ban-room') {
      await adminPost({ action: 'ban_room', room_id: data.room_id, ban_days: data.ban_days, ban_reason: data.ban_reason });
      renderRoute();
    }
  }

  async function sendMessage(form) {
    var fd = new FormData(form);
    var chatType = fd.get('chat_type');
    var targetId = int(fd.get('target_id'));
    var img = form.querySelector('input[name="img"]').files[0];
    var content = text(fd.get('content'), '');
    if (!content && !img) {
      toast('消息内容不能为空', 'warning');
      return;
    }
    var body = new FormData();
    body.set('content', content);
    if (fd.get('reply_to')) {
      body.set('reply_to', fd.get('reply_to'));
    }
    if (img) {
      body.set('img', img);
    }
    if (chatType === 'group') {
      body.set('room_id', targetId);
      var mentionIds = parseMentionIds(fd.get('mention_uids'));
      if (mentionIds.length) {
        body.set('mention_uids', mentionIds.join(','));
      }
      await apiPost('message/send_group_msg', body);
      state.reply = null;
      await loadGroupChat(targetId);
      renderGroupChat();
      startGroupPoll(targetId);
    } else {
      body.set('friend_id', targetId);
      await apiPost('message/send_private_msg', body);
      state.reply = null;
      await renderPrivate(targetId);
    }
  }

  async function adminPost(body) {
    body.token = state.adminToken;
    await apiPost('admin/admin_ban', body);
    state.adminToken = '';
    state.adminTokenExpire = 0;
    toast('管理员操作完成');
  }

  function chooseRecorderFormat() {
    var options = [
      { mime: 'audio/webm;codecs=opus', type: 'audio/webm', ext: 'webm' },
      { mime: 'audio/webm', type: 'audio/webm', ext: 'webm' },
      { mime: 'audio/ogg;codecs=opus', type: 'audio/ogg', ext: 'ogg' },
      { mime: 'audio/ogg', type: 'audio/ogg', ext: 'ogg' },
      { mime: 'audio/mp4', type: 'audio/mp4', ext: 'm4a' },
      { mime: 'video/mp4', type: 'video/mp4', ext: 'm4a' },
      { mime: 'video/webm;codecs=opus', type: 'video/webm', ext: 'webm' },
      { mime: 'video/webm', type: 'video/webm', ext: 'webm' }
    ];
    if (!window.MediaRecorder || typeof MediaRecorder.isTypeSupported !== 'function') {
      return { mime: '', type: 'audio/webm', ext: 'webm' };
    }
    for (var i = 0; i < options.length; i += 1) {
      if (MediaRecorder.isTypeSupported(options[i].mime)) {
        return options[i];
      }
    }
    return { mime: '', type: 'audio/webm', ext: 'webm' };
  }

  function voiceExtension(mime) {
    var clean = String(mime || '').split(';')[0].trim().toLowerCase();
    if (clean === 'audio/ogg' || clean === 'application/ogg') {
      return 'ogg';
    }
    if (clean === 'audio/mpeg' || clean === 'audio/mp3') {
      return 'mp3';
    }
    if (clean === 'audio/wav' || clean === 'audio/x-wav' || clean === 'audio/wave') {
      return 'wav';
    }
    if (clean === 'audio/mp4' || clean === 'video/mp4' || clean === 'audio/x-m4a' || clean === 'audio/m4a') {
      return 'm4a';
    }
    if (clean === 'audio/3gpp' || clean === 'video/3gpp') {
      return '3gp';
    }
    return 'webm';
  }

  async function toggleVoice(type, targetId) {
    if (state.recording) {
      state.recorder.stop();
      return;
    }
    if (!navigator.mediaDevices || !window.MediaRecorder) {
      toast('当前浏览器不支持录音', 'warning');
      return;
    }
    var stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    var format = chooseRecorderFormat();
    var recorder = format.mime ? new MediaRecorder(stream, { mimeType: format.mime }) : new MediaRecorder(stream);
    state.recorder = recorder;
    state.recorderChunks = [];
    state.recording = { type: type, id: targetId, startedAt: Date.now(), stream: stream, format: format };
    recorder.ondataavailable = function (event) {
      if (event.data && event.data.size) {
        state.recorderChunks.push(event.data);
      }
    };
    recorder.onstop = async function () {
      try {
        var recording = state.recording;
        state.recording = null;
        stream.getTracks().forEach(function (track) { track.stop(); });
        var chunkType = state.recorderChunks[0] && state.recorderChunks[0].type;
        var actualType = recorder.mimeType || chunkType || recording.format.type || 'audio/webm';
        var blob = new Blob(state.recorderChunks, { type: actualType });
        var body = new FormData();
        body.set('voice', blob, 'voice.' + voiceExtension(actualType || recording.format.type));
        body.set('duration', Math.max(1, Math.round((Date.now() - recording.startedAt) / 1000)));
        if (type === 'group') {
          body.set('room_id', targetId);
        } else {
          body.set('friend_id', targetId);
        }
        await apiPost('message/send_voice_msg', body);
        toast('语音已发送');
        renderRoute();
      } catch (error) {
        if (!isAuthError(error)) {
          toast(error.message || '语音发送失败', 'error');
        }
      }
    };
    recorder.start();
    toast('正在录音，再点一次发送');
    renderRoute();
  }

  async function handleClick(event) {
    var actionEl = event.target.closest('[data-action]');
    if (!actionEl) {
      return;
    }
    if ((actionEl.classList.contains('group-card') || actionEl.classList.contains('friend-row')) && event.target.closest('button,a,input,textarea,select,label')) {
      return;
    }
    var action = actionEl.dataset.action;
    if (action === 'modal-close') {
      if (!event.target.closest('[data-modal-box]') || event.target === actionEl) {
        closeModal();
      }
      return;
    }
    event.preventDefault();
    if (action === 'theme-toggle') {
      toggleTheme();
      return;
    }
    if (action === 'mobile-layout-toggle') {
      toggleMobileLayout();
      return;
    }
    if (action === 'open-mobile-search') {
      openMobileSearch();
      return;
    }
    if (action === 'route') {
      var route = actionEl.dataset.route || 'dashboard';
      if (/^(group|private)\//.test(route)) {
        setEntryRoute(currentHashRoute());
      }
      pushRouteHistory(currentHashRoute());
      setHash(route);
      return;
    }
    if (action === 'chat-back') {
      goBackRoute();
      return;
    }
    if (action === 'refresh') {
      renderRoute();
      return;
    }
    if (action === 'logout') {
      await apiPost('auth/logout', {}, true).catch(function () {});
      state.user = null;
      renderAuth('login');
      window.location.hash = '#/login';
      return;
    }
    if (action === 'open-create-group') {
      openCreateGroup();
      return;
    }
    if (action === 'open-add-friend') {
      openAddFriend();
      return;
    }
    if (action === 'send-friend-direct') {
      openAddFriend(actionEl.dataset.uid);
      return;
    }
    if (action === 'open-remark') {
      openRemark(actionEl.dataset.uid, actionEl.dataset.remark);
      return;
    }
    if (action === 'handle-friend-request') {
      await apiPost('friend/handle_request', { request_id: int(actionEl.dataset.id), action: actionEl.dataset.result });
      toast('请求已处理');
      await refreshShellData(false);
      renderRoute();
      return;
    }
    if (action === 'direct-recover' || action === 'recover-friend') {
      await apiPost('friend/recover_friend', { friend_id: int(actionEl.dataset.uid), direct: action === 'direct-recover' ? '1' : '0' });
      toast('恢复请求已处理');
      renderRoute();
      return;
    }
    if (action === 'delete-friend' || action === 'block-friend') {
      var route = action === 'delete-friend' ? 'friend/delete_friend' : 'friend/block_friend';
      confirmDialog(action === 'delete-friend' ? '删除好友' : '拉黑好友', '确认执行该操作？', async function () {
        await apiPost(route, { friend_id: int(actionEl.dataset.uid) });
        await refreshShellData(false);
        setHash('friends');
      });
      return;
    }
    if (action === 'reply-message') {
      state.reply = {
        type: actionEl.dataset.type,
        id: int(actionEl.dataset.id),
        roomId: int(actionEl.dataset.roomId),
        friendId: state.active.id,
        label: actionEl.dataset.label || '消息'
      };
      renderRoute();
      return;
    }
    if (action === 'clear-reply') {
      state.reply = null;
      renderRoute();
      return;
    }
    if (action === 'recall-message') {
      await apiPost('message/recall_msg', {
        msg_id: int(actionEl.dataset.id),
        room_id: int(actionEl.dataset.roomId),
        type: actionEl.dataset.type
      });
      toast('消息已撤回');
      refreshActiveView();
      return;
    }
    if (action === 'toggle-essence') {
      await apiPost('essence/set_essence', { msg_id: int(actionEl.dataset.id), room_id: int(actionEl.dataset.roomId) });
      toast('精华状态已更新');
      renderRoute();
      return;
    }
    if (action === 'open-group-details') {
      openDrawer('群聊资料', groupSideHtml(state.roomMeta || {}));
      return;
    }
    if (action === 'load-more-messages') {
      await loadMoreMessages(actionEl.dataset.type);
      return;
    }
    if (action === 'open-private-details') {
      openDrawer('好友资料', privateSideHtml(state.privateFriend || {}));
      return;
    }
    if (action === 'voice-toggle') {
      await toggleVoice(actionEl.dataset.type, int(actionEl.dataset.id));
      return;
    }
    if (action === 'mark-group-read') {
      var last = state.roomMessages.length ? int(state.roomMessages[state.roomMessages.length - 1].id) : 0;
      await apiPost('message/mark_read', { room_id: int(actionEl.dataset.roomId), last_msg_id: last });
      toast('已更新已读位置');
      await refreshShellData(true);
      state.roomMessages.forEach(function (message) {
        message.is_read = 1;
      });
      return;
    }
    if (action === 'leave-group') {
      confirmDialog('退出群组', '确认退出该群组？', async function () {
        await apiPost('group/leave', { room_id: int(actionEl.dataset.roomId) });
        await refreshShellData(false);
        setHash('groups');
      });
      return;
    }
    if (action === 'open-mute') {
      openMute(actionEl.dataset.roomId, actionEl.dataset.uid);
      return;
    }
    if (action === 'unmute-member') {
      await apiPost('group/mute_member', { room_id: int(actionEl.dataset.roomId), target_uid: int(actionEl.dataset.uid), action: 'unmute' });
      closeModal();
      toast('已解除禁言');
      renderRoute();
      return;
    }
    if (action === 'kick-member') {
      confirmDialog('踢出成员', '确认将该成员移出群组？', async function () {
        await apiPost('group/kick_member', { room_id: int(actionEl.dataset.roomId), target_uid: int(actionEl.dataset.uid) });
        renderRoute();
      });
      return;
    }
    if (action === 'toggle-admin') {
      await apiPost('group/set_admin', { room_id: int(actionEl.dataset.roomId), target_uid: int(actionEl.dataset.uid), action: actionEl.dataset.admin === '1' ? 'remove' : 'set' });
      toast('管理员状态已更新');
      renderRoute();
      return;
    }
    if (action === 'handle-apply') {
      await apiPost('group/handle_apply', { apply_id: int(actionEl.dataset.id), action: actionEl.dataset.result });
      toast('申请已处理');
      renderRoute();
      return;
    }
    if (action === 'reset-invite') {
      var reset = await apiPost('group/reset_invite_code', { room_id: int(actionEl.dataset.roomId) });
      toast('新邀请码：' + text(reset.invite_code || reset.new_code, ''));
      renderRoute();
      return;
    }
    if (action === 'disband-group') {
      confirmDialog('解散群组', '确认解散该群组？该操作会通知所有成员。', async function () {
        await apiPost('group/disband', { room_id: int(actionEl.dataset.roomId) });
        await refreshShellData(false);
        setHash('groups');
      });
      return;
    }
    if (action === 'mark-notice') {
      await apiPost('user/mark_notice_read', { notice_id: int(actionEl.dataset.id) });
      await refreshShellData(false);
      renderRoute();
      return;
    }
    if (action === 'open-notice') {
      await apiPost('user/mark_notice_read', { notice_id: int(actionEl.dataset.id) }, true).catch(function () {});
      openNoticeRoute(actionEl.dataset);
      return;
    }
    if (action === 'mark-all-notices') {
      await apiPost('user/mark_notice_read', { read_all: '1' });
      await refreshShellData(false);
      renderRoute();
      return;
    }
    if (action === 'delete-account') {
      confirmDialog('注销账号', '确认注销当前账号？该操作不可恢复。', async function () {
        await apiPost('user/delete_account', {});
        state.user = null;
        renderAuth('login');
      });
      return;
    }
    if (action === 'report-user') {
      setHash('report?type=user&id=' + int(actionEl.dataset.uid) + '&name=' + encodeURIComponent(actionEl.dataset.name || ''));
      return;
    }
    if (action === 'report-group') {
      setHash('report?type=group&id=' + int(actionEl.dataset.roomId) + '&name=' + encodeURIComponent(actionEl.dataset.roomName || ''));
      return;
    }
    if (action === 'admin-token') {
      var token = await apiPost('admin/generate_token', {});
      state.adminToken = token.token;
      state.adminTokenExpire = Date.now() + int(token.expires_in) * 1000;
      renderRoute();
      return;
    }
    if (action === 'admin-unban-user') {
      await adminPost({ action: 'unban_user', user_id: int(actionEl.dataset.uid) });
      renderRoute();
      return;
    }
    if (action === 'admin-unban-room') {
      await adminPost({ action: 'unban_room', room_id: int(actionEl.dataset.roomId) });
      renderRoute();
    }
  }

  async function renderRoute() {
    applyTheme();
    var route = parseHash();
    clearPoll();

    if (route.name === 'login' || route.name === 'register') {
      if (!state.user && !state.booted) {
        await loadSession().catch(function () { return false; });
      }
      state.booted = true;
      if (state.user) {
        setHash('dashboard');
      } else {
        renderAuth(route.name);
      }
      return;
    }

    if (!state.user) {
      var ok = await loadSession().catch(function () { return false; });
      state.booted = true;
      if (!ok) {
        renderAuth('login');
        window.location.hash = '#/login';
        return;
      }
    }

    try {
      if (route.name === 'dashboard') {
        await renderDashboard();
      } else if (route.name === 'groups') {
        await renderGroups();
      } else if (route.name === 'essence') {
        await renderEssenceRoute(int(route.parts[1]), route.query);
      } else if (route.name === 'group') {
        await renderGroupRoute(int(route.parts[1]));
      } else if (route.name === 'private') {
        await renderPrivate(int(route.parts[1]));
      } else if (route.name === 'friends') {
        await renderFriends();
      } else if (route.name === 'notices') {
        await renderNotices();
      } else if (route.name === 'profile') {
        await renderProfile();
      } else if (route.name === 'user') {
        await renderUser(int(route.parts[1]));
      } else if (route.name === 'bug') {
        renderBug();
      } else if (route.name === 'report') {
        renderReport(route.query);
      } else if (route.name === 'admin') {
        await renderAdmin();
      } else {
        setHash('dashboard');
      }
    } catch (error) {
      if (isAuthError(error)) {
        return;
      }
      shell(pageTitle('加载失败', '当前视图无法加载。') + '<div class="error-box">' + esc(error && error.message ? error.message : '未知错误') + '</div>');
    }
  }

  document.addEventListener('submit', function (event) {
    var form = event.target.closest('form[data-form]');
    if (!form) {
      return;
    }
    event.preventDefault();
    var submit = form.querySelector('button[type="submit"]');
    if (submit) {
      submit.disabled = true;
    }
    submitForm(form).catch(function (error) {
      if (!isAuthError(error)) {
        toast(error.message || '操作失败', 'error');
      }
    }).finally(function () {
      if (submit) {
        submit.disabled = false;
      }
    });
  });

  document.addEventListener('click', function (event) {
    handleClick(event).catch(function (error) {
      if (!isAuthError(error)) {
        toast(error.message || '操作失败', 'error');
      }
    });
  });

  window.addEventListener('resize', function () {
    if (!localStorage.getItem(MOBILE_LAYOUT_KEY)) {
      applyMobileLayout();
    }
  });
  window.addEventListener('hashchange', renderRoute);
  applyTheme();
  if (window.CSAC_BOOT_TIMER) {
    window.clearTimeout(window.CSAC_BOOT_TIMER);
    window.CSAC_BOOT_TIMER = 0;
  }
  renderRoute();
})();
