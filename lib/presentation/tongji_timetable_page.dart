import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../import/tongji_timetable_import.dart';
import '../import/tongji_login_redirect.dart';
import 'import_preview_page.dart';

class TongjiTimetablePage extends StatefulWidget {
  const TongjiTimetablePage({super.key});

  @override
  State<TongjiTimetablePage> createState() => _TongjiTimetablePageState();
}

class _TongjiTimetablePageState extends State<TongjiTimetablePage> {
  static final _timetableUri = Uri.parse(
    'https://1.tongji.edu.cn/GraduateStudentTimeTable',
  );
  static const _parser = TongjiTimetableImportParser();
  static const _desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/131.0.0.0 Safari/537.36';

  late final WebViewController _controller;
  var _progress = 0;
  var _reading = false;
  var _desktopMode = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_desktopUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) => setState(() => _progress = progress),
          onNavigationRequest: _upgradeInsecureTongjiRedirect,
          onPageFinished: _preparePage,
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) {
              _showMessage('网页加载失败，请检查网络后重试');
            }
          },
        ),
      )
      ..loadRequest(_timetableUri);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('从同济1系统导入'),
        actions: [
          IconButton(
            tooltip: _desktopMode ? '切换到手机模式' : '切换到电脑模式',
            onPressed: _toggleDesktopMode,
            icon: Icon(
              _desktopMode
                  ? Icons.desktop_windows_outlined
                  : Icons.phone_android_outlined,
            ),
          ),
          IconButton(
            tooltip: '重新加载',
            onPressed: _controller.reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') _clearLogin();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'logout', child: Text('退出并清除登录信息')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_progress < 100) LinearProgressIndicator(value: _progress / 100),
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                '请在下方完成同济统一认证。默认使用电脑模式加载完整课表；登录页面不好操作时，可点右上角电脑图标切换。',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: FilledButton.icon(
          onPressed: _reading ? null : _readTimetable,
          icon: _reading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.table_view_rounded),
          label: Text(_reading ? '正在读取' : '读取当前课表'),
        ),
      ),
    );
  }

  Future<void> _readTimetable() async {
    setState(() => _reading = true);
    try {
      final currentUrl = await _controller.currentUrl();
      if (currentUrl == null ||
          !currentUrl.startsWith(_timetableUri.toString())) {
        _showMessage('请先完成登录，并等待“学生课表”页面显示出来');
        return;
      }
      final raw = await _controller.runJavaScriptReturningResult(
        _extractTimetableScript,
      );
      final payload = _decodeJavaScriptResult(raw);
      final error = payload['error'] as String?;
      if (error != null) {
        _showMessage(error);
        return;
      }
      final rows = (payload['rows'] as List<Object?>? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map(
            (row) => TongjiTimetableRecord.fromJson(
              row.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .toList();
      if (rows.isEmpty) {
        _showMessage('没有识别到课程卡片，请确认网页已完整显示课表');
        return;
      }
      if (!mounted) return;
      final imported = await Navigator.push<bool>(
        context,
        MaterialPageRoute<bool>(
          builder: (_) => ImportPreviewPage(
            initialPreview: _parser.parse(rows),
            title: '同济课表预览',
          ),
        ),
      );
      if (imported == true && mounted) {
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        _showMessage('课表读取失败，网站结构可能已经变化，请稍后重试');
      }
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  NavigationDecision _upgradeInsecureTongjiRedirect(NavigationRequest request) {
    final secureUri = upgradeTongjiLoginRedirect(request.url);
    if (secureUri == null) return NavigationDecision.navigate;
    unawaited(_controller.loadRequest(secureUri));
    return NavigationDecision.prevent;
  }

  Future<void> _toggleDesktopMode() async {
    setState(() => _desktopMode = !_desktopMode);
    await _controller.setUserAgent(_desktopMode ? _desktopUserAgent : null);
    await _controller.reload();
    if (mounted) {
      _showMessage(_desktopMode ? '已切换到电脑模式' : '已切换到手机模式');
    }
  }

  Future<void> _preparePage(String url) async {
    if (!_desktopMode || !url.contains('GraduateStudentTimeTable')) return;
    await _controller.runJavaScript(_forceDesktopLayoutScript);
  }

  Map<String, Object?> _decodeJavaScriptResult(Object raw) {
    Object? decoded = jsonDecode(raw.toString());
    if (decoded is String) decoded = jsonDecode(decoded);
    return (decoded as Map<Object?, Object?>).map(
      (key, value) => MapEntry(key.toString(), value),
    );
  }

  Future<void> _clearLogin() async {
    await WebViewCookieManager().clearCookies();
    await _controller.clearCache();
    await _controller.clearLocalStorage();
    await _controller.loadRequest(_timetableUri);
    if (mounted) _showMessage('网页登录信息已清除');
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

// 根据网页中周几标题和节次行的位置，确定每张课程卡片所在的格子。
const _extractTimetableScript = r'''
(() => {
  const visible = (element) => {
    const rect = element.getBoundingClientRect();
    const style = getComputedStyle(element);
    return rect.width > 0 && rect.height > 0 &&
      style.display !== 'none' && style.visibility !== 'hidden';
  };
  const text = (element) => (element.innerText || '')
    .replace(/\s+/g, ' ').trim();
  const elements = [...document.querySelectorAll('body *')].filter(visible);
  const smallestExactText = (value) => elements
    .filter((element) => text(element) === value)
    .sort((a, b) => {
      const aRect = a.getBoundingClientRect();
      const bRect = b.getBoundingClientRect();
      return aRect.width * aRect.height - bRect.width * bRect.height;
    })[0];
  const scheduleTitle = smallestExactText('学生课表');
  const selectedListTitle = smallestExactText('已选课程列表');
  if (!scheduleTitle || !selectedListTitle) {
    return JSON.stringify({error: '没有找到完整的学生课表区域，请等待页面加载完成后重试'});
  }
  const scheduleTop = scheduleTitle.getBoundingClientRect().top;
  const scheduleBottom = selectedListTitle.getBoundingClientRect().top;
  const scheduleElements = elements.filter((element) => {
    const rect = element.getBoundingClientRect();
    return rect.top >= scheduleTop - 2 && rect.bottom <= scheduleBottom + 2;
  });
  const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日']
    .map((name, index) => {
      const matches = scheduleElements.filter((element) => text(element) === name);
      const element = matches.sort((a, b) =>
        a.getBoundingClientRect().width - b.getBoundingClientRect().width)[0];
      if (!element) return null;
      const rect = element.getBoundingClientRect();
      return {weekday: index + 1, x: rect.left + rect.width / 2};
    }).filter(Boolean);
  const periods = scheduleElements.map((element) => {
    const match = /^第\s*(\d+)\s*节课$/.exec(text(element));
    if (!match) return null;
    const rect = element.getBoundingClientRect();
    return {period: Number(match[1]), y: rect.top + rect.height / 2,
      width: rect.width};
  }).filter(Boolean).sort((a, b) => a.width - b.width)
    .filter((item, index, all) =>
      index === all.findIndex((other) => other.period === item.period));
  if (weekdays.length !== 7 || periods.length === 0) {
    return JSON.stringify({error: '网页课表还没有完整显示，请等待加载完成后重试'});
  }
  const hasCourseCardBackground = (element) => {
    const style = getComputedStyle(element);
    if (style.backgroundImage && style.backgroundImage !== 'none') return true;
    const channels = style.backgroundColor.match(/[\d.]+/g);
    if (!channels || channels.length < 3) return false;
    const red = Number(channels[0]);
    const green = Number(channels[1]);
    const blue = Number(channels[2]);
    const alpha = channels.length > 3 ? Number(channels[3]) : 1;
    return alpha > 0 && Math.max(red, green, blue) - Math.min(red, green, blue) > 25;
  };
  const candidates = scheduleElements.filter((element) => {
    const value = text(element);
    const weekFields = value.match(/\[[^\]]+\]/g) || [];
    const courseCodes = value.match(/\([A-Za-z]{2,}[A-Za-z0-9_-]*\)/g) || [];
    if (weekFields.length !== 1 || courseCodes.length !== 1) {
      return false;
    }
    return hasCourseCardBackground(element);
  });
  const rows = [];
  const seen = new Set();
  for (const element of candidates) {
    const rect = element.getBoundingClientRect();
    const centerX = rect.left + rect.width / 2;
    const weekday = weekdays.reduce((best, item) =>
      Math.abs(item.x - centerX) < Math.abs(best.x - centerX) ? item : best);
    const covered = periods.filter((item) =>
      item.y >= rect.top - 3 && item.y <= rect.bottom + 3);
    if (covered.length === 0) continue;
    const startPeriod = Math.min(...covered.map((item) => item.period));
    const endPeriod = Math.max(...covered.map((item) => item.period));
    const value = text(element);
    const key = `${weekday.weekday}|${startPeriod}|${endPeriod}|${value}`;
    if (seen.has(key)) continue;
    seen.add(key);
    rows.push({text: value, weekday: weekday.weekday, startPeriod, endPeriod});
  }
  return JSON.stringify({rows});
})()
''';

// 让响应式网页保留完整的周一到周日列，抓取不依赖手机屏幕当前可见范围。
const _forceDesktopLayoutScript = r'''
(() => {
  let viewport = document.querySelector('meta[name="viewport"]');
  if (!viewport) {
    viewport = document.createElement('meta');
    viewport.name = 'viewport';
    document.head.appendChild(viewport);
  }
  viewport.content = 'width=1920, initial-scale=0.35, user-scalable=yes';
  document.documentElement.style.minWidth = '1920px';
  document.body.style.minWidth = '1920px';
})()
''';
