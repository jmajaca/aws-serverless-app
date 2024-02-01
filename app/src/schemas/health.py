from typing import Literal

from pydantic import BaseModel


class HealthSchema(BaseModel):
    status: Literal["OK"]

    @classmethod
    def ok(cls) -> "HealthSchema":
        return cls(status="OK")
