from fastapi import FastAPI

from src.routers.health import router as health_router
from src.routers.hello_world import router as hello_world_router


def create_app() -> FastAPI:
    app = FastAPI(title="demo-app")

    app.include_router(health_router)
    app.include_router(hello_world_router)

    return app


app = create_app()
