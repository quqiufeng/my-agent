#!/usr/bin/env python3
# agentkit/tools/vacuum.py — 科沃斯 DEEBOT T80 云控（deebot-client）
# 用法: vacuum.py <status|start|pause|resume|stop|dock|find>
# 凭据: 环境变量 ECOVACS_ACCOUNT / ECOVACS_PASSWORD / ECOVACS_COUNTRY(默认 CN)
# 说明: T80 机型类 xwk78e 由库缺失 → 已移植（site-packages/deebot_client/hardware/deebot/xwk78e.py）。
import asyncio, os, sys, uuid

from aiohttp import ClientSession
from deebot_client.authentication import Authenticator, create_rest_config, md5
from deebot_client.api_client import ApiClient
from deebot_client.mqtt_client import MqttClient, create_mqtt_config
from deebot_client.device import Device
from deebot_client.commands.json.clean import Clean, CleanAction
from deebot_client.commands.json.charge import Charge
from deebot_client.commands.json.charge_state import GetChargeState
from deebot_client.commands.json.battery import GetBattery
from deebot_client.commands.json.play_sound import PlaySound

# T80 机型类(xwk78e)库暂缺 → 运行时复用 T20(xwk78e同族)的能力集注册，无需改 site-packages
try:
    from deebot_client.hardware.deebot import DEVICES as _DEVICES
    import deebot_client.hardware.deebot.m4xnd8 as _base  # noqa: F401
    if "xwk78e" not in _DEVICES and "m4xnd8" in _base.DEVICES:
        _DEVICES["xwk78e"] = _base.DEVICES["m4xnd8"]
except Exception as _e:  # pragma: no cover
    print(f"[vacuum] 注册机型失败: {_e}", file=sys.stderr)

ACCT = os.environ.get("ECOVACS_ACCOUNT", "")
PWD = os.environ.get("ECOVACS_PASSWORD", "")
COUNTRY = os.environ.get("ECOVACS_COUNTRY", "CN")


async def run(cmd: str) -> int:
    if not ACCT or not PWD:
        print("缺 ECOVACS_ACCOUNT / ECOVACS_PASSWORD", file=sys.stderr)
        return 3
    dev_id = str(uuid.uuid4())
    async with ClientSession() as s:
        cfg = create_rest_config(s, device_id=dev_id, alpha_2_country=COUNTRY)
        auth = Authenticator(cfg, ACCT, md5(PWD))
        await auth.authenticate()
        devs = await ApiClient(auth).get_devices()
        if not devs.mqtt:
            print("未找到可用设备（型号未支持?）", file=sys.stderr)
            return 1
        mqtt = MqttClient(create_mqtt_config(device_id=dev_id, country=COUNTRY), auth)
        dev = Device(devs.mqtt[0], auth)
        await dev.initialize(mqtt)
        try:
            if cmd == "status":
                ch = await dev.execute_command(GetChargeState())
                bt = await dev.execute_command(GetBattery())
                d = (ch.get("resp", {}).get("body", {}) or {}).get("data", {}) or {}
                b = (bt.get("resp", {}).get("body", {}) or {}).get("data", {}) or {}
                charging = d.get("isCharging")
                mode = d.get("mode")
                val = b.get("value")
                state = "充电中/在充电座" if charging == 1 else "空闲/工作中"
                print(f"{state}；模式={mode}；电量={val}")
            elif cmd in ("start", "pause", "resume", "stop"):
                await dev.execute_command(Clean(CleanAction(cmd)))
                print({"start": "开始清扫", "pause": "暂停", "resume": "继续", "stop": "停止"}[cmd])
            elif cmd == "dock":
                await dev.execute_command(Charge())
                print("已发送归位（回充）")
            elif cmd == "find":
                await dev.execute_command(PlaySound())
                print("已让它发声（找机）")
            else:
                print(f"未知命令: {cmd}", file=sys.stderr)
                return 2
        finally:
            try:
                await dev.teardown()
            except Exception:
                pass
    return 0


if __name__ == "__main__":
    c = sys.argv[1] if len(sys.argv) > 1 else "status"
    try:
        sys.exit(asyncio.run(run(c)))
    except KeyboardInterrupt:
        sys.exit(130)
