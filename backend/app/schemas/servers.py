from pydantic import BaseModel

class ServerItem(BaseModel):
    id: int
    country: str
    name: str
    host: str
    port: int
    priority: int
    is_active: bool
    meta: dict

class ServersResponse(BaseModel):
    servers: list[ServerItem]