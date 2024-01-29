from fastapi import FastAPI

from app.routers import health_router, hello_world_router


def create_app() -> FastAPI:
    app = FastAPI(title="demo-app")

    app.include_router(health_router)
    app.include_router(hello_world_router)

    return app


app = create_app()
