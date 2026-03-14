"""
Support API — AI-agent backend
- Пользователь (Flutter): JWT токен, POST /support/messages (role='user')
- Felix агент:  X-Agent-Secret header, POST /support/agent-message (role='agent')
- AI inline:    POST /support/ask — мгновенный ответ из FAQ-базы
"""
import os
from datetime import datetime
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_session
from app.models.user import User
from app.models.support import SupportSession, SupportMessage
from app.api.users import get_current_user
from app.services.ai_support import get_answer as ai_get_answer

router = APIRouter(prefix="/support", tags=["support"])

AGENT_SECRET = os.getenv("AGENT_SECRET", "")


# ── Schemas ──────────────────────────────────────────────────────────────

class SessionCreate(BaseModel):
    lang: str = Field(default="en", pattern="^(en|ru|fa)$")


class SessionOut(BaseModel):
    session_id: UUID
    lang: str
    created_at: str
    is_open: bool
    rating: Optional[int]


class MessageCreate(BaseModel):
    session_id: UUID
    role: str = Field(pattern="^(user|agent)$")
    message: str = Field(min_length=1, max_length=8000)


class MessageOut(BaseModel):
    id: UUID
    session_id: UUID
    role: str
    message: str
    created_at: str


class RateRequest(BaseModel):
    rating: int = Field(ge=1, le=5)


class AskRequest(BaseModel):
    message: str = Field(min_length=1, max_length=2000)
    lang: str = Field(default="en", pattern="^(en|ru|fa)$")


# ── Helpers ──────────────────────────────────────────────────────────────

def _session_out(s: SupportSession) -> dict:
    return {
        "session_id": s.id,
        "lang": s.lang,
        "created_at": s.created_at.isoformat(),
        "is_open": s.is_open,
        "rating": s.rating,
    }


def _msg_out(m: SupportMessage) -> dict:
    return {
        "id": m.id,
        "session_id": m.session_id,
        "role": m.role,
        "message": m.message,
        "created_at": m.created_at.isoformat(),
    }


# ── AI Ask (inline) ─────────────────────────────────────────────────────

