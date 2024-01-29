from datetime import datetime

from fastapi import APIRouter

from app.schemas import HelloWorldSchema

router = APIRouter(prefix="/hello-world")


@router.get(path="", description="Main application endpoint")
async def health() -> HelloWorldSchema:
    return HelloWorldSchema(message="hello world", timestamp=datetime.now())
