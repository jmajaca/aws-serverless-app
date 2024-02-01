import datetime

from pydantic import BaseModel


class HelloWorldSchema(BaseModel):
    message: str
    timestamp: datetime.datetime
