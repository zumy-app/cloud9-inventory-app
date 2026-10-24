// Odoo hub: the rest of Odoo (POS checkout, backend) inside the app.
// Same login, no second sign-in: the Odoo session cookie is injected into
// the WebView cookie jar. A native "Scan to POS" button types a scanned
// barcode into whatever POS field is focused (with Enter).
library;

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../i18n/lang.dart';
import '../widgets/feedback.dart';
import 'scan.dart';

/// Entry hub: POS checkout + Odoo backend, same session.
class OdooHubScreen extends StatelessWidget {
  final String baseUrl;
  final String sessionCookie; // "session_id=..." from OdooClient
  const OdooHubScreen(
      {super.key, required this.baseUrl, this.sessionCookie = ''});

  String get _base => baseUrl.replaceAll(RegExp(r'/+$'), '');

  void _open(BuildContext context, String title, String url) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OdooWebViewScreen(
          title: title, url: url, sessionCookie: sessionCookie),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('hub_title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(t('hub_sub'), style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.point_of_sale,
                  size: 36, color: Color(0xFFF26522)),
              title: Text(t('hub_pos')),
              subtitle: Text(t('hub_pos_sub')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(context, t('hub_pos'), '$_base/pos/web'),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.dashboard_customize,
                  size: 36, color: Color(0xFF032561)),
              title: Text(t('hub_backend')),
              subtitle: Text(t('hub_backend_sub')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(context, t('hub_backend'), '$_base/web'),
            ),
          ),
          const SizedBox(height: 8),
          Text(t('hub_note'),
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }
}

class OdooWebViewScreen extends StatefulWidget {
  final String title;
  final String url;
  final String sessionCookie;
  const OdooWebViewScreen(
      {super.key,
      required this.title,
      required this.url,
      this.sessionCookie = ''});

  @override
  State<OdooWebViewScreen> createState() => _OdooWebViewScreenState();
}

class _OdooWebViewScreenState extends State<OdooWebViewScreen> {
  late final WebViewController _ctl;
  bool _ready = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _ctl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p / 100.0);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _ready = true);
        },
      ));
    _boot();
  }

  Future<void> _boot() async {
    // Inject the Odoo session so the WebView opens logged in.
    final m =
        RegExp(r'session_id=([^;]+)').firstMatch(widget.sessionCookie);
    if (m != null) {
      final host = Uri.parse(widget.url).host;
      await WebViewCookieManager().setCookie(WebViewCookie(
          name: 'session_id', value: m.group(1)!, domain: host, path: '/'));
    }
    await _ctl.loadRequest(Uri.parse(widget.url));
  }

  /// Scan with the phone camera, then type the code into the focused
  /// POS field + Enter. Falls back to a toast when POS has no field.
  Future<void> _scanToPos() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    final c = (code ?? '').trim();
    if (c.isEmpty || !mounted) return;
    const js = '''
(function(code){
  var el = document.activeElement;
  function focusable(){
    var i = document.querySelector("input[type=text], input:not([type]), input[type=search]");
    if (i) { i.focus(); return i; }
    return null;
  }
  if (!el || (el.tagName !== "INPUT" && el.tagName !== "TEXTAREA")) { el = focusable(); }
  if (!el) return "no-field";
  try {
    var proto = el.tagName === "TEXTAREA" ? window.HTMLTextAreaElement.prototype : window.HTMLInputElement.prototype;
    var setter = Object.getOwnPropertyDescriptor(proto, "value").set;
    setter.call(el, code);
  } catch (e) { el.value = code; }
  el.dispatchEvent(new Event("input", {bubbles: true}));
  el.dispatchEvent(new KeyboardEvent("keydown", {key: "Enter", code: "Enter", keyCode: 13, bubbles: true}));
  el.dispatchEvent(new KeyboardEvent("keyup", {key: "Enter", code: "Enter", keyCode: 13, bubbles: true}));
  return "ok";
})('%CODE%')''';
    final safe = c.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
    try {
      final out =
          await _ctl.runJavaScriptReturningResult(js.replaceAll('%CODE%', safe));
      if (!mounted) return;
      if (out.toString().contains('no-field')) {
        showErr(context, t('hub_nofield'));
      } else {
        showOk(context, '${t('hub_scanned')} $c');
      }
    } catch (_) {
      if (mounted) showErr(context, t('hub_scan_fail'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _ctl.reload()),
        ],
      ),
      body: Column(
        children: [
          if (_progress < 1.0) LinearProgressIndicator(value: _progress),
          Expanded(child: WebViewWidget(controller: _ctl)),
        ],
      ),
      floatingActionButton: _ready
          ? FloatingActionButton.extended(
              onPressed: _scanToPos,
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(t('hub_scan')),
            )
          : null,
    );
  }
}
