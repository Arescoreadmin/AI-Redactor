import os, asyncio, asyncpg, uuid
DSN = os.getenv("POSTGRES_DSN","postgresql://postgres:postgres@postgres:5432/redactor")
async def main():
    pool = await asyncpg.create_pool(DSN)
    async with pool.acquire() as c:
        await c.execute("INSERT INTO orgs(id, name) VALUES($1,$2) ON CONFLICT DO NOTHING", uuid.UUID("00000000-0000-0000-0000-000000000001"), "Demo Org")
    print("Fixture org created.")
asyncio.run(main())
