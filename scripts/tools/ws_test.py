"""AnySim WebSocket 服务快速测试脚本"""
import asyncio, json, websockets, sys

HOST = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 9091

async def test():
    uri = f"ws://{HOST}:{PORT}"
    print(f"[Test] 连接 {uri}")
    try:
        async with websockets.connect(uri) as ws:
            print("[Test] 连接成功!\n")

            # Test 1: get_status
            await ws.send(json.dumps({"cmd": "get_status"}))
            resp = await asyncio.wait_for(ws.recv(), timeout=3.0)
            data = json.loads(resp)
            print(f"[Test] get_status 响应:")
            print(f"  type: {data.get('type')}")
            print(f"  data: {json.dumps(data.get('data'), indent=4)}")

            # Test 2: get_entities
            await ws.send(json.dumps({"cmd": "get_entities"}))
            resp = await asyncio.wait_for(ws.recv(), timeout=3.0)
            data = json.loads(resp)
            print(f"\n[Test] get_entities 响应:")
            print(f"  type: {data.get('type')}")
            print(f"  data: {json.dumps(data.get('data'), indent=4)}")

            # Test 3: start simulation
            await ws.send(json.dumps({"cmd": "start", "payload": {"max_steps": 10}}))
            resp = await asyncio.wait_for(ws.recv(), timeout=3.0)
            data = json.loads(resp)
            print(f"\n[Test] start 响应: {json.dumps(data, indent=4)}")

            # Test 4: receive sim_state
            print("\n[Test] 等待 sim_state 广播...")
            for i in range(3):
                try:
                    resp = await asyncio.wait_for(ws.recv(), timeout=5.0)
                    state = json.loads(resp)
                    print(f"  [{i}] type={state.get('type')}, time={state.get('time'):.2f}, step={state.get('step')}, entities={state.get('entity_count')}")
                except asyncio.TimeoutError:
                    print(f"  [{i}] 超时 (无更多状态)")
                    break

            print("\n[Test] 所有测试通过! ✓")
    except websockets.ConnectionClosedError as e:
        print(f"[Test] 连接断开: {e}")
    except Exception as e:
        print(f"[Test] 错误: {e}")
        import traceback
        traceback.print_exc()

asyncio.run(test())
