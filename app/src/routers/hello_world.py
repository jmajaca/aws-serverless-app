from datetime import datetime

from fastapi import APIRouter
from loguru import logger

from src.schemas import HelloWorldSchema

router = APIRouter(prefix="/hello-world")


@router.get(path="", description="Main application endpoint")
async def hello_world() -> HelloWorldSchema:
    logger.info("Received request for hello world.")
    return HelloWorldSchema(message="hello world!!!!!", timestamp=datetime.now())
