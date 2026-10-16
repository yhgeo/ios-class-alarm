#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成「响课 · 开关闹钟」快捷指令（未签名 XML plist）。

它做什么
--------
每天 22:00 被自动化唤起时：
  1. 从 Gist 取「日期 → 闹钟时间」对照表（alarms.json）
  2. 算出明天的日期字符串（yyyy-MM-dd）
  3. 查表得到明天该用的闹钟时间
  4. 关掉全部 6 个「课表 HH:MM」闹钟
  5. 6 个「如果」互相独立：时间匹配哪个，就把哪个打开

关键：全程不打开任何 App，所以**锁屏时也能跑**。

⚠️ 需要导入后手动补的一处
----------------------
「开关闹钟」动作里的**闹钟选择器是设备相关的**（存的是你手机里那个闹钟的引用），
没法预先写死。所以导入后要逐个点开那 12 个「开关闹钟」，从列表里选对应闹钟：

    第 1~6 个（关闭）：课表 07:50 / 09:45 / 10:00 / 13:30 / 15:25 / 18:00
    第 7~12 个（打开，在各自的「如果」里）：同上，一一对应

除这一处外，UUID、变量引用、条件分组都已接好。

用法
----
    python tools/make_shortcut.py -o XiangKeAlarms.shortcut
"""

import argparse
import plistlib
import uuid

# 对照表的 raw 地址（不带 revision，永远指向最新版）
TABLE_URL = ("https://gist.githubusercontent.com/yhgeo/"
             "a1319b6b00cf0cd73c19a4b7f0d47fb8/raw/alarms.json")

# 6 个固定闹钟时间（= 课表里 6 种最早课时间各减 30 分钟）
ALARM_TIMES = ["07:50", "09:45", "10:00", "13:30", "15:25", "18:00"]


def U() -> str:
    return str(uuid.uuid4()).upper()


def ref_output(action_uuid: str, output_name: str) -> dict:
    """指向前一个动作输出的「魔法变量」引用"""
    return {
        "Value": {
            "OutputUUID": action_uuid,
            "OutputName": output_name,
            "Type": "ActionOutput",
        },
        "WFSerializationType": "WFTextTokenAttachment",
    }


def text_string(s: str) -> dict:
    return {"Value": {"string": s}, "WFSerializationType": "WFTextTokenString"}


def quantity(number: int, unit_seconds: int) -> dict:
    return {
        "Value": {"Number": number, "Unit": unit_seconds},
        "WFSerializationType": "WFQuantityFieldValue",
    }


actions: list = []


def emit(identifier: str, params: dict = None, output_name: str = None) -> str:
    p = dict(params or {})
    uid = U()
    p["UUID"] = uid
    if output_name:
        p["CustomOutputName"] = output_name
    actions.append({
        "WFWorkflowActionIdentifier": identifier,
        "WFWorkflowActionParameters": p,
    })
    return uid


# ---------------------------------------------------------------- 1. 取表
fetch = emit(
    "is.workflow.actions.downloadurl",
    {"WFURL": TABLE_URL, "WFHTTPMethod": "GET"},
    output_name="对照表内容",
)

# ---------------------------------------------------------------- 2. 解析成字典
dict_uid = emit(
    "is.workflow.actions.detect.dictionary",
    {"WFInput": ref_output(fetch, "Contents of URL")},
    output_name="对照表",
)

# ---------------------------------------------------------------- 3. 今天
today = emit(
    "is.workflow.actions.date",
    {"WFDateActionMode": "Current Date"},
    output_name="今天",
)

# ---------------------------------------------------------------- 4. +1 天
tomorrow = emit(
    "is.workflow.actions.adjustdate",
    {
        "WFInput": ref_output(today, "Date"),
        "WFAdjustOperation": "Add",
        "WFDuration": quantity(1, 86400),   # 1 天
    },
    output_name="明天",
)

# ---------------------------------------------------------------- 5. 格式化成 yyyy-MM-dd
key_uid = emit(
    "is.workflow.actions.format.date",
    {
        "WFInput": ref_output(tomorrow, "Adjusted Date"),
        "WFDateFormatStyle": "Custom",
        "WFDateFormat": "yyyy-MM-dd",
    },
    output_name="日期键",
)

# ---------------------------------------------------------------- 6. 查表
lookup = emit(
    "is.workflow.actions.getvalueforkey",
    {
        "WFInput": ref_output(dict_uid, "Dictionary"),
        "WFDictionaryKey": ref_output(key_uid, "Formatted Date"),
        "WFGetDictionaryValueType": "Value",
    },
    output_name="闹钟时间",
)

# ---------------------------------------------------------------- 7. 先全部关掉
# WFAlarm 留空 —— 闹钟引用是设备相关的，导入后由用户逐个选
for t in ALARM_TIMES:
    emit(
        "is.workflow.actions.alarm.toggle",
        {"WFEnabled": False},
        output_name=f"关闭 {t}",
    )

# ---------------------------------------------------------------- 8. 匹配的打开
# 6 个互相独立的「如果」，不要嵌套
for t in ALARM_TIMES:
    grp = U()
    emit("is.workflow.actions.conditional", {
        "GroupingIdentifier": grp,
        "WFControlFlowMode": 0,          # 0 = 如果
        "WFCondition": 4,                # 4 = 「是」
        "WFInput": {"Variable": ref_output(lookup, "Dictionary Value")},
        "WFConditionalActionString": t,
    })
    emit(
        "is.workflow.actions.alarm.toggle",
        {"WFEnabled": True},
        output_name=f"打开 {t}",
    )
    emit("is.workflow.actions.conditional", {
        "GroupingIdentifier": grp,
        "WFControlFlowMode": 2,          # 2 = 结束如果
    })


# ---------------------------------------------------------------- 顶层
shortcut = {
    "WFWorkflowActions": actions,
    "WFWorkflowClientVersion": "1200",
    "WFWorkflowClientRelease": "2.2.2",
    "WFWorkflowMinimumClientVersion": 900,
    "WFWorkflowMinimumClientVersionString": "900",
    "WFWorkflowIcon": {
        "WFWorkflowIconStartColor": 4282601983,
        "WFWorkflowIconGlyphNumber": 59427,
    },
    "WFWorkflowImportQuestions": [],
    "WFWorkflowTypes": [],
    "WFWorkflowInputContentItemClasses": ["WFTextContentItem"],
    "WFWorkflowOutputContentItemClasses": [],
    "WFWorkflowHasShortcutInputVariables": False,
    "WFWorkflowHasOutputFallback": False,
    "WFQuickActionSurfaces": [],
    "WFWorkflowNoInputBehavior": "WFWorkflowNoInputBehaviorIgnore",
}


def main():
    ap = argparse.ArgumentParser(description='生成「响课 · 开关闹钟」快捷指令')
    ap.add_argument('-o', '--output', default='XiangKeAlarms.shortcut')
    args = ap.parse_args()

    with open(args.output, 'wb') as f:
        plistlib.dump(shortcut, f, fmt=plistlib.FMT_XML, sort_keys=False)

    print('已写出：%s' % args.output)
    print('  动作数：%d' % len(actions))
    print('  其中「开关闹钟」：%d 个（导入后需逐个选闹钟）' % (len(ALARM_TIMES) * 2))
    print('  对照表地址：%s' % TABLE_URL)


if __name__ == '__main__':
    main()
