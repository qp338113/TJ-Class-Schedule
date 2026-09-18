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
      // 课程卡片结果先解析出来：弹窗可能只成功一部分，失败的格子要靠它兜底。
      final cardRows = (payload['rows'] as List<Object?>? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map(
            (row) => TongjiTimetableRecord.fromJson(
              row.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .toList();
      // 再读「排课信息」浮层：星期来自标题、节次与周次来自每行，
      // 不需要用卡片位置去推算，因而不会出现位置错位。
      // 浮层需要光标移入才显示，只能逐格触发并读取。
      final popupRows = await _readPopupRows(payload['hoverTargets']);
      // 按格合并：弹窗成功的那几格用弹窗结果，其余保留卡片结果。
      // 避免“弹窗只成功几格”反而丢掉整片课程。
      final rows = mergePopupWithCards(popup: popupRows, cards: cardRows);
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

  /// 逐格触发「排课信息」浮层并读取文字，解析成导入记录。
  ///
  /// 网页靠光标移入显示该浮层（不是点击），因此这里派发鼠标事件，
  /// 等一小段时间让浮层渲染完再读。任何一格读不到都不影响其它格；
  /// 整体一条都解析不出来时返回空列表，由调用方回退到读课程卡片。
  Future<List<TongjiTimetableRecord>> _readPopupRows(Object? targets) async {
    if (targets is! List) return const [];
    final records = <TongjiTimetableRecord>[];
    // 同一格的浮层内容是一样的，重复触发既慢又容易读到上一格的残留，
    // 因此按「星期 + 节次」去重后只读一次。
    final visited = <String>{};
    for (final target in targets) {
      if (target is! Map) continue;
      final x = (target['x'] as num?)?.toInt();
      final y = (target['y'] as num?)?.toInt();
      final weekday = (target['weekday'] as num?)?.toInt() ?? 0;
      final targetStart = (target['startPeriod'] as num?)?.toInt() ?? 0;
      final targetEnd = (target['endPeriod'] as num?)?.toInt() ?? 0;
      if (x == null || y == null || weekday == 0 || targetStart == 0) continue;
      final key = '$weekday|$targetStart|$targetEnd';
      if (!visited.add(key)) continue;
      final script = _hoverTimetableTargetScript
          .replaceAll('__X__', '$x')
          .replaceAll('__Y__', '$y');
      final hovered = await _controller.runJavaScriptReturningResult(script);
      if (hovered.toString().replaceAll('"', '').trim() != 'true') continue;
      // 浮层是异步渲染的，等它出现再读。
      await Future<void>.delayed(const Duration(milliseconds: 220));
      final popupRaw = await _controller.runJavaScriptReturningResult(
        _readTimetablePopupScript,
      );
      final popup = _decodeJavaScriptResult(popupRaw);
      if (popup['found'] != true) continue;
      final text = popup['text'];
      if (text is! String) continue;
      final parsed = parseTongjiPopupText(text);
      // 关键校验：浮层没来得及更新时读到的是上一格的内容。
      // 星期与节次都必须与本格吻合，否则整格作废、交给卡片结果兜底。
      // 只校验星期是不够的——同一天相邻两格会因此互相重复录入。
      if (parsed.isEmpty) continue;
      if (parsed.any((r) => r.weekday != weekday)) continue;
      if (parsed.any((r) => r.startPeriod > targetEnd || targetStart > r.endPeriod)) {
        continue;
      }
      records.addAll(parsed);
    }
    return records;
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
  // [周次] 的内容必须是周次写法，挡掉页面上其他方括号文字。
  const isWeekField = (value) =>
    /\d/.test(value) && /^[\d\s,，、\-—~～至第单双周()（）]+$/.test(value);
  // 文字层与彩色背景常常分属两层，向上找最近的有色容器。
  // 同一格叠放多门课时，格子（含两个 [周次]）会被排除，而每门课自己的文字层能被找到。
  const hasCardBackgroundNearby = (element) => {
    let node = element;
    for (let depth = 0; depth < 4 && node; depth++) {
      if (hasCourseCardBackground(node)) return true;
      node = node.parentElement || null;
    }
    return false;
  };
  const weekFieldOf = (value) => {
    const weekFields = value.match(/\[[^\]]+\]/g) || [];
    const courseCodes = value.match(/\([A-Za-z]{2,}[A-Za-z0-9_-]*\)/g) || [];
    if (weekFields.length !== 1 || courseCodes.length > 1) return null;
    const inner = weekFields[0].slice(1, -1);
    return isWeekField(inner) ? inner : null;
  };
  const matched = [];
  for (const element of scheduleElements) {
    const value = text(element);
    if (weekFieldOf(value) === null || !hasCardBackgroundNearby(element)) continue;
    matched.push({element, value, rect: element.getBoundingClientRect()});
  }
  // 同一张卡片的外层彩色盒子和内层文字层都会命中：文本相同，但盒子跨多个节次、
  // 文字层只有一行高，直接去重会留下两条。按面积从大到小只保留最外层那个。
  matched.sort(
    (a, b) => b.rect.width * b.rect.height - a.rect.width * a.rect.height,
  );
  const candidates = [];
  for (const candidate of matched) {
    const covered = candidates.some(
      (item) =>
        item.value === candidate.value &&
        item.rect.left <= candidate.rect.left + 1 &&
        item.rect.top <= candidate.rect.top + 1 &&
        item.rect.right >= candidate.rect.right - 1 &&
        item.rect.bottom >= candidate.rect.bottom - 1,
    );
    if (!covered) candidates.push(candidate);
  }
  // 周几列的左右边界，取相邻两列标题的中点。
  const weekdayBounds = weekdays.map((item, index) => ({
    weekday: item.weekday,
    left: index === 0
      ? item.x - (weekdays[1].x - weekdays[0].x) / 2
      : (weekdays[index - 1].x + item.x) / 2,
    right: index === weekdays.length - 1
      ? item.x + (item.x - weekdays[index - 1].x) / 2
      : (item.x + weekdays[index + 1].x) / 2,
  }));
  const sortedPeriods = [...periods].sort((a, b) => a.y - b.y);
  const periodFirst = sortedPeriods[0].y;
  const periodLast = sortedPeriods[sortedPeriods.length - 1].y;
  const rowHeight = sortedPeriods.length > 1
    ? (periodLast - periodFirst) / (sortedPeriods.length - 1)
    : 60;
  const rows = [];
  const seen = new Set();
  for (const candidate of candidates) {
    const element = candidate.element;
    const rect = candidate.rect;
    const centerX = rect.left + rect.width / 2;
    const centerY = rect.top + rect.height / 2;
    // 卡片必须落在某一周几列内，且宽度不超过一列，避免抓到左侧“第N节课”栏或跨列容器。
    const column = weekdayBounds.find((item) =>
      centerX >= item.left && centerX <= item.right && rect.width <= (item.right - item.left) * 1.5);
    if (!column) continue;
    // 纵向必须落在节次表范围内，挡掉课表区域上下边缘的说明文字。
    if (centerY < periodFirst - rowHeight / 2 || centerY > periodLast + rowHeight / 2) continue;
    const covered = sortedPeriods.filter((item) =>
      item.y >= rect.top - 3 && item.y <= rect.bottom + 3);
    if (covered.length === 0) continue;
    const startPeriod = Math.min(...covered.map((item) => item.period));
    const endPeriod = Math.max(...covered.map((item) => item.period));
    const value = candidate.value;
    const key = `${column.weekday}|${startPeriod}|${endPeriod}|${value}`;
    if (seen.has(key)) continue;
    seen.add(key);
    rows.push({text: value, weekday: column.weekday, startPeriod, endPeriod});
  }
  // 供“排课信息”弹窗抓取使用：hover 目标是「格子」本身（外层彩色盒），
  // 而不是格子里的小卡片——弹窗给出的是整格的排课信息。
  // 取含 [周次] 且带彩色背景、宽度不超过一周几列的元素，按面积从大到小保留最外层。
  const blockCandidates = scheduleElements.filter((element) =>
    /\[[^\]]+\]/.test(text(element)) && hasCourseCardBackground(element));
  blockCandidates.sort((a, b) => {
    const ra = a.getBoundingClientRect();
    const rb = b.getBoundingClientRect();
    return rb.width * rb.height - ra.width * ra.height;
  });
  const hoverRectList = [];
  const hoverTargets = [];
  for (const element of blockCandidates) {
    const rect = element.getBoundingClientRect();
    const centerX = rect.left + rect.width / 2;
    const centerY = rect.top + rect.height / 2;
    const column = weekdayBounds.find((item) =>
      centerX >= item.left && centerX <= item.right &&
      rect.width <= (item.right - item.left) * 1.5);
    if (!column) continue;
    if (centerY < periodFirst - rowHeight / 2 ||
        centerY > periodLast + rowHeight / 2) continue;
    if (hoverRectList.some((item) =>
      item.left <= rect.left + 1 && item.top <= rect.top + 1 &&
      item.right >= rect.right - 1 && item.bottom >= rect.bottom - 1)) continue;
    hoverRectList.push({
      left: rect.left, top: rect.top, right: rect.right, bottom: rect.bottom,
    });
    // 一并带上该格所在的星期与节次，供应用侧把弹窗结果与卡片结果按格对齐。
    const blockCovered = sortedPeriods.filter((item) =>
      item.y >= rect.top - 3 && item.y <= rect.bottom + 3);
    hoverTargets.push({
      x: Math.round(centerX),
      y: Math.round(centerY),
      weekday: column.weekday,
      startPeriod: blockCovered.length === 0
        ? 0
        : Math.min(...blockCovered.map((item) => item.period)),
      endPeriod: blockCovered.length === 0
        ? 0
        : Math.max(...blockCovered.map((item) => item.period)),
    });
  }
  return JSON.stringify({rows, hoverTargets});
})()
''';

// 把光标移到指定坐标，触发该格子的“排课信息”浮层。
//
// 网页显示排课信息靠的是鼠标移入（mouseenter/mouseover），不是点击，
// 所以这里派发鼠标移动事件而不是 click。三种事件都发一遍，
// 是因为不同前端框架监听的事件名不同。
const _hoverTimetableTargetScript = r'''
((x, y) => {
  const element = document.elementFromPoint(x, y);
  if (!element) return false;
  const options = {
    bubbles: true, cancelable: true, view: window,
    clientX: x, clientY: y,
  };
  for (const type of ['mouseover', 'mouseenter', 'mousemove']) {
    element.dispatchEvent(new MouseEvent(type, options));
  }
  return true;
})(__X__, __Y__)
''';

// 读取当前显示的“排课信息”浮层文字。
// 页面上可能同时存在多个含该字样的元素（外层容器 + 内层面板），
// 取文字最短的那个即为真正的面板内容。
const _readTimetablePopupScript = r'''
(() => {
  const visible = (element) => {
    const rect = element.getBoundingClientRect();
    const style = getComputedStyle(element);
    return rect.width > 0 && rect.height > 0 &&
      style.display !== 'none' && style.visibility !== 'hidden';
  };
  const hits = [...document.querySelectorAll('body *')]
    .filter(visible)
    .filter((element) => (element.innerText || '').includes('排课信息'));
  if (hits.length === 0) return JSON.stringify({found: false});
  hits.sort((a, b) =>
    (a.innerText || '').length - (b.innerText || '').length);
  return JSON.stringify({found: true, text: hits[0].innerText});
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
