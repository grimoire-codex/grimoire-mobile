import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/auth.dart';
import '../../core/models.dart';
import 'host_bridge.dart';

/// A character sheet, drawn by Grimoire's own sheet renderer.
///
/// Sheets carry their own layout and stylesheet (a phone-sized
/// `mobile.html`/`mobile.css` when the sheet has one), plus formulas, pick
/// grants and the content catalog, all of which the web renderer already
/// implements. The app hosts it and supplies the session over the bridge in
/// `host_bridge.dart`.
class SheetScreen extends ConsumerStatefulWidget {
  const SheetScreen({super.key, required this.characterId, this.preview});

  final String characterId;
  final Character? preview;

  @override
  ConsumerState<SheetScreen> createState() => _SheetScreenState();
}

class _SheetScreenState extends ConsumerState<SheetScreen> {
  WebViewController? _controller;
  double _progress = 0;
  bool _outdatedServer = false;

  String get _baseUrl => ref.read(apiProvider)!.baseUrl;
  Uri get _sheetUrl => Uri.parse('$_baseUrl/characters/${widget.characterId}');

  @override
  void initState() {
    super.initState();
    final session = ref.read(authProvider);
    if (session != null && !session.usesApiKey) _start();
  }

  Future<void> _start() async {
    await _setSessionCookie(ref.read(apiProvider)?.session.accessToken);
    final broker = HostTokenBroker(ref.read(apiProvider)!);
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent);
    await controller.addJavaScriptChannel(
      hostChannelName,
      onMessageReceived: (message) => _onHostMessage(controller, broker, message.message),
    );
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p / 100);
        },
        onNavigationRequest: _onNavigate,
        onPageFinished: (_) async {
          final aware = await controller.runJavaScriptReturningResult(hostAwareCheck);
          if (aware != true && aware != 'true' && mounted) {
            setState(() => _outdatedServer = true);
          }
        },
      ),
    );
    await controller.loadRequest(_sheetUrl);
    if (mounted) setState(() => _controller = controller);
  }

  Future<void> _onHostMessage(
    WebViewController controller,
    HostTokenBroker broker,
    String raw,
  ) async {
    switch (HostMessage.parse(raw)) {
      case TokenRequest(:final id, :final reason):
        final token = await broker.token(reason);
        if (token != null) await _setSessionCookie(token);
        await controller.runJavaScript(replyScript(id, token));
      case CloseRequest():
        if (mounted) Navigator.of(context).maybePop();
      case null:
        break;
    }
  }

  /// Portraits and images load through plain image requests, which Grimoire
  /// authenticates with the `grimoire_session` cookie.
  Future<void> _setSessionCookie(String? token) async {
    if (token == null) return;
    await WebViewCookieManager().setCookie(
      WebViewCookie(name: 'grimoire_session', value: token, domain: Uri.parse(_baseUrl).host),
    );
  }

  Future<NavigationDecision> _onNavigate(NavigationRequest request) async {
    final url = Uri.tryParse(request.url);
    final base = Uri.parse(_baseUrl);
    if (url == null || (url.host == base.host && url.port == base.port)) {
      return NavigationDecision.navigate;
    }
    // A link off the server (a rules homepage, an attribution) opens outside.
    await launchUrl(url, mode: LaunchMode.externalApplication);
    return NavigationDecision.prevent;
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authProvider);
    final title = widget.preview?.name ?? 'Character';

    if (session?.usesApiKey ?? false) {
      return _Notice(
        title: title,
        message:
            'Character sheets need a password or single sign-on session. '
            'Sign in that way to open sheets in the app.',
        sheetUrl: _sheetUrl,
      );
    }
    if (_outdatedServer) {
      return _Notice(
        title: title,
        message:
            'This Grimoire is too old to show sheets inside the app. '
            'Update Grimoire, or open the sheet in your browser.',
        sheetUrl: _sheetUrl,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        bottom: _progress < 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress, minHeight: 2),
              )
            : null,
      ),
      body: _controller == null
          ? const Center(child: CircularProgressIndicator())
          : WebViewWidget(controller: _controller!),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.title, required this.message, required this.sheetUrl});

  final String title;
  final String message;
  final Uri sheetUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.badge_outlined, size: 48),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => launchUrl(sheetUrl, mode: LaunchMode.externalApplication),
                child: const Text('Open in browser'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
