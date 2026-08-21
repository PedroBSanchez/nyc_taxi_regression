from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .routers import predict
from .services.predict import get_predictor
from .settings import get_settings

settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI):
    get_predictor()
    yield


app = FastAPI(lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[settings.client_url],
    allow_headers=['*'],
    allow_methods=['*'],
    allow_credentials=True
)

app.include_router(predict.router)
