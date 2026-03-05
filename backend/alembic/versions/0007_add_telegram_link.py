"""add telegram_id and link_token to users

Revision ID: 0007_add_telegram_link
Revises: 0006_add_post_trial_limit
Create Date: 2026-03-05
"""
from alembic import op
import sqlalchemy as sa

revision = "0007_add_telegram_link"
down_revision = "0006_add_post_trial_limit"
branch_labels = None
depends_on = None


def upgrade():
    # telegram_id — Telegram user ID (BIGINT, уникальный, nullable)
    op.add_column(
        "users",
        sa.Column("telegram_id", sa.BigInteger(), nullable=True),
    )
    op.create_index("ix_users_telegram_id", "users", ["telegram_id"], unique=True)

    # link_token — 6-символьный одноразовый токен для привязки аккаунта
    op.add_column(
        "users",
        sa.Column("link_token", sa.String(10), nullable=True),
    )
    # link_token_expires — TTL токена (UTC)
    op.add_column(
        "users",
        sa.Column("link_token_expires", sa.DateTime(), nullable=True),
    )


def downgrade():
    op.drop_column("users", "link_token_expires")
    op.drop_column("users", "link_token")
    op.drop_index("ix_users_telegram_id", table_name="users")
    op.drop_column("users", "telegram_id")
