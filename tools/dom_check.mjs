// 用模拟 DOM 运行同济课表抓取脚本，验证只会抓到课表区域内的真实课程卡片。
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
const GRAY = 'rgb(200, 200, 200)';
const WEEKDAYS = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
const COL_W = 230;
const colLeft = (i) => 360 + i * COL_W;
const colCenter = (i) => colLeft(i) + COL_W / 2;
const rowTop = (k) => 440 + (k - 1) * 56;
const rowCenter = (k) => rowTop(k) + 28;

const root = mk({ tag: 'body', rect: box(0, 0, 1920, 1200) });

// 侧边栏（在“学生课表”上方，不应被抓取）
root.add(mk({ text: '我的选课 [1-16]', rect: box(20, 300, 180, 28), style: { backgroundColor: PURPLE } }));

// 筛选条件区（上方）
root.add(mk({ text: '筛选条件', rect: box(360, 410, 200, 40) }));
root.add(mk({ text: '学年学期: 2026-2027学年第1学期', rect: box(360, 430, 400, 32) }));

// 课表标题：抓取区域的上下边界
flat.push(mk({ text: '学生课表', rect: box(250, 370, 120, 24) }));

// 表头行
mk({ text: '节次/周次', rect: box(250, 400, 110, 30), style: { backgroundColor: LIGHT } });
WEEKDAYS.forEach((name, i) => {
  mk({ text: name, rect: box(colLeft(i), 400, COL_W, 30), style: { backgroundColor: LIGHT } });
});

// 节次标签列 + 行容器
for (let k = 1; k <= 11; k++) {
  const row = mk({ rect: box(250, rowTop(k), 1700, 56), style: { backgroundColor: LIGHT } });
  row.add(mk({ text: `第${k}节课`, rect: box(250, rowTop(k), 110, 56) }));
}

