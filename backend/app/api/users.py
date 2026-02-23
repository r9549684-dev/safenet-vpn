from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from datetime import datetime
from app.database import get_session
from app.models.user import User
from app.schemas.users import MeResponse
from app.utils.security import decode_token
from app.services.entitlements import is_user_premium, now_utc

router = APIRouter(prefix="/users", tags=["users"])
oauth2 = OAuth2PasswordBearer(tokenUrl="auth/device")

async def get_current_user(session: AsyncSession = Depends(get_session), token: str = Depends(oauth2)) -> User:
    try:
        data = decode_token(token)
        user_id = data["sub"]
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid token")

    q = await session.execute(select(User).where(User.id == user_id))
    user = q.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=401, detail="User not found")
    return user

@router.get("/me", response_model=MeResponse)
async def me(user: User = Depends(get_current_user)):
    return user
