// 诊断：同格叠放多门课时，抓取脚本到底产出几条记录。
// 复用 dom_check.mjs 的模拟 DOM 手法，但只针对叠放格，单独跑。
import fs from 'node:fs';

import { fileURLToPath } from 'node:url';
import path from 'node:path';
// 相对脚本自身定位项目根目录，换机器/换路径后无需修改。
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const DART = path.join(ROOT, 'lib/presentation/tongji_timetable_page.dart');
const src = fs.readFileSync(DART, 'utf8');
const marker = "const _extractTimetableScript = r'''";
const s = src.indexOf(marker) + marker.length;
const script = src.slice(s, src.indexOf("''';", s));

class El {
  constructor(o = {}) {
    this.tag = o.tag || 'div';
    this.own = o.text || '';
    this.rect = o.rect;
    this.style = Object.assign(
      { display: 'block', visibility: 'visible', backgroundColor: 'rgba(0, 0, 0, 0)', backgroundImage: 'none' },
      o.style || {},
    );
    this.children = [];
  }
  add(...kids) { kids.forEach((k) => { k.parent = this; this.children.push(k); }); return this; }
  get parentElement() { return this.parent || null; }
  get innerText() {
    return [this.own, ...this.children.map((c) => c.innerText)].filter((t) => t !== '').join('\n');
  }
  getBoundingClientRect() {
    const r = this.rect;
    return { left: r.left, top: r.top, width: r.width, height: r.height, right: r.left + r.width, bottom: r.top + r.height };
  }
}

const flat = [];
const mk = (o) => { const e = new El(o); flat.push(e); return e; };
const box = (left, top, width, height) => ({ left, top, width, height });

const PURPLE = 'rgb(124, 92, 191)';
const LIGHT = 'rgb(247, 247, 252)';
const WEEKDAYS = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
const COL_W = 230;
const colLeft = (i) => 360 + i * COL_W;
const rowTop = (k) => 440 + (k - 1) * 56;

const root = mk({ tag: 'body', rect: box(0, 0, 1920, 1400) });
flat.push(mk({ text: '学生课表', rect: box(250, 370, 120, 24) }));
mk({ text: '节次/周次', rect: box(250, 400, 110, 30), style: { backgroundColor: LIGHT } });
WEEKDAYS.forEach((name, i) => {
  mk({ text: name, rect: box(colLeft(i), 400, COL_W, 30), style: { backgroundColor: LIGHT } });
});
for (let k = 1; k <= 11; k++) {
  const row = mk({ rect: box(250, rowTop(k), 1700, 56), style: { backgroundColor: LIGHT } });
  row.add(mk({ text: `第${k}节课`, rect: box(250, rowTop(k), 110, 56) }));
}

// 真实场景：周五 5-6 节一格叠放「工科导论(卓越计划班)」三段周次、三位老师。
// 浮层文本证实三条都是 [5-6节]；页面里这一格的外层盒子跨 5-6 节。
const CAD_LINES = [
  '王彦博(17112) 工科导论（卓越计划班）(QDC1902) [1-2, 15] 南310',
  '王浩祺(19072) 工科导论（卓越计划班）(QDC1902) [11-14, 16] 南310',
  '陈隽(99130) 工科导论（卓越计划班）(QDC1902) [3-10] 南310',
];
{
  const col = 4, startP = 5, endP = 6;
  const top = rowTop(startP);
  const height = (endP - startP + 1) * 56;
  const cellBox = box(colLeft(col) + 8, top, COL_W - 16, height);
  const cell = mk({ rect: cellBox, style: { backgroundColor: PURPLE } });
  // 三道课在格内等分高度
  CAD_LINES.forEach((text, i) => {
    const slice = box(cellBox.left, top + i * (height / CAD_LINES.length), cellBox.width, height / CAD_LINES.length);
    const inner = mk({ rect: slice });
    inner.add(mk({ text, rect: slice }));
    cell.add(inner);
    // 变体：文字层比彩色格更宽（长文本溢出），看是否导致重复
    const wide = mk({ rect: box(cellBox.left - 6, slice.top, cellBox.width + 12, slice.height) });
    wide.add(mk({ text, rect: box(cellBox.left - 6, slice.top, cellBox.width + 12, slice.height) }));
    cell.add(wide);
  });
  root.add(cell);
}

// 对照：周三 3-4 节一格两门课（线性代数A 与 高等数学B(I)），只放一层文字层
const WED_LINES = [
  '张莉(05139) 线性代数A(CMS1208) [2-16双] 南201',
  '颜启明(09118) 高等数学B(I)(CMS1221) [1, 3, 5, 7, 9, 11, 13, 15] 北301',
];
{
  const col = 2, startP = 3, endP = 4;
  const top = rowTop(startP);
  const height = (endP - startP + 1) * 56;
  const cellBox = box(colLeft(col) + 8, top, COL_W - 16, height);
  const cell = mk({ rect: cellBox, style: { backgroundColor: PURPLE } });
  WED_LINES.forEach((text, i) => {
    const slice = box(cellBox.left, top + i * (height / WED_LINES.length), cellBox.width * (i === 0 ? 0.5 : 0.5), height / WED_LINES.length);
    const shifted = box(cellBox.left + i * (cellBox.width / 2), top, cellBox.width / 2, height);
    const inner = mk({ rect: shifted });
    inner.add(mk({ text, rect: shifted }));
    cell.add(inner);
  });
  root.add(cell);
}

flat.push(mk({ text: '已选课程列表', rect: box(250, 1300, 150, 24) }));

const fakeDocument = { querySelectorAll: () => flat };
const result = new Function('document', 'getComputedStyle', `return (${script});`)(
  fakeDocument,
  (el) => el.style,
);
const payload = JSON.parse(result);

if (payload.error) {
  console.log('error:', payload.error);
} else {
  console.log('=== rows ===');
  for (const r of payload.rows) {
    console.log(`周${r.weekday} ${r.startPeriod}-${r.endPeriod} | ${r.text}`);
  }
  console.log(`共 ${payload.rows.length} 条`);
  console.log('\n=== hoverTargets(格) ===');
  for (const t of payload.hoverTargets) {
    console.log(`周${t.weekday} ${t.startPeriod}-${t.endPeriod} @(${t.x},${t.y})`);
  }
}