// 真实课程卡片：研究生的格式（无课程代码，周次外多一层圆括号）
const cards = [
  ['周舒威 高等地下结构([1-16]彰武北大楼 209) 四平路校区', 0, 3, 4],
  ['黄忠凯 土木工程的韧性分析([1-16]彰武北大楼 309) 四平路校区', 0, 5, 6],
  ['钱杨 学术英语写作III([4, 6, 8, 10, 12, 14]) 四平路校区，', 2, 3, 4],
  ['钱杨 学术英语写作III([1-3, 5, 7, 9, 11, 13, 15-16]彰武北大楼 409) 四平路校区', 2, 3, 4],
  ['万立明 中国马克思主义与当代([2, 4, 6, 8, 10, 12, 14, 16]彰武南大楼 117) 四平路校区', 2, 5, 8],
  ['吕玺琳 岩土弹塑性力学([1-11]彰武北大楼 312) 四平路校区', 2, 9, 11],
  ['陈素琴 数值分析([1-16]彰武北大楼 301) 四平路校区', 3, 3, 4],
  ['乔亚飞 土木工程研究进展与研究方法([1-16]校本部土木大楼 A楼 101) 四平路校区', 3, 5, 6],
  ['张东明 地下结构最优化方法([1-16]彰武北大楼 209) 四平路校区', 4, 3, 4],
];
// 本科生格式（带课程代码）：截图二完整课表，含课程名以 (数字) 结尾与全角括号
const undergradCards = [
  // 周一
  ['樊维佳(14211) 大学物理B2(I)(PSE122601) [2-16双] 瑞安楼阶1', 0, 1, 2],
  ['冯辉(93761) 体育(1)(DPE110120) [1-16] 综合训练馆羽毛球馆', 0, 3, 4],
  ['张弢(00100) 高等数学B(I)(CMS122113) [1, 3, 5, 7, 9, 11, 13, 15] 南229', 0, 5, 6],
  ['李洁(10001) 高级语言程序设计A1(CST121607) [1-16] 南413', 0, 7, 8],
  ['张磊(22210) 线性代数B(CMS120609) [1-16] 北229', 0, 9, 10],
  // 周二
  ['许家烨(21087) 大学生国家安全教育 (CMA110504) [9, 16] 北329', 1, 5, 6],
  ['孙毅(22161) 形势与政策(1) (CMA111629) [7-10] 南301', 1, 7, 8],
  // 周三
  ['李洁(10001) 高级语言程序设计A1(CST121607) [1-16] 南413', 2, 1, 2],
  ['朱锡明(04041) 中国文化英语概论I(SFS121404) [1-16] 北416', 2, 3, 4],
  // 周四
  ['樊维佳(14211) 大学物理B2(I)(PSE122601) [1-16] 南129', 3, 1, 2],
  ['张弢(00100) 高等数学B(I)(CMS122113) [1-16] 南329', 3, 3, 4],
  ['姚莉萍(07154) 习近平新时代中国特色社会主义思想概论 (CMA111201) [1-16] 一教126', 3, 5, 6],
  ['杨小勇(10026) 宏观经济学 (CMA001101) [1-12] 北210', 3, 9, 10],
  // 周五
  ['张弢(00100) 高等数学B(I)(CMS122113) [1-16] 南329', 4, 1, 2],
  ['赫丽(00770) 大学物理实验B2(I) (PSE124105) [1-16] 物理馆2-4楼', 4, 3, 4],
  ['王鑫(21075) 大学美育(CAM001603) [1, 3, 5, 7, 9, 11, 13, 15] 线上课堂', 4, 7, 8],
  ['罗红杰(21109) 社会实践(CMA110903) [1-16] 线上课堂', 4, 9, 10],
];
// 同一格叠放两门课（星标区域，共两处）
const stackedCells = [
  {
    col: 2, startP: 7, endP: 10,
    items: [
      '阮青松(05137) 货币金融学(CEM050201) [1-6] 北210',
      '郭英(06067) 货币金融学(CEM050201) [1-6] 北210',
    ],
  },
  {
    col: 2, startP: 9, endP: 10,
    items: [
      '朱宏明(05117) 专业导论（计算机与电气类）(EIE190101) [12] 北201',
      '李云辉(06107) 专业导论（计算机与电气类）(EIE190101) [12] 北201',
    ],
  },
];
const allCards = [...cards, ...undergradCards];
for (const [text, col, startP, endP] of allCards) {
  const top = rowTop(startP);
  const height = endP * 56 - (startP - 1) * 56;
  // 嵌套结构：外层单元格（有色）> 内层文字层（无色），模拟真实页面的三层 DOM
  const cell = mk({ rect: box(colLeft(col) + 8, top, COL_W - 16, height), style: { backgroundColor: PURPLE } });
  const inner = mk({ rect: box(colLeft(col) + 8, top, COL_W - 16, height) });
  const textLayer = mk({ text, rect: box(colLeft(col) + 8, top, COL_W - 16, height) });
  inner.add(textLayer);
  cell.add(inner);
  root.add(cell);
}

// ★ 星标区域：同一格叠放多门课，格子含多个 [周次]
// 旧逻辑：格子 weekFields>1 被排除；内层文字层无背景色也被排除 → 完全检索不到
for (const { col, startP, endP, items } of stackedCells) {
  const top = rowTop(startP);
  const height = (endP - startP + 1) * 56;
  const cell = mk({ rect: box(colLeft(col) + 8, top, COL_W - 16, height), style: { backgroundColor: PURPLE } });
  items.forEach((text, i) => {
    const slice = box(colLeft(col) + 8, top + i * (height / items.length), COL_W - 16, height / items.length);
    const inner = mk({ rect: slice });
    const textLayer = mk({ text, rect: slice });
    inner.add(textLayer);
    cell.add(inner);
  });
  root.add(cell);
}

