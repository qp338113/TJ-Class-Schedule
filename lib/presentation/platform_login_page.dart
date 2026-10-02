import 'dart:async';
import 'dart:convert';
import '../data/platform_task_client.dart';
import 'task_guide_page.dart';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PlatformLoginResult {
  const PlatformLoginResult(this.token, [this.ticket]);
  final String token;
  final String? ticket;
}

class PlatformLoginPage extends StatefulWidget {
  const PlatformLoginPage({super.key, required this.platform});
  final String platform;

  @override
  State<PlatformLoginPage> createState() => _PlatformLoginPageState();
}

class _PlatformLoginPageState extends State<PlatformLoginPage> {
  static final _canvas = Uri.parse(
    'https://canvas.tongji.edu.cn/profile/settings',
  );
  static final _haoke = Uri.parse('https://tongji.aihaoke.net/student/course');
  final _manualToken = TextEditingController();
  late final WebViewController _web = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..loadRequest(widget.platform == 'canvas' ? _canvas : _haoke);
  bool _reading = false;
  final _client = PlatformTaskClient();

  @override
  void dispose() {
    _client.close();
    unawaited(
      _web.loadRequest(Uri.parse('about:blank')).catchError((Object _) {}),
    );
    _manualToken.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    setState(() => _reading = true);
    try {
      final url = Uri.tryParse(await _web.currentUrl() ?? '');
      final host = widget.platform == 'canvas' ? _canvas.host : _haoke.host;
      if (!(widget.platform == 'canvas' &&
              _manualToken.text.trim().isNotEmpty) &&
          (url?.scheme != 'https' || url?.host != host || url?.port != 443)) {
        throw const FormatException('请先在官方页面完成登录');
      }
      final result = widget.platform == 'canvas'
          ? PlatformLoginResult(await _readCanvasToken())
          : await _readHaokeCredentials();
      if (result.token.isEmpty) {
        throw const FormatException('当前页面没有可读取的新令牌，请先生成或手工粘贴');
      }
      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('保存平台连接？'),
          content: Text(
            '已读取 ${widget.platform == 'canvas' ? 'Canvas' : '好课'} 凭证。将仅加密保存到这台手机，不显示完整内容。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认导入'),
            ),
          ],
        ),
      );
      if (confirm == true && mounted) Navigator.pop(context, result);
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on PlatformRequestException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('读取失败：请确认已登录并在官方页面生成新令牌，或稍后重试。')),
        );
      }
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<String> _readCanvasToken() async {
    if (_manualToken.text.trim().isNotEmpty) return _manualToken.text.trim();
    const script = r'''(() => {
      if (location.origin !== 'https://canvas.tongji.edu.cn') return '';
      const visible = element => !!(element.offsetWidth || element.offsetHeight || element.getClientRects().length);
      for (const dialog of document.querySelectorAll('[role="dialog"], .ui-dialog')) {
        if (!visible(dialog)) continue;
        for (const field of dialog.querySelectorAll('input, textarea, code, pre')) {
          if (!visible(field)) continue;
          const value = (field.value || field.textContent || '').trim();
          if (/^[0-9]+~[A-Za-z0-9._~-]{20,}$/.test(value)) return value;
        }
      }
      return '';
    })()''';
    final raw = await _web.runJavaScriptReturningResult(script);
    return _decodeString(raw);
  }

  Future<PlatformLoginResult> _readHaokeCredentials() async {
    const script = r'''(() => {
      if (location.origin !== 'https://tongji.aihaoke.net') return '';
      const stored = sessionStorage.getItem('haoke-token');
      const cookie = document.cookie.split('; ').find(x => x.startsWith('haoke-token='));
      return stored || (cookie ? decodeURIComponent(cookie.slice('haoke-token='.length)) : '');
    })()''';
    final token = _decodeString(
      await _web.runJavaScriptReturningResult(script),
    );
    if (token.isEmpty || token.length > 4096) {
      throw const FormatException('好课登录信息未就绪');
    }
    final pair = await _client.readHaokeCredentials(token);
    return PlatformLoginResult(pair.token, pair.ticket);
  }

  String _decodeString(Object raw) {
    if (raw is! String) return raw.toString();
    try {
      return jsonDecode(raw) as String;
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.platform == 'canvas' ? '连接 Canvas' : '连接好课'),
      actions: [
        IconButton(
          tooltip: 'Token 导入教程',
          icon: const Icon(Icons.help_outline),
          onPressed: () => Navigator.push<void>(
            context,
            MaterialPageRoute(builder: (_) => const TaskGuidePage()),
          ),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            widget.platform == 'canvas'
                ? '在下方官方设置页登录并生成个人访问令牌；生成后点“读取并确认”。已隐藏的旧令牌无法恢复，可在下方手工粘贴。'
                : '在下方好课官方页面正常登录，登录完成后点“读取并确认”。不会读取密码。',
          ),
        ),
        if (widget.platform == 'canvas')
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _manualToken,
              obscureText: true,
              maxLength: 2048,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: '或粘贴新生成的 Canvas 令牌'),
            ),
          ),
        Expanded(child: WebViewWidget(controller: _web)),
        SafeArea(
          minimum: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: _reading ? null : _read,
            child: Text(_reading ? '读取中' : '读取并确认'),
          ),
        ),
      ],
    ),
  );
}
