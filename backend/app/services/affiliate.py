import logging
from decimal import Decimal
from datetime import datetime
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update, func
import httpx

from app.models.user import User
from app.models.invoice import Invoice
from app.models.affiliate import ReferralTransaction, WithdrawalRequest

log = logging.getLogger(__name__)

# Курс TON/USD через CoinGecko
async def get_ton_usd_rate() -> Decimal:
    try:
        async with httpx.AsyncClient(timeout=5) as client:
            r = await client.get(
                "https://api.coingecko.com/api/v3/simple/price",
                params={"ids": "the-open-network", "vs_currencies": "usd"},
            )
            data = r.json()
            return Decimal(str(data["the-open-network"]["usd"]))
    except Exception:
        return Decimal("3.0")  # fallback


async def usd_to_ton(usd_amount: Decimal) -> Decimal:
    rate = await get_ton_usd_rate()
    return (usd_amount / rate).quantize(Decimal("0.000001"))


async def process_referral_reward(
    db: AsyncSession,
    referrer: User,
    referred: User,
    payment_amount_usd: Decimal,
    invoice_id: str,
) -> None:
    """Вызывается после успешной оплаты. Начисляет вознаграждение рефереру."""

    # Идемпотентность — не начислять дважды за один invoice
    existing = await db.execute(
        select(ReferralTransaction).where(ReferralTransaction.invoice_id == invoice_id)
    )
    if existing.scalar_one_or_none():
        return

    if referrer.user_type == "regular":
        # Обычный пользователь — скидка 50% на следующий платёж
        await db.execute(
            update(User)
            .where(User.id == referrer.id)
            .values(next_payment_discount=Decimal("0.50"))
        )
        tx = ReferralTransaction(
            referrer_id=referrer.id,
            referred_id=referred.id,
            amount_ton=Decimal("0"),
            transaction_type="discount",
            invoice_id=invoice_id,
            status="completed",
        )
        db.add(tx)

    elif referrer.user_type == "partner":
        # Проверяем, первая ли это оплата реферала (First Time Deposit)
        # Инвойс уже помечен как paid перед вызовом этой функции, поэтому count >= 1
        q_count = await db.execute(
            select(func.count()).select_from(Invoice)
            .where(Invoice.user_id == str(referred.id))
            .where(Invoice.status == "paid")
        )
        paid_count = q_count.scalar_one()
        is_first_payment = (paid_count == 1)

        amount_ton = Decimal("0")
        tx_type = "unknown"
        should_increment_counter = False

        if is_first_payment:
            # CPA: Фиксированная выплата $1.5 за первого уникального
            amount_ton = await usd_to_ton(Decimal("1.5"))
            tx_type = "cpa"
            should_increment_counter = True
        else:
            # RevShare: Процент от продления (Recurring)
            # Процент зависит от уровня партнера (кол-во приведенных)
            rate = referrer.affiliate_rate
            if rate > 0:
                amount_ton = await usd_to_ton(payment_amount_usd * Decimal(str(rate)))
                tx_type = "revshare"
            else:
                # Если уровень партнера не позволяет получать % (до 100 рефералов), то 0
                amount_ton = Decimal("0")
                tx_type = "revshare_zero"

        if amount_ton > 0 or should_increment_counter:
            tx = ReferralTransaction(
                referrer_id=referrer.id,
                referred_id=referred.id,
                amount_ton=amount_ton,
                transaction_type=tx_type,
                invoice_id=invoice_id,
                status="pending" if amount_ton > 0 else "completed",
            )
            db.add(tx)

            # Обновляем баланс и счетчик
            values_to_update = {}
            if amount_ton > 0:
                values_to_update["referral_balance"] = User.referral_balance + amount_ton
            if should_increment_counter:
                values_to_update["paid_referrals_count"] = User.paid_referrals_count + 1
            
            if values_to_update:
                await db.execute(
                    update(User)
                    .where(User.id == referrer.id)
                    .values(**values_to_update)
                )

    await db.commit()
    log.info("Referral reward processed: referrer=%s type=%s invoice=%s", referrer.id, referrer.user_type, invoice_id)


async def process_withdrawal(
    db: AsyncSession,
    withdrawal: WithdrawalRequest,
    cryptobot,
) -> bool:
    """Выполнить вывод средств через CryptoBot."""
    try:
        await db.execute(
            update(WithdrawalRequest)
            .where(WithdrawalRequest.id == withdrawal.id)
            .values(status="processing")
        )
        await db.commit()

        success = await cryptobot.transfer(
            wallet=withdrawal.ton_wallet,
            amount=float(withdrawal.amount_ton),
            asset="TON",
            comment=f"SafeNet affiliate withdrawal #{withdrawal.id}",
        )

        if success:
            await db.execute(
                update(WithdrawalRequest)
                .where(WithdrawalRequest.id == withdrawal.id)
                .values(status="completed", processed_at=datetime.utcnow())
            )
            await db.execute(
                update(User)
                .where(User.id == withdrawal.user_id)
                .values(referral_balance=User.referral_balance - withdrawal.amount_ton)
            )
            await db.commit()
            return True
        else:
            await db.execute(
                update(WithdrawalRequest)
                .where(WithdrawalRequest.id == withdrawal.id)
                .values(status="pending")
            )
            await db.commit()
            return False

    except Exception as e:
        await db.rollback()
        log.error("process_withdrawal error: %s", e)
        raise e
