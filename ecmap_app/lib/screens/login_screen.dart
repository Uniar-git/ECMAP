import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _loginEmail = TextEditingController();
  final _loginPass = TextEditingController();
  final _regEmail = TextEditingController();
  final _regPass = TextEditingController();
  final _regPassConfirm = TextEditingController();
  String? _error;
  bool _loading = false;

  bool get _isWindows => !kIsWeb && Platform.isWindows;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() => setState(() => _error = null));
  }

  @override
  void dispose() {
    _tabs.dispose();
    _loginEmail.dispose();
    _loginPass.dispose();
    _regEmail.dispose();
    _regPass.dispose();
    _regPassConfirm.dispose();
    super.dispose();
  }

  String _translateError(FirebaseAuthException e) {
    const messages = {
      'user-not-found': 'メールアドレスが見つかりません',
      'wrong-password': 'パスワードが間違っています',
      'invalid-credential': 'メールアドレスまたはパスワードが正しくありません',
      'email-already-in-use': 'このメールアドレスは既に使用されています',
      'weak-password': 'パスワードは6文字以上にしてください',
      'invalid-email': 'メールアドレスの形式が正しくありません',
      'too-many-requests': 'しばらく時間をおいてから再試行してください',
      'network-request-failed': 'ネットワークエラーが発生しました',
    };
    return messages[e.code] ?? 'エラーが発生しました (${e.code})';
  }

  Future<void> _run(Future<void> Function() fn) async {
    setState(() { _loading = true; _error = null; });
    try {
      await fn();
    } on FirebaseAuthException catch (e) {
      if (e.code != 'popup-closed-by-user' && mounted) {
        setState(() => _error = _translateError(e));
      }
    } catch (_) {
      // user cancelled
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _login() => _run(
        () => AuthService.signInWithEmail(
            _loginEmail.text.trim(), _loginPass.text),
      );

  void _register() {
    if (_regPass.text != _regPassConfirm.text) {
      setState(() => _error = 'パスワードが一致しません');
      return;
    }
    _run(() => AuthService.signUpWithEmail(
        _regEmail.text.trim(), _regPass.text));
  }

  void _loginWithGoogle() => _run(AuthService.signInWithGoogle);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ECMAP',
                  style: GoogleFonts.spaceMono(
                    fontSize: 40,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accentBlue,
                    letterSpacing: 6,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'eSports Cognitive-Motor\nAssessment Platform',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 13, height: 1.6),
                ),
                const SizedBox(height: 32),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TabBar(
                          controller: _tabs,
                          tabs: const [
                            Tab(text: 'ログイン'),
                            Tab(text: '新規登録'),
                          ],
                          indicatorColor: AppColors.accentBlue,
                          labelColor: AppColors.accentBlue,
                          unselectedLabelColor: AppColors.textSecondary,
                          dividerColor: AppColors.border,
                        ),
                        const SizedBox(height: 20),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          child: [
                            _EmailPasswordForm(
                              emailCtrl: _loginEmail,
                              passCtrl: _loginPass,
                              submitLabel: 'ログイン',
                              onSubmit: _loading ? null : _login,
                            ),
                            _RegisterForm(
                              emailCtrl: _regEmail,
                              passCtrl: _regPass,
                              confirmCtrl: _regPassConfirm,
                              onSubmit: _loading ? null : _register,
                            ),
                          ][_tabs.index],
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          _ErrorBanner(message: _error!),
                        ],
                        if (!_isWindows) ...[
                          const SizedBox(height: 16),
                          const _Divider(),
                          const SizedBox(height: 16),
                          _GoogleButton(
                              onPressed: _loading ? null : _loginWithGoogle),
                        ],
                      ],
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

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _EmailPasswordForm extends StatelessWidget {
  final TextEditingController emailCtrl;
  final TextEditingController passCtrl;
  final String submitLabel;
  final VoidCallback? onSubmit;

  const _EmailPasswordForm({
    required this.emailCtrl,
    required this.passCtrl,
    required this.submitLabel,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'メールアドレス'),
          onSubmitted: (_) => onSubmit?.call(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: passCtrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'パスワード'),
          onSubmitted: (_) => onSubmit?.call(),
        ),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: onSubmit, child: Text(submitLabel)),
      ],
    );
  }
}

class _RegisterForm extends StatelessWidget {
  final TextEditingController emailCtrl;
  final TextEditingController passCtrl;
  final TextEditingController confirmCtrl;
  final VoidCallback? onSubmit;

  const _RegisterForm({
    required this.emailCtrl,
    required this.passCtrl,
    required this.confirmCtrl,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'メールアドレス'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: passCtrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'パスワード'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: confirmCtrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'パスワード（確認）'),
          onSubmitted: (_) => onSubmit?.call(),
        ),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: onSubmit, child: const Text('登録する')),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.accentRed.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.accentRed.withOpacity(0.4)),
      ),
      child: Text(message,
          style: const TextStyle(color: AppColors.accentRed, fontSize: 13)),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Row(children: [
      Expanded(child: Divider(color: AppColors.border)),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Text('または',
            style:
                TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ),
      Expanded(child: Divider(color: AppColors.border)),
    ]);
  }
}

class _GoogleButton extends StatelessWidget {
  final VoidCallback? onPressed;
  const _GoogleButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Text('G',
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary)),
      label: const Text('Googleでログイン'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.border),
        minimumSize: const Size.fromHeight(44),
      ),
    );
  }
}
