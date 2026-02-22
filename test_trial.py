import asyncio
from app.database import get_session
from app.models.user import User
from app.services.entitlements import has_trial, is_user_premium, now_utc
from sqlalchemy import select

async def test():
    async for session in get_session():
        result = await session.execute(select(User))
        users = result.scalars().all()
        for u in users:
            te = u.trial_ends_at
            now = now_utc()
            print(f"device={u.device_id[:12]} trial_ends={te} tzinfo={te.tzinfo} now={now} now_tz={now.tzinfo} has_trial={has_trial(u)}")

asyncio.run(test())
