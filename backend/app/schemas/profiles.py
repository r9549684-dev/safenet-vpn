from pydantic import BaseModel

class ProfilesResponse(BaseModel):
    etag: str
    profiles: dict