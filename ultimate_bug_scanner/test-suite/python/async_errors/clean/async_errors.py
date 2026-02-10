import asyncio

async def fetch_user(uid):
    await asyncio.sleep(0.1)
    return {'uid': uid}

async def refresh_dashboard():
    try:
        data = await fetch_user('abc')
    except Exception as exc:
        print('dashboard failed', exc)
        raise
    try:
        await fetch_user('lazy')
    finally:
        print('background fetch complete')

async def bootstrap():
    try:
        await refresh_dashboard()
    except Exception as exc:
        print('bootstrap failed', exc)
        raise

if __name__ == '__main__':
    asyncio.run(bootstrap())
