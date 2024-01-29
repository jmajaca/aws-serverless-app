from fastapi import APIRouter

from app.schemas.health import HealthSchema

router = APIRouter(prefix="/health")


@router.get(path="", description="Health endpoint")
async def health() -> HealthSchema:
    return HealthSchema.ok()
