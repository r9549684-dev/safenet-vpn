from pydantic import BaseModel, Field

class DeviceAuthRequest(BaseModel):
    device_id: str = Field(min_length=6, max_length=128)
    country: str | None = Field(default=None, min_length=2, max_length=2)

from app.schemas.users import UserSchema

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserSchema
