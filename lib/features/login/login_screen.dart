import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../../core/api.dart';
import '../../core/auth.dart';
import '../../core/pkce.dart';
import '../../core/session.dart';

enum _Method { password, apiKey }

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _server = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _apiKey = TextEditingController();

  String? _baseUrl;
  ServerInfo? _info;
  _Method _method = _Method.password;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_server, _username, _password, _apiKey]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() task) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await task();
    } on PlatformException catch (e) {
      // CANCELED: the browser sheet was closed; nothing to report.
      if (e.code != 'CANCELED') setState(() => _error = e.message ?? e.code);
    } catch (e) {
      setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() => _run(() async {
    final url = normalizeServerUrl(_server.text);
    if (url.isEmpty) throw 'Enter your Grimoire address.';
    final info = await GrimoireApi.probe(url);
    if (!info.initialized) {
      throw 'This Grimoire hasn\'t been set up yet. Finish setup in a browser first.';
    }
    setState(() {
      _baseUrl = url;
      _info = info;
      _method = info.passwordAuth ? _Method.password : _Method.apiKey;
    });
  });

  Future<void> _signIn() => _run(() async {
    final url = _baseUrl!;
    final session = _method == _Method.password
        ? await GrimoireApi.login(url, _username.text.trim(), _password.text)
        : await GrimoireApi.loginWithApiKey(url, _apiKey.text.trim());
    await ref.read(authProvider.notifier).signIn(session);
  });

  /// OIDC in the system browser: Grimoire sends the browser back to
  /// `grimoire://oauth` with a one-time code bound to our PKCE challenge.
  Future<void> _signInWithSso() => _run(() async {
    final url = _baseUrl!;
    final pkce = Pkce.generate();
    final state = randomToken(32);
    final result = await FlutterWebAuth2.authenticate(
      url: GrimoireApi.oidcLoginUrl(url, challenge: pkce.challenge, state: state).toString(),
      callbackUrlScheme: oidcCallbackScheme,
    );
    final params = Uri.parse(result).queryParameters;
    if (params['state'] != state) throw 'Sign-in was interrupted. Please try again.';
    final error = params['error'];
    if (error != null) throw error;
    final code = params['code'];
    if (code == null) throw 'Grimoire did not finish the sign-in.';
    final session = await GrimoireApi.exchangeOidcCode(url, code, pkce.verifier);
    await ref.read(authProvider.notifier).signIn(session);
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SvgPicture.asset('assets/grimoire-logo-circle.svg', height: 96),
                    const SizedBox(height: 16),
                    Text(
                      'Grimoire',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Connect to your own Grimoire server.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 32),
                    if (_info == null) ..._serverStep() else ..._signInStep(theme),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _serverStep() => [
    TextField(
      controller: _server,
      keyboardType: TextInputType.url,
      autocorrect: false,
      textInputAction: TextInputAction.go,
      autofillHints: const [AutofillHints.url],
      decoration: const InputDecoration(
        labelText: 'Server address',
        hintText: 'grimoire.example.com',
        prefixIcon: Icon(Icons.dns_outlined),
      ),
      onSubmitted: (_) => _connect(),
    ),
    const SizedBox(height: 16),
    FilledButton(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      onPressed: _busy ? null : _connect,
      child: _busy ? const _Spinner() : const Text('Continue'),
    ),
  ];

  List<Widget> _signInStep(ThemeData theme) {
    final info = _info!;
    return [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.dns_outlined),
        title: Text(Uri.parse(_baseUrl!).host),
        trailing: TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                  _info = null;
                  _error = null;
                }),
          child: const Text('Change'),
        ),
      ),
      if (info.loginMessage != null && info.loginMessage!.isNotEmpty) ...[
        Text(info.loginMessage!, style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
      ],
      if (info.oidc && info.oidcMobile) ...[
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          icon: const Icon(Icons.key),
          label: Text(
            (info.oidcButtonText?.isNotEmpty ?? false) ? info.oidcButtonText! : 'Sign in with SSO',
          ),
          onPressed: _busy ? null : _signInWithSso,
        ),
        const SizedBox(height: 20),
      ] else if (info.oidc) ...[
        Text(
          'This server uses single sign-on but doesn\'t support it from the app yet. '
          'Update Grimoire, or sign in with an API key from Settings → Connections.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
      ],
      SegmentedButton<_Method>(
        segments: [
          if (info.passwordAuth)
            const ButtonSegment(value: _Method.password, label: Text('Password')),
          const ButtonSegment(value: _Method.apiKey, label: Text('API key')),
        ],
        selected: {_method},
        onSelectionChanged: (s) => setState(() => _method = s.first),
      ),
      const SizedBox(height: 16),
      if (_method == _Method.password) ...[
        TextField(
          controller: _username,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username],
          decoration: const InputDecoration(labelText: 'Username'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          textInputAction: TextInputAction.go,
          autofillHints: const [AutofillHints.password],
          decoration: const InputDecoration(labelText: 'Password'),
          onSubmitted: (_) => _signIn(),
        ),
      ] else
        TextField(
          controller: _apiKey,
          autocorrect: false,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'API key',
            hintText: 'grim_…',
            helperText: 'Create one in Grimoire under Settings → Connections → API Keys.',
            helperMaxLines: 2,
          ),
          onSubmitted: (_) => _signIn(),
        ),
      const SizedBox(height: 16),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        onPressed: _busy ? null : _signIn,
        child: _busy ? const _Spinner() : const Text('Sign in'),
      ),
    ];
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) =>
      const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2));
}