@router.post("/ask")
async def ask_ai(
    body: AskRequest,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    """
    Мгновенный AI-ответ на вопрос пользователя.
    Ищет по встроенной FAQ-базе, фильтрует off-topic.
    Сохраняет оба сообщения (user + agent) в support_messages.
    """
    # Получаем или создаём активную сессию
    result = await session.execute(
        select(SupportSession)
        .where(
            SupportSession.user_id == current_user.id,
            SupportSession.resolved_at.is_(None),
        )
        .order_by(SupportSession.created_at.desc())
        .limit(1)
    )
    sup_session = result.scalar_one_or_none()
    if not sup_session:
        sup_session = SupportSession(
            user_id=current_user.id,
            lang=body.lang,
        )
        session.add(sup_session)
        await session.commit()
        await session.refresh(sup_session)

    # Сохраняем сообщение пользователя
    user_msg = SupportMessage(
        session_id=sup_session.id,
        user_id=current_user.id,
        role="user",
        message=body.message,
    )
    session.add(user_msg)

    # Получаем AI-ответ
    ai_result = ai_get_answer(body.message, body.lang)

    # Сохраняем ответ агента
    agent_msg = SupportMessage(
        session_id=sup_session.id,
        user_id=current_user.id,
        role="agent",
        message=ai_result["answer"],
    )
    session.add(agent_msg)

    await session.commit()
    await session.refresh(user_msg)
    await session.refresh(agent_msg)

    return {
        "answer": ai_result["answer"],
        "source": ai_result["source"],
        "topic": ai_result.get("topic"),
        "session_id": str(sup_session.id),
        "message_id": str(agent_msg.id),
    }


# ── Endpoints ────────────────────────────────────────────────────────────

@router.get("/sessions/active")
async def get_or_create_active_session(
    lang: str = "en",
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    """
    Возвращает активную (незакрытую) сессию пользователя.
    Если активной сессии нет — создаёт автоматически.
    Flutter вызывает один раз при открытии чата.
    """
    result = await session.execute(
        select(SupportSession)
        .where(
            SupportSession.user_id == current_user.id,
            SupportSession.resolved_at.is_(None),
        )
        .order_by(SupportSession.created_at.desc())
        .limit(1)
    )
    existing = result.scalar_one_or_none()
    if existing:
        return _session_out(existing)

    # Auto-create
    new_session = SupportSession(
        user_id=current_user.id,
        lang=lang if lang in ("en", "ru", "fa") else "en",
    )
    session.add(new_session)
    await session.commit()
    await session.refresh(new_session)
    return _session_out(new_session)


@router.post("/sessions", status_code=201)
async def create_session(
    body: SessionCreate,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    """Явное создание новой сессии (например, для повторного обращения)."""
    new_session = SupportSession(
        user_id=current_user.id,
        lang=body.lang,
    )
    session.add(new_session)
    await session.commit()
    await session.refresh(new_session)
    return _session_out(new_session)


@router.post("/messages", status_code=201)
async def save_message(
    body: MessageCreate,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    """
    Flutter: пользователь отправляет сообщение (role='user').
    JWT аутентификация, только role='user' разрешён.
    """
    if body.role != "user":
        raise HTTPException(403, "Use /support/agent-message for agent role")

    sup_session = await session.get(SupportSession, body.session_id)
    if not sup_session:
        raise HTTPException(404, "Session not found")
    if sup_session.user_id != current_user.id:
        raise HTTPException(403, "Not your session")
    if not sup_session.is_open:
        raise HTTPException(400, "Session is already resolved")

    msg = SupportMessage(
        session_id=body.session_id,
        user_id=current_user.id,
        role="user",
        message=body.message,
    )
    session.add(msg)
    await session.commit()
    await session.refresh(msg)
    return _msg_out(msg)


class AgentMessageCreate(BaseModel):
    session_id: UUID
    message: str = Field(min_length=1, max_length=8000)


@router.post("/agent-message", status_code=201)
async def agent_message(
    body: AgentMessageCreate,
    x_agent_secret: Optional[str] = Header(default=None, alias="X-Agent-Secret"),
    session: AsyncSession = Depends(get_session),
):
    """
    Felix-бот: отправить ответ агента (role='agent').
    Аутентификация: X-Agent-Secret header.
    """
    if not AGENT_SECRET:
        raise HTTPException(503, "Agent auth not configured")
    if x_agent_secret != AGENT_SECRET:
        raise HTTPException(401, "Invalid agent secret")

    sup_session = await session.get(SupportSession, body.session_id)
    if not sup_session:
        raise HTTPException(404, "Session not found")
    if not sup_session.is_open:
        raise HTTPException(400, "Session is already resolved")

    msg = SupportMessage(
        session_id=body.session_id,
        user_id=sup_session.user_id,
        role="agent",
        message=body.message,
    )
    session.add(msg)
    await session.commit()
    await session.refresh(msg)
    return _msg_out(msg)


@router.get("/history")
async def get_history(
    session_id: Optional[UUID] = None,
    limit: int = 50,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    """
    История сообщений.
    - Без session_id → активная сессия пользователя.
    - С session_id → конкретная сессия (должна принадлежать пользователю).
    """
    if session_id:
        sup_session = await session.get(SupportSession, session_id)
        if not sup_session or sup_session.user_id != current_user.id:
            raise HTTPException(404, "Session not found")
        target_session_id = session_id
    else:
        result = await session.execute(
            select(SupportSession)
            .where(
                SupportSession.user_id == current_user.id,
                SupportSession.resolved_at.is_(None),
            )
            .order_by(SupportSession.created_at.desc())
            .limit(1)
        )
        sup_session = result.scalar_one_or_none()
        if not sup_session:
            return []
        target_session_id = sup_session.id

    result = await session.execute(
        select(SupportMessage)
        .where(SupportMessage.session_id == target_session_id)
        .order_by(SupportMessage.created_at.asc())
        .limit(limit)
    )
    messages = result.scalars().all()
    return [_msg_out(m) for m in messages]


@router.post("/sessions/{session_id}/resolve")
async def resolve_session(
    session_id: UUID,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    """Закрыть сессию (агент вызывает после завершения диалога)."""
    sup_session = await session.get(SupportSession, session_id)
    if not sup_session or sup_session.user_id != current_user.id:
        raise HTTPException(404, "Session not found")
    if not sup_session.is_open:
        raise HTTPException(400, "Session already resolved")

    sup_session.resolved_at = datetime.utcnow()
    session.add(sup_session)
    await session.commit()
    return {"ok": True, "resolved_at": sup_session.resolved_at.isoformat()}


@router.post("/sessions/{session_id}/rate")
async def rate_session(
    session_id: UUID,
    body: RateRequest,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    """Пользователь оценивает сессию 1–5 после закрытия."""
    sup_session = await session.get(SupportSession, session_id)
    if not sup_session or sup_session.user_id != current_user.id:
        raise HTTPException(404, "Session not found")

    sup_session.rating = body.rating
    session.add(sup_session)
    await session.commit()
    return {"ok": True, "rating": sup_session.rating}
