#!/bin/bash
# DeepSeek 备份重命名：把 chat_sessions 里以 id 命名的文件，按 chat_session_index.json 的标题改名。
# 用法：把导出的备份文件夹放到本脚本所在的文件夹里，双击本文件。可以反复运行，已改过名的会自动跳过。
cd "$(dirname "$0")" || exit 1
if ! command -v python3 >/dev/null 2>&1; then
  echo "没有找到 python3，无法运行。请先安装 Python 3。"
  read -n 1 -s -r -p "按任意键关闭…"
  exit 1
fi
python3 - "$PWD" <<'PY'
import csv, json, os, sys, unicodedata
from collections import Counter

ROOT = sys.argv[1]
INDEX = 'chat_session_index.json'
MAP = '重命名对照表.csv'
RESERVED = {'CON', 'PRN', 'AUX', 'NUL'} | {f'COM{i}' for i in range(1, 10)} | {f'LPT{i}' for i in range(1, 10)}
HEADER = ['id', '标题', '新文件名', '附件文件夹', '创建时间', '更新时间']


def clean(title):
    """把标题变成可以当文件名用的文字。"""
    t = unicodedata.normalize('NFC', str(title or ''))
    t = ''.join('_' if (c in '\\/:*?"<>|' or ord(c) < 32) else c for c in t).strip().lstrip('.').strip()
    t = t[:80].rstrip(' .')
    if not t:
        t = '未命名对话'
    if t.upper() in RESERVED:          # Windows 的保留名，改掉以便备份能拷到 Windows 上
        t = '_' + t
    return t


def key(name):
    return unicodedata.normalize('NFC', name).casefold()


def stamp(s):
    s = str(s or '')
    return f"{s[:10]} {s[11:13]}{s[14:16]}" if len(s) >= 16 else s[:10]


def process(folder):
    with open(os.path.join(folder, INDEX), encoding='utf-8') as f:
        index = json.load(f)
    cs = os.path.join(folder, 'chat_sessions')
    existing = {key(n) for n in os.listdir(cs)}

    rows = {}
    map_path = os.path.join(folder, MAP)
    if os.path.exists(map_path):
        with open(map_path, encoding='utf-8-sig', newline='') as f:
            for r in list(csv.reader(f))[1:]:
                if r:
                    rows[r[0]] = (r + [''] * 6)[:6]

    dup = Counter(key(clean(x.get('title'))) for x in index)
    used = {key(r[2][:-5]) for r in rows.values() if r[2].endswith('.json')}
    renamed = 0
    for x in index:
        sid = x['id']
        src_json = os.path.join(cs, sid + '.json')
        src_dir = os.path.join(cs, sid + '_files')
        has_json, has_dir = os.path.isfile(src_json), os.path.isdir(src_dir)
        if not has_json and not has_dir:
            continue
        if sid in rows and rows[sid][2].endswith('.json'):
            base = rows[sid][2][:-5]          # 之前已经定过名字，沿用
        else:
            base = clean(x.get('title'))
            if dup[key(base)] > 1:
                base = f"{base} ({stamp(x.get('inserted_at'))})"

            def taken(b):
                return key(b) in used or key(b + '.json') in existing or key(b + '_files') in existing

            if taken(base) and dup[key(clean(x.get('title')))] <= 1:
                base = f"{base} ({stamp(x.get('inserted_at'))})"
            if taken(base):
                base = f"{base} [{sid[:8]}]"
        used.add(key(base))
        dst_json = os.path.join(cs, base + '.json')
        dst_dir = os.path.join(cs, base + '_files')
        files_name = rows.get(sid, [''] * 6)[3]
        if has_json:
            if os.path.exists(dst_json):
                print(f"  跳过（目标已存在）：{base}.json")
                continue
            os.rename(src_json, dst_json)
            existing.add(key(base + '.json'))
            renamed += 1
        if has_dir:
            if os.path.exists(dst_dir):
                print(f"  跳过（目标已存在）：{base}_files")
            else:
                os.rename(src_dir, dst_dir)
                existing.add(key(base + '_files'))
                files_name = base + '_files'
        rows[sid] = [sid, x.get('title', ''), base + '.json', files_name, x.get('inserted_at', ''), x.get('updated_at', '')]

    if renamed or not os.path.exists(map_path):
        order = [x['id'] for x in index if x['id'] in rows]
        order += [i for i in rows if i not in set(order)]
        with open(map_path, 'w', encoding='utf-8-sig', newline='') as f:
            w = csv.writer(f)
            w.writerow(HEADER)
            w.writerows(rows[i] for i in order)
    return renamed, len(index)


def is_backup(p):
    return os.path.isfile(os.path.join(p, INDEX)) and os.path.isdir(os.path.join(p, 'chat_sessions'))


folders = [ROOT] if is_backup(ROOT) else []
folders += sorted(os.path.join(ROOT, n) for n in os.listdir(ROOT)
                  if not n.startswith('.') and is_backup(os.path.join(ROOT, n)))
if not folders:
    print('这里没有找到 DeepSeek 备份文件夹（需要包含 chat_session_index.json 和 chat_sessions）。')
total = 0
for p in folders:
    try:
        n, count = process(p)
    except Exception as e:  # 一个备份出错不影响其他备份
        print(f"✗ {os.path.basename(p)}：出错了 —— {e}")
        continue
    total += n
    print(f"✓ {os.path.basename(p)}：共 {count} 个对话，本次重命名 {n} 个" + ('' if n else '（已经全部改过名）'))
print(f"\n完成，本次一共重命名 {total} 个对话。对照表在每个备份文件夹里的「{MAP}」。")
PY
echo
read -n 1 -s -r -p "按任意键关闭窗口…"
echo
