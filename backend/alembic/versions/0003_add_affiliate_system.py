"""add affiliate system

Revision ID: 0003_add_affiliate_system
Revises: 0002_add_user_connections
Create Date: 2026-02-21
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0003_add_affiliate_system"
down_revision = "0002_add_user_connections"
branch_labels = None
depends_on = None


def upgrade():
    # Новые поля в таблице users
    op.add_column("users", sa.Column("ton_wallet", sa.String(64), nullable=True))
    op.add_column("users", sa.Column("user_type", sa.String(16), server_default="regular", nullable=False))
    op.add_column("users", sa.Column("referral_balance", sa.Numeric(18, 6), server_default="0", nullable=False))
    op.add_column("users", sa.Column("paid_referrals_count", sa.Integer(), server_default="0", nullable=False))
    op.add_column("users", sa.Column("next_payment_discount", sa.Numeric(5, 2), server_default="0", nullable=False))

    # Таблица referral_transactions
    op.create_table(
        "referral_transactions",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("referrer_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("referred_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("amount_ton", sa.Numeric(18, 6), nullable=False),
        sa.Column("transaction_type", sa.String(16), nullable=False),
        sa.Column("invoice_id", sa.String(64), nullable=True, unique=True),
        sa.Column("status", sa.String(16), server_default="pending", nullable=False),
        sa.Column("created_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
    )

    # Таблица withdrawal_requests
    op.create_table(
        "withdrawal_requests",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("amount_ton", sa.Numeric(18, 6), nullable=False),
        sa.Column("ton_wallet", sa.String(64), nullable=False),
        sa.Column("status", sa.String(16), server_default="pending", nullable=False),
        sa.Column("processed_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
    )

    op.create_index("ix_referral_transactions_referrer", "referral_transactions", ["referrer_id"])
    op.create_index("ix_referral_transactions_invoice", "referral_transactions", ["invoice_id"], unique=True)
    op.create_index("ix_withdrawal_requests_user", "withdrawal_requests", ["user_id"])


def downgrade():
    op.drop_index("ix_withdrawal_requests_user", table_name="withdrawal_requests")
    op.drop_index("ix_referral_transactions_invoice", table_name="referral_transactions")
    op.drop_index("ix_referral_transactions_referrer", table_name="referral_transactions")
    op.drop_table("withdrawal_requests")
    op.drop_table("referral_transactions")
    op.drop_column("users", "next_payment_discount")
    op.drop_column("users", "paid_referrals_count")
    op.drop_column("users", "referral_balance")
    op.drop_column("users", "user_type")
    op.drop_column("users", "ton_wallet")
