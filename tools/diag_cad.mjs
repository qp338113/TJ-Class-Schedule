// 诊断：同一格三条排课（CAD）在不同 DOM 结构下能否被抓到。
// A：三行各是一个元素；B：三行同在一个元素里（innerText 带换行）；
// C：三行同在一个元素里且不含换行。
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

const box = (left, top, width, height) => ({ left, top, width, height });
const PURPLE = 'rgb(124, 92, 191)';
const LIGHT = 'rgb(247, 247, 252)';
const WEEKDAYS = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
const COL_W = 230;
const colLeft = (i) => 360 + i * COL_W;
const rowTop = (k) => 440 + (k - 1) * 56;

const CAD = [
  '徐俊(07196) Auto CAD工程制图(CCE0901) [10] 土木学院机房',
  '张博珊(19633) Auto CAD工程制图(CCE0901) [3-9] 土木学院机房',
  '徐骁青(21030) Auto CAD工程制图(CCE0901) [1-2, 11-12] 土木学院机房',
];

function build(variant) {
  const flat = [];
  const mk = (o) => { const e = new El(o); flat.push(e); return e; };
  const root = mk({ rect: box(0, 0, 1920, 1400) });
  flat.push(mk({ text: '学生课表', rect: box(250, 370, 120, 24) }));
  flat.push(mk({ text: '已选课程列表', rect: box(250, 1300, 150, 24) }));
  mk({ text: '节次/周次', rect: box(250, 400, 110, 30), style: { backgroundColor: LIGHT } });
  WEEKDAYS.forEach((name, i) => {
    mk({ text: name, rect: box(colLeft(i), 400, COL_W, 30), style: { backgroundColor: LIGHT } });
  });
  for (let k = 1; k <= 11; k++) {
    mk({ text: `第${k}节课`, rect: box(250, rowTop(k), 110, 56) });
  }
  const col = 3, startP = 5, endP = 6;
  const top = rowTop(startP);
  const height = (endP - startP + 1) * 56;
  const cellBox = box(colLeft(col) + 8, top, COL_W - 16, height);
  const cell = mk({ rect: cellBox, style: { backgroundColor: PURPLE } });
  if (variant === 'A') {
    CAD.forEach((text, i) => {
      const slice = box(cellBox.left, top + i * (height / CAD.length), cellBox.width, height / CAD.length);
      cell.add(mk({ text, rect: slice }));
    });
  } else if (variant === 'B') {
    cell.add(mk({ text: CAD.join('\n'), rect: cellBox }));
  } else {
    cell.add(mk({ text: CAD.join(''), rect: cellBox }));
  }
  root.add(cell);
  return flat;
}

for (const variant of ['A', 'B', 'C']) {
  const flat = build(variant);
  const result = new Function('document', 'getComputedStyle', `return (${script});`)(
    { querySelectorAll: () => flat },
    (el) => el.style,
  );
  const payload = JSON.parse(result);
  console.log(`\n=== 变体 ${variant} ===`);
  if (payload.error) { console.log('  error:', payload.error); continue; }
  console.log(`  rows=${payload.rows.length}`);
  for (const r of payload.rows) console.log(`    周${r.weekday} ${r.startPeriod}-${r.endPeriod} | ${r.text.slice(0, 48)}`);
  console.log(`  hoverTargets=${payload.hoverTargets.length}`);
  for (const t of payload.hoverTargets) console.log(`    周${t.weekday} ${t.startPeriod}-${t.endPeriod} @(${t.x},${t.y})`);
}
