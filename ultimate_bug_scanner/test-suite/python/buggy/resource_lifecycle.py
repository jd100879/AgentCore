import subprocess
import asyncio

fh = open("/tmp/leaky.txt", "w")
fh.write("hello")

proc = subprocess.Popen(["sleep", "1"])

async def leak_task():
    task = asyncio.create_task(asyncio.sleep(1))
    await asyncio.sleep(0.1)
    return task

asyncio.run(leak_task())
