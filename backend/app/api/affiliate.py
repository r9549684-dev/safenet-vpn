import re
from decimal import Decimal
from fastapi import APIRouter, Depends, Header, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel
from typing import Optional

from app.database import get_session
from app.models.user import User
from app.models.affiliate import WithdrawalRequest, ReferralTransaction
from app.services.affiliate import get_ton_usd_rate, process_withdrawal
from app.services.cryptobot import CryptoBotService
from app.api.users import get_current_user
from app.config import settings

router = APIRouter(prefix="/affiliate", tags=["affiliate"])

TON_WALLET_RE = re.compile(r'^(0:[a-fA-F0-9]{64}|EQ[a-zA-Z0-9_-]{46})$')


# ── Admin dependency ──────────────────────────────────────────────────────────

async def require_admin(
    x_admin_secret: Optional[str] = Header(default=None, alias="X-Admin-Secret"),
) -> None:
    if not settings.ADMIN_SECRET or not x_admin_secret:
        raise HTTPException(status_code=403, detail="Admin access required")
    if x_admin_secret != settings.ADMIN_SECRET:
        raise HTTPException(status_code=403, detail="Admin access required")


# ── Schemas ──────────────────────────────────────────────────────────────────

class WalletUpdate(BaseModel):
    ton_wallet: str

class WithdrawalCreate(BaseModel):
    amount_ton: Decimal

class PartnerApply(BaseModel):
    ton_wallet: str


# ── User endpoints ────────────────────────────────────────────────────────────

@router.get("/profile")
async def get_affiliate_profile(
    current_user: User = Depends(get_current_user),
):
    ton_rate = await get_ton_usd_rate()
    balance_usd = float(current_user.referral_balance) * float(ton_rate)
    min_withdrawal_ton = Decimal("5") / ton_rate

    return {
        "user_type": current_user.user_type,
        "referral_code": current_user.referral_code,
        "referral_balance_ton": float(current_user.referral_balance),
        "referral_balance_usd": round(balance_usd, 2),
        "paid_referrals_count": current_user.paid_referrals_count,
        "current_rate": current_user.affiliate_rate if current_user.is_partner else None,
        "next_payment_discount": float(current_user.next_payment_discount),
        "ton_wallet": current_user.ton_wallet,
        "min_withdrawal_ton": float(min_withdrawal_ton.quantize(Decimal("0.000001"))),
        "can_withdraw": current_user.referral_balance >= min_withdrawal_ton,
    }


