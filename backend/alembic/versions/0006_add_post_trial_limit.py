"""add post_trial_connect_count to users

Revision ID: 0006_add_post_trial_limit
Revises: 0005_add_support
Create Date: 2026-03-01
"""
from alembic import op
import sqlalchemy as sa

revision = "0006_add_post_trial_limit"
down_revision = "0005_add_support"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column(
        "users",
        sa.Column(
            "post_trial_connect_count",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
    )


def downgrade():
    op.drop_column("users", "post_trial_connect_count")
