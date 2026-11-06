#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Swift 源码静态预检（无需 Xcode，Windows / macOS / Linux 均可运行）。

本机没有 Swift 编译器，GitHub Actions 上才第一次真正编译。这个脚本把已经
踩过的、以及容易再犯的编译期问题在提交前拦住：

  1. SwiftUI `.frame(...)` 的两个重载不能混用
     - frame(width:height:alignment:)
     - frame(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:alignment:)
     `width` / `height` 与任何 min/ideal/max 参数同用会报
     "extra argument 'minHeight' in call"。
  2. 字符串插值里直接放 Substring（.prefix/.suffix/...）在
     LocalizedStringKey 上没有对应 appendInterpolation 重载，需要 String(...)。
  3. 项目约定：可选绑定一律写 `guard let self = self`，不用 Swift 5.7 简写。
  4. 括号平衡、旧应用名残留。

用法：
    python tools/verify_swift_sources.py           # 检查全部 Swift 文件
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SWIFT_DIR = ROOT / "WingControl"

FIXED = {"width", "height"}
FLEXIBLE = {"minWidth", "idealWidth", "maxWidth", "minHeight", "idealHeight", "maxHeight"}
KNOWN_FRAME_LABELS = FIXED | FLEXIBLE | {"alignment"}

SUBSTRING_CALLS = re.compile(r"\.(?:prefix|suffix|dropFirst|dropLast|split)\s*\(")
LABEL = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*:")


def mask_strings_and_comments(src: str) -> str:
    """把字符串字面量与注释内容替换为等长空格，保留括号结构与换行。"""
    out = list(src)
    i, n = 0, len(src)
    while i < n:
        ch = src[i]
        if ch == '"':
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == '"':
                    j += 1
                    break
                j += 1
            for k in range(i, min(j, n)):
                if src[k] != "\n":
                    out[k] = " "
            i = j
        elif ch == "/" and i + 1 < n and src[i + 1] == "/":
            j = src.find("\n", i)
            j = n if j == -1 else j
            for k in range(i, j):
                out[k] = " "
            i = j
        elif ch == "/" and i + 1 < n and src[i + 1] == "*":
            j = src.find("*/", i + 2)
            j = n if j == -1 else j + 2
            for k in range(i, min(j, n)):
                if src[k] != "\n":
                    out[k] = " "
            i = j
        else:
            i += 1
    return "".join(out)


def find_frame_calls(masked: str):
    """返回 [(行号, 参数原始文本)]，按括号深度匹配 .frame(...) 调用。"""
    for m in re.finditer(r"\.frame\s*\(", masked):
        # WingProtocol.frame(_:deviceID:) 是本项目自己的协议方法，不是 SwiftUI 修饰符
        if re.search(r"\bWingProtocol\s*$", masked[: m.start()]):
            continue
        start = m.end()
        depth, i = 1, start
        while i < len(masked) and depth:
            if masked[i] == "(":
                depth += 1
            elif masked[i] == ")":
                depth -= 1
            i += 1
        yield masked.count("\n", 0, m.start()) + 1, masked[start : i - 1]


def top_level_labels(args: str) -> list[str]:
    """按顶层逗号切分参数，取每段的实参标签。"""
    parts, depth, buf = [], 0, []
    for ch in args:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append("".join(buf).strip())
            buf = []
        else:
            buf.append(ch)
    parts.append("".join(buf).strip())
    labels = []
    for part in parts:
        if not part:
            continue
        m = LABEL.match(part)
        labels.append(m.group(1) if m else "<位置参数>")
    return labels


def interpolation_fragments(src: str) -> list[tuple[int, str]]:
    """提取所有 \\( ... ) 插值片段（含行号），括号可嵌套。"""
    found = []
    i, n = 0, len(src)
    while i < n - 1:
        if src[i] == "\\" and src[i + 1] == "(":
            depth, j = 1, i + 2
            while j < n and depth:
                if src[j] == "(":
                    depth += 1
                elif src[j] == ")":
                    depth -= 1
                j += 1
            found.append((src.count("\n", 0, i) + 1, src[i + 2 : j - 1]))
            i = j
        else:
            i += 1
    return found


def check_file(path: Path) -> list[str]:
    src = path.read_text(encoding="utf-8")
    masked = mask_strings_and_comments(src)
    rel = path.relative_to(ROOT).as_posix()
    errors: list[str] = []

    # 1) .frame 重载混用 / 未知参数
    for line, args in find_frame_calls(masked):
        labels = top_level_labels(args)
        used = set(labels) - {"<位置参数>"}
        if (used & FIXED) and (used & FLEXIBLE):
            errors.append(
                f"{rel}:{line}: .frame 混用了固定尺寸与弹性尺寸参数 {sorted(used)}；"
                "SwiftUI 没有这个重载，请统一用 min*/max* 或只用 width/height"
            )
        unknown = used - KNOWN_FRAME_LABELS
        if unknown:
            errors.append(f"{rel}:{line}: .frame 未知参数 {sorted(unknown)}")

    # 2) 字符串插值中的 Substring
    for line, frag in interpolation_fragments(src):
        if SUBSTRING_CALLS.search(frag) and "String(" not in frag:
            errors.append(
                f"{rel}:{line}: 字符串插值里是 Substring，LocalizedStringKey 无法插值；"
                "请用 String(...) 包裹"
            )

    # 3) 可选绑定统一写法
    for line, text in enumerate(src.splitlines(), 1):
        if re.search(r"\bguard\s+let\s+self\s*,", text):
            errors.append(f"{rel}:{line}: 请写成 `guard let self = self`（保持跨工具链一致）")

    # 4) 括号平衡（已屏蔽字符串与注释）
    for open_ch, close_ch in [("{", "}"), ("(", ")"), ("[", "]")]:
        if masked.count(open_ch) != masked.count(close_ch):
            errors.append(
                f"{rel}: 括号不平衡 {open_ch}{close_ch} = "
                f"{masked.count(open_ch)}/{masked.count(close_ch)}"
            )

    if "克拉电动尾翼" in src:
        errors.append(f"{rel}: 仍有旧应用名「克拉电动尾翼」")
    return errors


def main() -> int:
    files = sorted(SWIFT_DIR.rglob("*.swift"))
    if not files:
        print(f"ERROR: 找不到 Swift 文件：{SWIFT_DIR}")
        return 1

    errors: list[str] = []
    frames = 0
    for path in files:
        errors.extend(check_file(path))
        frames += len(list(find_frame_calls(mask_strings_and_comments(path.read_text(encoding="utf-8")))))

    print(f"检查 {len(files)} 个 Swift 文件、{frames} 处 .frame 调用")
    if errors:
        print("\n=== 发现 %d 个问题 ===" % len(errors))
        for err in errors:
            print("ERROR:", err)
        return 1
    print("Swift 源码静态预检通过（frame 重载 / Substring 插值 / 可选绑定 / 括号 / 名称）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