@router.post("/wallet")
async def update_wallet(
    body: WalletUpdate,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    if not TON_WALLET_RE.match(body.ton_wallet):
        raise HTTPException(400, "Неверный формат TON кошелька. Используй формат 0:... или EQ...")
    current_user.ton_wallet = body.ton_wallet
    session.add(current_user)
    await session.commit()
    return {"ok": True, "ton_wallet": body.ton_wallet}


@router.post("/apply-partner")
async def apply_partner(
    body: PartnerApply,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    if current_user.is_partner:
        raise HTTPException(400, "Уже являешься партнёром")
    if not TON_WALLET_RE.match(body.ton_wallet):
        raise HTTPException(400, "Неверный формат TON кошелька")
    current_user.user_type = "partner"
    current_user.ton_wallet = body.ton_wallet
    session.add(current_user)
    await session.commit()
    return {"ok": True, "message": "Статус партнёра активирован"}


@router.post("/withdraw")
async def request_withdrawal(
    body: WithdrawalCreate,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    if not current_user.is_partner:
        raise HTTPException(403, "Только для партнёров")
    if not current_user.ton_wallet:
        raise HTTPException(400, "Сначала укажи TON кошелёк")

    ton_rate = await get_ton_usd_rate()
    min_ton = Decimal("5") / ton_rate

    if body.amount_ton < min_ton:
        raise HTTPException(400, f"Минимальная сумма вывода: {float(min_ton):.6f} TON (~$5)")
    if body.amount_ton > current_user.referral_balance:
        raise HTTPException(400, "Недостаточно средств на балансе")

    # Проверить нет ли pending запроса
    existing = await session.execute(
        select(WithdrawalRequest).where(
            WithdrawalRequest.user_id == current_user.id,
            WithdrawalRequest.status.in_(["pending", "processing"]),
        )
    )
    if existing.scalar_one_or_none():
        raise HTTPException(400, "Уже есть активный запрос на вывод")

    withdrawal = WithdrawalRequest(
        user_id=current_user.id,
        amount_ton=body.amount_ton,
        ton_wallet=current_user.ton_wallet,
        status="pending",
    )
    session.add(withdrawal)
    await session.commit()
    await session.refresh(withdrawal)

    # Попытка авто-вывода через CryptoBot
    cryptobot = CryptoBotService()
    success = await process_withdrawal(session, withdrawal, cryptobot)

    return {
        "ok": True,
        "withdrawal_id": withdrawal.id,
        "status": "completed" if success else "pending",
        "message": "Средства отправлены" if success else "Запрос создан, ожидает обработки",
    }


@router.get("/withdrawals")
async def get_withdrawals(
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    result = await session.execute(
        select(WithdrawalRequest)
        .where(WithdrawalRequest.user_id == current_user.id)
        .order_by(WithdrawalRequest.created_at.desc())
        .limit(50)
    )
    withdrawals = result.scalars().all()
    return [
        {
            "id": w.id,
            "amount_ton": float(w.amount_ton),
            "ton_wallet": w.ton_wallet,
            "status": w.status,
            "created_at": w.created_at.isoformat(),
            "processed_at": w.processed_at.isoformat() if w.processed_at else None,
        }
        for w in withdrawals
    ]


@router.get("/transactions")
async def get_transactions(
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    result = await session.execute(
        select(ReferralTransaction)
        .where(ReferralTransaction.referrer_id == current_user.id)
        .order_by(ReferralTransaction.created_at.desc())
        .limit(100)
    )
    txs = result.scalars().all()
    return [
        {
            "id": t.id,
            "amount_ton": float(t.amount_ton),
            "type": t.transaction_type,
            "status": t.status,
            "created_at": t.created_at.isoformat(),
        }
        for t in txs
    ]


# ── Admin endpoints ───────────────────────────────────────────────────────────

@router.get("/admin/withdrawals", dependencies=[Depends(require_admin)])
async def admin_list_withdrawals(session: AsyncSession = Depends(get_session)):
    result = await session.execute(
        select(WithdrawalRequest)
        .where(WithdrawalRequest.status == "pending")
        .order_by(WithdrawalRequest.created_at)
    )
    items = result.scalars().all()
    return [
        {
            "id": w.id,
            "user_id": str(w.user_id),
            "amount_ton": float(w.amount_ton),
            "ton_wallet": w.ton_wallet,
            "status": w.status,
            "created_at": w.created_at.isoformat(),
        }
        for w in items
    ]


@router.post("/admin/withdrawals/{withdrawal_id}/approve", dependencies=[Depends(require_admin)])
async def admin_approve_withdrawal(
    withdrawal_id: int,
    session: AsyncSession = Depends(get_session),
):
    withdrawal = await session.get(WithdrawalRequest, withdrawal_id)
    if not withdrawal:
        raise HTTPException(404, "Запрос не найден")
    if withdrawal.status != "pending":
        raise HTTPException(400, f"Статус: {withdrawal.status}")

    cryptobot = CryptoBotService()
    success = await process_withdrawal(session, withdrawal, cryptobot)
    return {"ok": success, "status": "completed" if success else "failed"}


@router.post("/admin/withdrawals/{withdrawal_id}/reject", dependencies=[Depends(require_admin)])
async def admin_reject_withdrawal(
    withdrawal_id: int,
    session: AsyncSession = Depends(get_session),
):
    withdrawal = await session.get(WithdrawalRequest, withdrawal_id)
    if not withdrawal:
        raise HTTPException(404, "Запрос не найден")
    withdrawal.status = "rejected"
    session.add(withdrawal)
    await session.commit()
    return {"ok": True}
