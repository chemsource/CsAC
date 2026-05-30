(function () {
  'use strict';

  function normalizeRoute(route) {
    return String(route || '').trim().replace(/^\/+/, '').replace(/\.php$/i, '');
  }

  function baseUrl() {
    return new URL('rpc/UniCsAC.php', window.location.href).toString();
  }

  function appendParams(url, params) {
    if (!params || typeof params !== 'object') {
      return;
    }
    Object.entries(params).forEach(function ([key, value]) {
      if (value === undefined || value === null || value === '') {
        return;
      }
      url.searchParams.set(key, value);
    });
  }

  function looksLikeVmhostChallenge(text) {
    return !!text && (
      (/toNumbers\("[0-9a-fA-F]+"\)/.test(text) && /toHex|slowAES/.test(text)) ||
      text.indexOf('__test') !== -1 ||
      text.indexOf('document.cookie') !== -1 ||
      text.indexOf('Javascript in your browser') !== -1
    );
  }

  function challengeMessage() {
    return '服务器安全验证中，已尝试自动刷新验证，请稍后重试';
  }

  function hexToBytes(hex) {
    var clean = String(hex || '').trim();
    if (!clean || clean.length % 2 !== 0 || /[^0-9a-f]/i.test(clean)) {
      throw new Error('hex invalid');
    }
    var out = new Uint8Array(clean.length / 2);
    for (var i = 0; i < clean.length; i += 2) {
      out[i / 2] = parseInt(clean.slice(i, i + 2), 16);
    }
    return out;
  }

  function bytesToHex(bytes) {
    return Array.prototype.map.call(new Uint8Array(bytes), function (byte) {
      return byte.toString(16).padStart(2, '0');
    }).join('');
  }

  function vmhostParams(text) {
    var strict = /(?:^|[^\w])a\s*=\s*toNumbers\("([0-9a-fA-F]+)"\)[\s\S]*?(?:^|[^\w])b\s*=\s*toNumbers\("([0-9a-fA-F]+)"\)[\s\S]*?(?:^|[^\w])c\s*=\s*toNumbers\("([0-9a-fA-F]+)"\)/m.exec(text);
    if (strict) {
      return [strict[1], strict[2], strict[3]];
    }
    var values = [];
    var re = /toNumbers\("([0-9a-fA-F]+)"\)/g;
    var match;
    while ((match = re.exec(text))) {
      if (match[1].length >= 32) {
        values.push(match[1]);
      }
    }
    return values.length >= 3 ? values.slice(0, 3) : null;
  }

  async function solveVmhostChallenge(text) {
    if (!window.crypto || !window.crypto.subtle) {
      return false;
    }
    var params = vmhostParams(text);
    if (!params) {
      return false;
    }
    try {
      var key = hexToBytes(params[0]);
      var iv = hexToBytes(params[1]);
      var cipher = hexToBytes(params[2]);
      var cryptoKey = await window.crypto.subtle.importKey('raw', key, { name: 'AES-CBC' }, false, ['decrypt']);
      var plain = await window.crypto.subtle.decrypt({ name: 'AES-CBC', iv: iv }, cryptoKey, cipher);
      document.cookie = '__test=' + bytesToHex(plain) + '; max-age=21600; path=/; SameSite=Lax';
      return true;
    } catch (error) {
      return false;
    }
  }

  function primeVmhostChallenge(url) {
    return new Promise(function (resolve) {
      var iframe = document.createElement('iframe');
      var done = false;
      var finish = function (ok) {
        if (done) {
          return;
        }
        done = true;
        window.clearTimeout(timer);
        iframe.remove();
        resolve(ok);
      };
      var timer = window.setTimeout(function () {
        finish(false);
      }, 2200);
      iframe.onload = function () {
        window.setTimeout(function () {
          finish(true);
        }, 180);
      };
      iframe.style.cssText = 'position:absolute;width:1px;height:1px;left:-9999px;top:-9999px;border:0;opacity:0;pointer-events:none;';
      iframe.setAttribute('aria-hidden', 'true');
      iframe.src = url;
      document.body.appendChild(iframe);
    });
  }

  function compactErrorText(text) {
    if (/^\s*<!doctype|^\s*<html|<body[\s>]/i.test(String(text || ''))) {
      return '服务器返回了非 JSON 页面，请稍后重试';
    }
    var value = String(text || '').replace(/<script[\s\S]*?<\/script>/gi, ' ')
      .replace(/<style[\s\S]*?<\/style>/gi, ' ')
      .replace(/<[^>]+>/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
    if (!value) {
      return '响应解析失败';
    }
    return value.slice(0, 180);
  }

  async function request(method, route, payload, options) {
    options = options || {};
    var url = new URL(baseUrl(), window.location.href);
    url.searchParams.set('route', normalizeRoute(route));

    var fetchOptions = {
      method: method,
      credentials: 'include',
      cache: 'no-store',
      headers: {
        Accept: 'application/json, text/plain, */*',
        'X-Requested-With': 'XMLHttpRequest'
      }
    };

    if (options && options.headers) {
      Object.assign(fetchOptions.headers, options.headers);
    }

    if (method === 'GET') {
      appendParams(url, payload);
    } else if (payload instanceof FormData) {
      fetchOptions.body = payload;
    } else if (payload && typeof payload === 'object') {
      fetchOptions.headers['Content-Type'] = 'application/json';
      fetchOptions.body = JSON.stringify(payload);
    }

    var response;
    try {
      response = await fetch(url.toString(), fetchOptions);
    } catch (error) {
      return {
        success: false,
        message: '网络请求失败',
        error: String(error && error.message ? error.message : error),
        _status: 0
      };
    }

    var data;
    var text = '';
    try {
      text = await response.text();
      if (looksLikeVmhostChallenge(text)) {
        var attempts = options._challengeAttempts || 0;
        if (attempts < 2) {
          var solved = await solveVmhostChallenge(text);
          if (!solved) {
            solved = await primeVmhostChallenge(url.toString());
          }
          if (solved) {
            return request(method, route, payload, Object.assign({}, options, { _challengeAttempts: attempts + 1 }));
          }
        }
        return {
          success: false,
          message: challengeMessage(),
          challenge: true,
          _status: response.status,
          _ok: response.ok
        };
      }
      data = text ? JSON.parse(text) : {};
    } catch (error) {
      data = {
        success: false,
        message: compactErrorText(text)
      };
    }
    if (!data || typeof data !== 'object') {
      data = { success: false, message: '响应格式无效' };
    }
    data._status = response.status;
    data._ok = response.ok;
    return data;
  }

  var client = {
    get: function (route, params, options) {
      return request('GET', route, params || null, options || {});
    },
    post: function (route, body, options) {
      return request('POST', route, body || null, options || {});
    },
    postFormData: function (route, formData, options) {
      return request('POST', route, formData, options || {});
    },
    request: request,
    route: normalizeRoute,
    baseUrl: baseUrl()
  };

  window.UniCsAC = client;
  window.API = client;
})();
