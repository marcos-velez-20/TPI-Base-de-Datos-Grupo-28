from fastapi import APIRouter, Query
from database import transaction
from repositories import maridajes as repo

router = APIRouter(prefix="/maridajes", tags=["Maridajes"])


@router.get("")
def listar_maridajes(
    page: int = Query(1, ge=1),
    limit: int = Query(100, ge=1, le=500),
):
    offset = (page - 1) * limit
    with transaction() as conn:
        items = repo.listar_maridajes(conn, limit, offset)
        total = len(items)
    return {"page": page, "limit": limit, "total": total, "items": items[:limit]}