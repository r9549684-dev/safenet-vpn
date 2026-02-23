from pydantic import BaseModel, Field

class CreateInvoiceRequest(BaseModel):
    amount: float = Field(gt=0)
    months: int = Field(default=1, ge=1, le=24)

class CreateInvoiceResponse(BaseModel):
    provider: str
    invoice_id: str
    pay_url: str | None = None
    raw: dict