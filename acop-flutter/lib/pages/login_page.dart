import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _csacUserCtrl = TextEditingController();
  final _csacPwdCtrl = TextEditingController();

  // 0=密码登录, 1=验证码登录, 2=注册
  int _mode = 0;
  bool _obscurePwd = true;
  bool _obscureCsacPwd = true;
  int _countdown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pwdCtrl.dispose();
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _csacUserCtrl.dispose();
    _csacPwdCtrl.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _countdown = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() {
        _countdown--;
        if (_countdown <= 0) t.cancel();
      });
    });
  }

  Future<void> _sendCode() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入有效的邮箱地址')));
      return;
    }
    final state = context.read<AppState>();
    final purpose = _mode == 2 ? 'register' : 'login';
    final result = await state.sendCode(email, purpose);
    if (!mounted) return;

    if (result['success'] == true) {
      _startCountdown();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('验证码已发送，请查收邮箱')));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result['message'] ?? '发送失败')));
    }
  }

  Future<void> _submit() async {
    final state = context.read<AppState>();

    if (_mode == 0) {
      // 密码登录
      final ok = await state.login(_emailCtrl.text.trim(), _pwdCtrl.text);
      if (!ok && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(state.error ?? '登录失败')));
      }
    } else if (_mode == 1) {
      // 验证码登录
      final ok = await state.loginByCode(
        _emailCtrl.text.trim(),
        _codeCtrl.text.trim(),
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(state.error ?? '验证码登录失败')));
      }
    } else {
      // 注册
      final ok = await state.register(
        _emailCtrl.text.trim(),
        _pwdCtrl.text,
        _nameCtrl.text.trim(),
        _codeCtrl.text.trim(),
        _csacUserCtrl.text.trim(),
        _csacPwdCtrl.text,
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(state.error ?? '注册失败')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 420;
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 12 : 24,
                vertical: compact ? 12 : 24,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Card(
                    elevation: 4,
                    child: Padding(
                      padding: EdgeInsets.all(compact ? 20 : 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Icon(
                            Icons.smart_toy,
                            size: compact ? 48 : 56,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'CsAC Open Platform',
                            textAlign: TextAlign.center,
                            style: textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            ['密码登录', '验证码登录', '创建账号'][_mode],
                            textAlign: TextAlign.center,
                            style: textTheme.bodyMedium?.copyWith(
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 20),
                          SegmentedButton<int>(
                            showSelectedIcon: false,
                            segments: [
                              ButtonSegment(
                                value: 0,
                                label: Text(compact ? '密码' : '密码登录'),
                              ),
                              ButtonSegment(
                                value: 1,
                                label: Text(compact ? '验证码' : '验证码登录'),
                              ),
                              const ButtonSegment(value: 2, label: Text('注册')),
                            ],
                            selected: {_mode},
                            onSelectionChanged: (v) =>
                                setState(() => _mode = v.first),
                          ),
                          const SizedBox(height: 20),
                          if (_mode == 2) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer.withValues(
                                  alpha: 0.3,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: colorScheme.outline.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.link,
                                    size: 18,
                                    color: colorScheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '需要绑定CsAC账号，请输入您的CsAC用户名和密码',
                                      style: textTheme.bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _csacUserCtrl,
                              decoration: const InputDecoration(
                                labelText: 'CsAC 用户名',
                                prefixIcon: Icon(Icons.person_outline),
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _csacPwdCtrl,
                              obscureText: _obscureCsacPwd,
                              decoration: InputDecoration(
                                labelText: 'CsAC 密码',
                                prefixIcon: const Icon(Icons.lock_outline),
                                border: const OutlineInputBorder(),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureCsacPwd
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                  ),
                                  onPressed: () => setState(
                                    () => _obscureCsacPwd = !_obscureCsacPwd,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Divider(),
                            const SizedBox(height: 8),
                          ],
                          TextField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: '邮箱',
                              prefixIcon: Icon(Icons.email),
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_mode == 2) ...[
                            TextField(
                              controller: _nameCtrl,
                              decoration: const InputDecoration(
                                labelText: '开发者名称',
                                prefixIcon: Icon(Icons.badge),
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (_mode == 0 || _mode == 2) ...[
                            TextField(
                              controller: _pwdCtrl,
                              obscureText: _obscurePwd,
                              decoration: InputDecoration(
                                labelText: '平台密码',
                                prefixIcon: const Icon(Icons.lock),
                                border: const OutlineInputBorder(),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePwd
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                  ),
                                  onPressed: () => setState(
                                    () => _obscurePwd = !_obscurePwd,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (_mode == 1 || _mode == 2) ...[
                            if (compact) ...[
                              TextField(
                                controller: _codeCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: '邮箱验证码',
                                  prefixIcon: Icon(Icons.verified_user),
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 48,
                                child: FilledButton.tonal(
                                  onPressed: _countdown > 0 ? null : _sendCode,
                                  child: Text(
                                    _countdown > 0
                                        ? '${_countdown}s 后重发'
                                        : '发送验证码',
                                  ),
                                ),
                              ),
                            ] else ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _codeCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: '邮箱验证码',
                                        prefixIcon: Icon(Icons.verified_user),
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  SizedBox(
                                    width: 120,
                                    height: 56,
                                    child: FilledButton.tonal(
                                      onPressed: _countdown > 0
                                          ? null
                                          : _sendCode,
                                      child: Text(
                                        _countdown > 0
                                            ? '${_countdown}s'
                                            : '发送验证码',
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 12),
                          ],
                          Consumer<AppState>(
                            builder: (context, state, child) {
                              return SizedBox(
                                height: 48,
                                child: FilledButton(
                                  onPressed: state.loading ? null : _submit,
                                  child: state.loading
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Text(['登录', '登录', '注册'][_mode]),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
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
