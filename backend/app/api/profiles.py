from fastapi import APIRouter, Depends, Request, Response
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_session
from app.services.profiles import get_profiles_map, compute_etag
from app.schemas.profiles import ProfilesResponse

router = APIRouter(prefix="/profiles", tags=["profiles"])

@router.get("", response_model=ProfilesResponse)
async def get_profiles(request: Request, response: Response, session: AsyncSession = Depends(get_session)):
    profiles_map = await get_profiles_map(session)
    etag = compute_etag(profiles_map)

    inm = request.headers.get("if-none-match")
    if inm and inm.strip('"') == etag:
        response.status_code = 304
        return ProfilesResponse(etag=etag, profiles={})

    response.headers["ETag"] = f"\"{etag}\""
    return ProfilesResponse(etag=etag, profiles=profiles_map)