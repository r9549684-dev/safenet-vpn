from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_session
from app.schemas.auth import DeviceAuthRequest, TokenResponse
from app.services.auth import get_or_create_user
from app.utils.security import create_access_token

router = APIRouter(prefix="/auth", tags=["auth"])

@router.post("/device", response_model=TokenResponse)
async def device_auth(payload: DeviceAuthRequest, session: AsyncSession = Depends(get_session)):
    user = await get_or_create_user(session, payload.device_id, payload.country)
    token = create_access_token(str(user.id))
    return TokenResponse(access_token=token, user=user)
