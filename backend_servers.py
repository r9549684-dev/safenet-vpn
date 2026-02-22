from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_session
from app.services.servers import list_active_servers
from app.schemas.servers import ServersResponse, ServerItem

router = APIRouter(prefix="/servers", tags=["servers"])


@router.get("/recommended", response_model=ServerItem)
async def recommended_server(session: AsyncSession = Depends(get_session)):
    items = await list_active_servers(session)
    if not items:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No servers available")
    s = items[0]
    return ServerItem(
        id=s.id,
        country=s.country,
        name=s.name,
        host=s.host,
        port=s.port,
        priority=s.priority,
        is_active=s.is_active,
        meta=s.meta or {},
    )


@router.get("", response_model=ServersResponse)
async def servers(session: AsyncSession = Depends(get_session)):
    items = await list_active_servers(session)
    return ServersResponse(
        servers=[
            ServerItem(
                id=s.id,
                country=s.country,
                name=s.name,
                host=s.host,
                port=s.port,
                priority=s.priority,
                is_active=s.is_active,
                meta=s.meta or {},
            )
            for s in items
        ]
    )
