from contextlib import asynccontextmanager

import os
import psycopg
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

import database
from errors import traducir_error_pg
from routers import clientes, comprobantes, ingresos, reportes, salud, transferencias, vinos, cepas, bodegas, salas, maridajes


def _cors_origins():
    raw = os.getenv("CORS_ORIGINS", "http://localhost:5173,http://localhost:8080")
    return [o.strip() for o in raw.split(",") if o.strip()]


@asynccontextmanager
async def lifespan(app: FastAPI):
    database.init_pool()
    yield
    database.close_pool()


app = FastAPI(
    title="Bodegas del Atuel - API REST",
    description="API sobre PostgreSQL con SQL puro (psycopg). Las reglas de negocio las aplica la base.",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins(),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(psycopg.Error)
async def manejar_error_postgres(request, exc: psycopg.Error):
    status, cuerpo, headers = traducir_error_pg(exc)
    return JSONResponse(status_code=status, content=cuerpo, headers=headers)


for r in (salud, vinos, clientes, comprobantes, transferencias, ingresos, reportes, cepas, bodegas, salas, maridajes):
    app.include_router(r.router)
