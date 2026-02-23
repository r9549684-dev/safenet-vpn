import uuid
from datetime import datetime
from decimal import Decimal
from typing import Optional
from sqlalchemy import String, DateTime, Numeric, Integer, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column
from app.database import Base


class ReferralTransaction(Base):
    __tablename__ = "referral_transactions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    referrer_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    referred_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    amount_ton: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False)
    transaction_type: Mapped[str] = mapped_column(String(16), nullable=False)  # fixed | percent | discount
    invoice_id: Mapped[Optional[str]] = mapped_column(String(64), nullable=True, unique=True)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="pending")  # pending | processing | completed
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=datetime.utcnow)


class WithdrawalRequest(Base):
    __tablename__ = "withdrawal_requests"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    amount_ton: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False)
    ton_wallet: Mapped[str] = mapped_column(String(64), nullable=False)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="pending")  # pending | processing | completed | rejected
    processed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=datetime.utcnow)
