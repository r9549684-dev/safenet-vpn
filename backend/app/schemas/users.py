from pydantic import BaseModel
from datetime import datetime
from uuid import UUID

class UserSchema(BaseModel):
    id: UUID
    device_id: str
    country: str | None
    language: str | None = None
    referral_code: str | None
    is_premium: bool
    premium_until: datetime | None
    trial_ends_at: datetime
    created_at: datetime
    
    # Computed fields (optional, if we want to return them)
    # compute_credits: int = 0 

    class Config:
        from_attributes = True

class MeResponse(UserSchema):
    pass