// 诱饵 1：落在节次标签列里的彩色方括号元素（旧逻辑会漏，靠列判定挡住）
flat.push(mk({
  text: '学期[1-16]说明', rect: box(255, 700, 100, 40), style: { backgroundColor: PURPLE },
}));
// 诱饵 2：方括号里不是周次（靠周次内容判定挡住）
flat.push(mk({
  text: '[点击查看详情]', rect: box(colLeft(5) + 20, 700, 190, 40), style: { backgroundColor: PURPLE },
}));
// 诱饵 3：两个课程代码（说明抓到了合并容器）
flat.push(mk({
  text: '合并课程 (ABC101) (DEF102) [1-16] 某地', rect: box(colLeft(5) + 20, 760, 190, 40), style: { backgroundColor: PURPLE },
}));
// 诱饵 4：滚动条（灰色、无文字）
flat.push(mk({ rect: box(1870, 440, 8, 616), style: { backgroundColor: GRAY } }));
// 诱饵 5：在周几列内、有色祖先，但位于表头之上（靠纵向边界挡住）
{
  const wrap = mk({ rect: box(colLeft(5), 330, COL_W, 40), style: { backgroundColor: PURPLE } });
  wrap.add(mk({ text: '注意事项 [1-16] 请按时上课', rect: box(colLeft(5), 330, COL_W, 40) }));
  root.add(wrap);
}
// 诱饵 6：文字层自身跨多列（靠列宽判定挡住）
{
  const rowWrap = mk({ rect: box(colLeft(0), rowTop(6), COL_W * 7, 56), style: { backgroundColor: PURPLE } });
  rowWrap.add(mk({ text: '本周调休说明 [1-16]', rect: box(colLeft(0), rowTop(6), COL_W * 7, 56) }));
  root.add(rowWrap);
}

// 深层嵌套的真实卡片：验证“向上找有色容器”在嵌套较深时仍能命中
{
  const col = 6, startP = 5, endP = 6;
  const top = rowTop(startP);
  const height = endP * 56 - (startP - 1) * 56;
  const slice = box(colLeft(col) + 8, top, COL_W - 16, height);
  const outer = mk({ rect: slice, style: { backgroundColor: PURPLE } }); // 有色卡盒在最外层
  let node = outer;
  for (let i = 0; i < 5; i++) { // 中间套 5 层无色包装
    const child = mk({ rect: slice });
    node.add(child);
    node = child;
  }
  node.add(mk({ text: '深层老师(1234) 深层嵌套课程 (DEEP101) [1-16] 深楼 1', rect: slice }));
  root.add(outer); // 挂最外层，保持父子链完整
}

// 回归：外层彩色盒子跨 3-4 节、内层文字层只有一行高，两者文本相同。
// 曾因尺寸不同导致去重键不同而重复识别两次（同一节课出现 2 条）。
{
  const col = 1, startP = 3, endP = 4;
  const top = rowTop(startP);
  const cell = mk({
    rect: box(colLeft(col) + 8, top, COL_W - 16, 56 * 2),
    style: { backgroundColor: PURPLE },
  });
  const wrapper = mk({ rect: box(colLeft(col) + 8, top, COL_W - 16, 56 * 2) });
  wrapper.add(mk({
    text: '重复检测师(9999) 重复检测课程 (DUP101) [1-16] 复楼 2',
    rect: box(colLeft(col) + 8, top + 10, COL_W - 16, 40), // 仅一行文字高
  }));
  cell.add(wrapper);
  root.add(cell);
}

