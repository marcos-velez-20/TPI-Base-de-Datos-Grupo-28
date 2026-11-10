from fastapi import APIRouter, Query
from database import transaction
from repositories import bodegas as repo

router = APIRouter(prefix="/bodegas", tags=["Bodegas"])


@router.get("")
def listar_bodegas(
    page: int = Query(1, ge=1),
    limit: int = Query(100, ge=1, le=500),
):
    offset = (page - 1) * limit
    with transaction() as conn:
        items = repo.listar_bodegas(conn, limit, offset)
        total = len(items)
    return {"page": page, "limit": limit, "total": total, "items": items[:limit]}