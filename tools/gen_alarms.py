#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成「日期 → 闹钟时间」对照表，供快捷指令直接查表。

背景
----
iOS 锁屏时禁止「打开 App / 打开 URL」，所以 `xiangke://apply` 那条路在锁屏必定失败；
「后台刷新」又由系统择机、实测三天都不一定跑一次。
但快捷指令的「开关闹钟」动作**不需要打开 App**，锁屏也能执行 ——
于是把「每天设哪个闹钟」拆成两半：

  准备（一次）：在时钟里建好固定的几个闹钟（课表里最早课只有 6 种时间）
  每天（自动）：快捷指令查这张表 → 打开该用的那个、关掉其余

快捷指令里没法做「取最小 start + 减提前量」这种计算，所以结果预先算好发布。

用法
----
    python gen_alarms.py <timetable.json> [-o alarms.json] [--from 2026-10-16]

输出格式（刻意压到最简，便于快捷指令一次取值）：
    {"2026-10-16": "13:30", "2026-10-17": "13:30", "2026-10-18": ""}
空字符串 = 当天无课（快捷指令据此把全部闹钟关掉）。
"""

import argparse
import collections
import datetime
import io
import json
import sys


def alarm_time(courses, advance):
    """该天的闹钟时间 HH:MM；无课返回 None"""
    if not courses:
        return None
    first = min(courses, key=lambda c: c['start'])
    h, m = (int(x) for x in first['start'].split(':'))
    total = max(0, h * 60 + m - advance)
    return '%02d:%02d' % (total // 60, total % 60)


def main():
    ap = argparse.ArgumentParser(description='生成快捷指令用的日期→闹钟时间对照表')
    ap.add_argument('timetable', help='课表 JSON（含 overrides / advanceMinutes）')
    ap.add_argument('-o', '--output', default='alarms.json', help='输出文件，默认 alarms.json')
    ap.add_argument('--from', dest='start', default=None,
                    help='起始日期 YYYY-MM-DD，默认取「明天」')
    args = ap.parse_args()

    with io.open(args.timetable, encoding='utf-8') as f:
        data = json.load(f)

    advance = int(data.get('advanceMinutes', 30))
    overrides = data.get('overrides', {})
    if not overrides:
        print('课表里没有 overrides —— 本工具只处理按日期写的课表', file=sys.stderr)
        return 1

    dated = sorted(datetime.date.fromisoformat(k) for k in overrides)
    start = datetime.date.fromisoformat(args.start) if args.start \
        else datetime.date.today() + datetime.timedelta(days=1)
    end = dated[-1]

    table = {}
    by_time = collections.Counter()
    day = start
    while day <= end:
        key = day.isoformat()
        t = alarm_time(overrides.get(key), advance)
        table[key] = t or ''
        if t:
            by_time[t] += 1
        day += datetime.timedelta(days=1)

    with io.open(args.output, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(table, f, ensure_ascii=False, sort_keys=True, separators=(',', ':'))
        f.write('\n')

    print('提前量：%d 分钟' % advance)
    print('覆盖 %s ~ %s，共 %d 天（其中 %d 天无课）'
          % (start, end, len(table), sum(1 for v in table.values() if not v)))
    print()
    print('时钟里需要预置的闹钟（共 %d 个）：' % len(by_time))
    for t, n in sorted(by_time.items()):
        print('   %s   用到 %d 天' % (t, n))
    print()
    print('已写出：%s' % args.output)
    return 0


if __name__ == '__main__':
    sys.exit(main())
