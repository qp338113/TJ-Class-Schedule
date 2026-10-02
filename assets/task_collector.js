// Self-contained function: Chrome serializes it into the active tab's isolated world.
// Read rendered DOM only. No cookies, storage, request interception or remote requests.
function collectVisibleTasks() {
  const host = location.hostname;
  let platform = host === 'tongji.aihaoke.net' ? 'haoke' : (host === 'chaoxing.com' || host.endsWith('.chaoxing.com')) ? 'chaoxing' : host.endsWith('.polymas.com') || host === 'polymas.com' || host.endsWith('.zhihuishu.com') ? 'polymas' : host === 'canvas.tongji.edu.cn' ? 'canvas' : host === '192.168.180.213' ? 'oj' : ['127.0.0.1','localhost'].includes(host) ? 'manual' : '';
  if (!platform) throw new Error('请在已登录的教学平台作业列表或课集试验页使用。');
  const visible = el => el.getClientRects().length > 0 && getComputedStyle(el).visibility !== 'hidden' && getComputedStyle(el).display !== 'none';
  const cleanUrl = raw => {
    try {
      const u = new URL(raw, location.href);
      if (!['http:','https:'].includes(u.protocol) || u.username || u.password || u.origin !== location.origin) return '';
      // Keep only known navigation identifiers, not unknown signed or session parameters.
      const allowed = /^(courseid|clazzid|cpi|instanceId|taskType|columnId|uniqueId|id|taskId|assignmentId)$/i;
      for (const key of [...u.searchParams.keys()]) if (!allowed.test(key)) u.searchParams.delete(key);
      u.hash = ''; return u.href;
    } catch { return ''; }
  };
  const candidates = []; const seen = new Set();
  let course = '';
  const breadcrumbs = [...document.querySelectorAll('.el-breadcrumb__inner,.ant-breadcrumb-link,[aria-label="breadcrumb"] a,[aria-label="面包屑"] a')].filter(visible);
  course = breadcrumbs.map(el=>el.innerText.trim()).find(text=>text.length>2&&!/^(首页|展开导航|作业|当前任务|课程|学习任务)$/.test(text)) || '';
  // Haoke uses clickable div/span titles rather than anchors. Match each visible
  // submission interval, then ascend to the smallest row containing its status.
  const datePart = '(?:\\d{4}[-/.年])?\\d{1,2}[-/.月]\\d{1,2}日?\\s+\\d{1,2}:\\d{2}';
  const interval = new RegExp('提交\\s*[:：]\\s*('+datePart+')\\s*(?:-|~|至|—)\\s*('+datePart+')');
  const isHaoke = platform === 'haoke' || (platform === 'manual' && location.pathname === '/collector-haoke-demo');
  if (isHaoke) {
    const leaves = [...document.querySelectorAll('main *,[role="main"] *,body div,body span,body td,body li,body p')].slice(0,12000).filter(el=>visible(el)&&(el.innerText||'').length<700&&interval.test(el.innerText||''));
    const handled = new Set();
    for (const leaf of leaves) {
      let row = leaf;
      for (let depth=0;row&&depth<8;depth++,row=row.parentElement) {
        const text = row.innerText?.trim() || '';
        if (text.length>1800) break;
        const ranges = text.match(new RegExp(interval.source,'g')) || [];
        if (ranges.length>1) break;
        if (!ranges.length || !/(待提交|已完成|已提交|未开始|待完成)/.test(text)) continue;
        if (handled.has(row)) break;
        const match = text.match(interval);
        const prefix = text.slice(0,match.index).split(/\n/).map(line=>line.trim().replace(/\s*(必做|选做)\s*$/,'').trim()).filter(Boolean);
        const title = prefix.find(line=>line.length>=3&&!/^(任务名称|状态|操作|去学习|答题统计|必做|选做)$/.test(line));
        if (!title) continue;
        const anchor=[...row.querySelectorAll('a[href]')].find(a=>visible(a)&&cleanUrl(a.getAttribute('href')));
        const url=anchor?cleanUrl(anchor.getAttribute('href')):cleanUrl(location.href);
        const state = text.match(/待提交|已完成|已提交|未开始|待完成/)?.[0] || '';
        const key=url+'|'+title;handled.add(row);
        if (!seen.has(key)) {
          seen.add(key);
          candidates.push({title:title.slice(0,200),course,platform:platform==='manual'?'haoke':platform,dueAt:null,url,rangeStart:match[1],rangeEnd:match[2],selected:!['已完成','已提交'].includes(state),note:`页面提交时间：${match[1]} - ${match[2]}\n页面状态：${state}。请核对截止年份；跳转链接可能打开本课程作业列表。`});
        }
        break;
      }
      if(candidates.length>=50)break;
    }
  }
  const anchors = isHaoke&&candidates.length ? [] : [...document.querySelectorAll('a[href]')].filter(visible).slice(0,1500);
  for (const a of anchors) {
    const title = a.innerText?.trim().replace(/\s+/g,' ').slice(0,200);
    if (!title || title.length < 3 || /^(作业|任务|测验|考试|全部作业|我的作业|提交作业|返回|首页|课程列表)$/.test(title)) continue;
    const container = a.closest('tr,li,article,[data-keji-task],.task-item,.homework-item,.assignment,.list-item') || a.parentElement;
    const text = container?.innerText?.trim() || title;
    const raw = a.getAttribute('href') || '';
    if (!/(作业|实验|练习|测验|习题|assignment|homework|quiz|task|任务)/i.test(title+' '+raw)) continue;
    if (text.length > 1800) continue; // Never export entire page or huge sections.
    const url = cleanUrl(raw); if (!url || seen.has(url+'|'+title)) continue;
    seen.add(url+'|'+title);
    const deadlineText = text.match(/(?:截止(?:时间|日期)?|结束时间|due(?:\s+date)?)[：:\s]*([^\n]{0,65})/i)?.[1]?.trim() || '';
    // No inferred year/date/status: user reviews a deadline clue before importing.
    candidates.push({title,course,platform,dueAt:null,url,note:deadlineText ? `页面截止时间线索：${deadlineText}（待核对）` : '页面未识别到截止时间，请在原平台核对。'});
    if (candidates.length >= 50) break;
  }
  return {version:1,platform,course,capturedAt:new Date().toISOString(),pageUrl:cleanUrl(location.href),tasks:candidates};
}
