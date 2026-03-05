import uuid
from datetime import datetime
from decimal import Decimal
from typing import Optional
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy import BigInteger, String, Boolean, DateTime, Numeric, Integer
from sqlalchemy.orm import Mapped, mapped_column
from app.database import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    device_id: Mapped[str] = mapped_column(String, unique=True, index=True)

    country: Mapped[str | None] = mapped_column(String(2), nullable=True)

    referral_code: Mapped[str | None] = mapped_column(String(16), unique=True, nullable=True)
    referred_by: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)

    is_premium: Mapped[bool] = mapped_column(Boolean, default=False)
    premium_until: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    trial_ends_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)

    # Affiliate / referral fields
    ton_wallet: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    user_type: Mapped[str] = mapped_column(String(16), nullable=False, default="regular")  # regular | partner
    referral_balance: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False, default=Decimal("0"))
    paid_referrals_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    next_payment_discount: Mapped[Decimal] = mapped_column(Numeric(5, 2), nullable=False, default=Decimal("0"))
    post_trial_connect_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

    # Telegram integration
    telegram_id: Mapped[Optional[int]] = mapped_column(BigInteger, nullable=True, unique=True)
    link_token: Mapped[Optional[str]] = mapped_column(String(10), nullable=True)
    link_token_expires: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)

    @property
    def is_trial(self) -> bool:
        """True если пользователь в активном триал-периоде (не premium)."""
        if self.is_premium:
            return False
        return self.trial_ends_at > datetime.utcnow()

    @property
    def is_partner(self) -> bool:
        return self.user_type == "partner"

    @property
    def affiliate_rate(self) -> float:
        """Процент выплаты для партнёра по прогрессивной шкале."""
        count = self.paid_referrals_count
        if count >= 1500:
            return 0.25
        elif count >= 1001:
            return 0.20
        elif count >= 501:
            return 0.15
        elif count >= 101:
            return 0.10
        return 0.0  # CPA only ($1.5) до 100