// 复现：一格内拼了多门课（文字层合并），cell 文本里出现多个 [周次]。
// 旧实现要求“有且只有一个 [周次]”，这种格子会被整块丢弃 → 整格课程缺失，
// 真实反馈是「周四 5-6 节 Auto CAD 制图三段周次三位老师，常整格识别不到」。
// 现在按下一条的「教师(工号)」为边界逐条切开，格内每门课都要能读到。
const mergedCellGroups = [
  {
    col: 2, startP: 7, endP: 10,
    items: [
      '李汶军(07169) 普通化学实验A2(CSE121608) [2-16双]工程试验馆503',
      '孙淑娴(15176) 普通化学(CSM122901) [1,3,5,7,9,11,13,15] 南229',
    ],
  },
  {
    col: 4, startP: 5, endP: 6,
    items: [
      '钱啸宇(06059) 专业导论(理工试验班)(PSE190103) [5] 北116',
      '郭英(06792) 专业导论(理工试验班)(PSE190103) [1,3,5,7,9,11,13,15] 北116',
      '胡军(06122) 专业导论(理工试验班)(PSE190103) [1-4] 北116',
    ],
  },
];
for (const { col, startP, endP, items } of mergedCellGroups) {
  const top = rowTop(startP);
  const height = (endP - startP + 1) * 56;
  const slice = box(colLeft(col) + 8, top, COL_W - 16, height);
  const cell = mk({ rect: slice, style: { backgroundColor: PURPLE } });
  cell.add(mk({ text: items.join(' '), rect: slice }));
  root.add(cell);
}

// 下边界标题
flat.push(mk({ text: '已选课程列表', rect: box(250, 1100, 150, 24) }));
// 诱饵 5：下方“已选课程列表”里的课程条目（靠纵向边界挡住）
mk({ text: '高等数学B [1-16] 姚勤 (CMS122103)', rect: box(260, 1140, 400, 36), style: { backgroundColor: PURPLE } });

const fakeDocument = { querySelectorAll: () => flat };
const result = new Function('document', 'getComputedStyle', `return (${script});`)(
  fakeDocument,
  (el) => el.style,
);
const payload = JSON.parse(result);

console.log('=== 抓取结果 ===');
if (payload.error) {
  console.log('error:', payload.error);
} else {
  for (const r of payload.rows) {
    console.log(`周${r.weekday} ${r.startPeriod}-${r.endPeriod}节 | ${r.text}`);
  }
  console.log(`共 ${payload.rows.length} 条`);
}

const expectedRows = allCards.map(([text, col, s2, e2]) => `周${col + 1} ${s2}-${e2}节 | ${text}`);
// 深层嵌套卡片（有色卡盒在最外层，中间 5 层无色包装）
expectedRows.push('周7 5-6节 | 深层老师(1234) 深层嵌套课程 (DEEP101) [1-16] 深楼 1');
// 重复检测：同一节课只能出现一次（外层盒子与内层文字层尺寸不同，曾重复成 2 条）
expectedRows.push('周2 3-4节 | 重复检测师(9999) 重复检测课程 (DUP101) [1-16] 复楼 2');
// 叠放格：节次由「格子」决定，格内每门课都属于该格覆盖的节次。
//
// 这里曾经按「文字层自身高度」分摊节次，把期望值写成每门课各占一段，
// 于是把 5-5 / 6-6 这类互不重叠的错误区间当成了正确行为，回归测不出问题。
// 实际上同一个蓝方框里的课程共享该格的节次（弹窗也按格给出 [5-6节]），
// 且格内中间那段若按自身高度去数，会因没压住任何节次中心而被整条丢弃。
for (const { col, startP, endP, items } of stackedCells) {
  for (const text of items) {
    expectedRows.push(`周${col + 1} ${startP}-${endP}节 | ${text}`);
  }
}
// 一格内拼了多门课（文字层合并，含多个 [周次]）：格内每门课都要读到，
// 且节次由「格子」决定，所以每门课都取该格覆盖的节次。
for (const { col, startP, endP, items } of mergedCellGroups) {
  for (const text of items) {
    expectedRows.push(`周${col + 1} ${startP}-${endP}节 | ${text}`);
  }
}
const got = payload.rows.map((r) => `周${r.weekday} ${r.startPeriod}-${r.endPeriod}节 | ${r.text}`);
const missing = expectedRows.filter((e) => !got.includes(e));
const extra = got.filter((g) => !expectedRows.includes(g));
console.log('\n=== 校验 ===');
console.log('漏抓:', missing.length === 0 ? '无' : missing);
console.log('多抓:', extra.length === 0 ? '无' : extra);
process.exit(missing.length === 0 && extra.length === 0 ? 0 : 1);
