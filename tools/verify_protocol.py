#!/usr/bin/env python3
"""校验从小程序逆向还原的蓝牙协议，与 Swift 端 WingProtocol.frame/parse 保持一致。

用法：python tools/verify_protocol.py
不依赖第三方库；原小程序逻辑见 README「协议还原」一节。
"""
from typing import Optional

DOWN = [0, 10, 20, 30, 40, 50, 60, 70, 80]
UP = [0, 50, 60, 70, 80, 90, 100, 110, 120]
STEPS = [0, 3, 4, 5]


def frame(cmd: int, p1: int, p2: int, did: int = 0x0A) -> str:
    """BB | did | 80 | cmd | p1 | p2"""
    return " ".join(f"{b:02X}" for b in (0xBB, did, 0x80, cmd, p1, p2))


def validate(down: int, up: int) -> str:
    """返回 valid / calibration / 错误文案，顺序与小程序 bindChangeleft 一致"""
    if down == 0 and up == 0:
        return "calibration"
    if up < down + 20:
        return "降速加速临界范围总大于20码"
    if down == 0 and up != 0:
        return "下降速度必须大于零，升降都为零校准除外"
    if up <= down:
        return "升起速度必须大于下降速度，升降都为零校准除外"
    return "valid"


def parse(raw: str):
    """解析 notify 上报的 8 / 12 字节帧"""
    data = bytes.fromhex(raw.replace(" ", ""))
    if len(data) < 8:
        return None
    result = {
        "auto": data[3], "step": data[4], "speed": data[5],
        "down": data[6], "up": data[7],
    }
    if len(data) >= 12:
        result.update({
            "track": data[8], "ignition": data[9],
            "ready": data[10], "fire_result": data[11],
        })
    return result


def ignition_title(ready: bool, on: bool) -> str:
    if not ready:
        return "点火升降(需配合车内按键)"
    return "点火升降(已开启)" if on else "点火升降(已关闭)"


def main() -> None:
    cases = [
        ("设置档位 3", frame(0x01, 3, 0), "BB 0A 80 01 03 00"),
        ("自动升降 10/80", frame(0x02, 10, 80), "BB 0A 80 02 0A 50"),
        ("关闭自动", frame(0x03, 0, 0), "BB 0A 80 03 00 00"),
        ("赛道 强/中/弱", frame(0x04, 1, 0), "BB 0A 80 04 01 00"),
        ("点火开", frame(0x05, 1, 0), "BB 0A 80 05 01 00"),
        ("点火关", frame(0x05, 0, 0), "BB 0A 80 05 00 00"),
        ("一键上升", frame(0x06, 1, 0), "BB 0A 80 06 01 00"),
        ("一键下降", frame(0x06, 2, 0), "BB 0A 80 06 02 00"),
        ("校准 0/0", frame(0x02, 0, 0), "BB 0A 80 02 00 00"),
    ]
    for name, got, want in cases:
        assert got == want, f"{name}: {got} != {want}"
        print(f"  [OK] {name:<16} {got}")

    checks = [
        ((10, 80), "valid"),
        ((0, 0), "calibration"),
        ((50, 60), "降速加速临界范围总大于20码"),
        ((0, 80), "下降速度必须大于零，升降都为零校准除外"),
        ((80, 80), "降速加速临界范围总大于20码"),
    ]
    for (d, u), want in checks:
        got = validate(d, u)
        assert got == want, f"validate({d},{u}): {got} != {want}"
        print(f"  [OK] 校验 {d:>2}/{u:<3} → {got}")

    basic = parse("BB 0A 80 02 03 46 0A 50")
    assert basic == {"auto": 2, "step": 3, "speed": 70, "down": 10, "up": 80}, basic
    print(f"  [OK] 8 字节基础帧 → {basic}")

    full = parse("BB 0A 80 02 05 3C 0A 50 02 01 01 00")
    assert full["track"] == 2 and full["ignition"] == 1 and full["ready"] == 1, full
    assert ignition_title(bool(full["ready"]), bool(full["ignition"])) == "点火升降(已开启)"
    print(f"  [OK] 12 字节扩展帧 → {full}")

    assert parse("BB 0A 80 02") is None
    print("  [OK] 短帧被忽略")

    assert STEPS == [0, 3, 4, 5]
    print("  [OK] 有效档位 = 0 / 3 / 4 / 5（对应 tial0/3/4/5.png）")
    print("\n协议校验全部通过。")


if __name__ == "__main__":
    main()
