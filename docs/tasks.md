# Implementation Task List — Household Chores Motivation App

**Version**: 1.0
**Date**: 2026-07-16
**Source of truth**: `docs/requirements.md`

Each task is designed to be self-contained. A developer agent can implement it by
reading only this task description plus the referenced requirements sections.
Dependency chains are explicit.

**All 82 tasks (TASK-001–082) are complete.** Their full bodies live in
`docs/archive/tasks-completed.md`; the ledger below is the authoritative
history. New work: append tasks here as TASK-082+ following the same format
(self-contained body, acceptance criteria, ledger row).

---

## Status Ledger (updated 2026-07-16)

| Range | Status |
|---|---|
| TASK-001 … TASK-027 | ✅ Done (initial MVP build-out) — archived |
| TASK-028 … TASK-030 | ✅ Done (credential purge, IDOR fix, recurrence keys) — archived |
| TASK-031 | ✅ Done 2026-07-16 — slowapi rate limiting on `/auth/login` (5/min), `/auth/register` (10/h), `/auth/refresh` (30/min) per client IP; 429 + `Retry-After`; configurable via `RATE_LIMIT_*` settings; disabled suite-wide in tests with dedicated enable-and-assert tests. |
| TASK-032 … TASK-044 | ✅ Done (Dockerfile hardening, logout/revocation, enum validation, health probe, fixtures, headers/CORS, refresh endpoint, reassignment+pagination, invite mgmt, N+1, deps, scheduler UTC/lock) — archived. ⚠️ TASK-042's login regression was fixed by TASK-068 (archived). |
| TASK-045 … TASK-051 | ✅ Done, with follow-up defects fixed by TASK-054+ — archived (TASK-047's logout call was defeated by a caller bug, TASK-050 missed the refresh Dio, TASK-051 only fixed the banner) |
| TASK-052, TASK-053 | ✅ Done 2026-07-16 — admin chore reassignment UI (member-picker sheet, pending/overdue only) and invite management (list active invites with expiry, revoke, admin-gated) — archived. |
| TASK-054, TASK-055, TASK-056 | ✅ Done 2026-07-15 — INTERNET permission + cleartext network-security-config; logout ordering fixed; refresh interceptor hardened (retry marker, `/auth/` exclusion, shared-future queueing for concurrent 401s, timeouts) — archived. |
| TASK-057 | ✅ Done 2026-07-17 — runtime server URL: first-run setup screen with health-check test, secure-storage persistence, per-request baseUrl injection (no restart needed), change-server entry points on login/dashboard (logs out on change) — archived. |
| TASK-058, TASK-059, TASK-064 | ✅ Done 2026-07-17 — chores fetch pages until complete (limit=100, 10-page guard); mutations invalidate related providers (leaderboards, members, chores); post-completion UI shows server pointsAwarded — archived. |
| TASK-060, TASK-061, TASK-062 | ✅ Done 2026-07-17 — "Edit series" wired into the admin menu (past-date edits saveable); invite deep links via `choreapp:///join/<token>` QR + `/join/:token` route with logged-out stash-then-join; shared `friendlyErrorMessage` used by AppErrorWidget and all snackbars, rename flow error-handled — archived. |
| TASK-063 | ✅ Done 2026-07-17 — real applicationId (dev.ahzed11.choreapp — existing installs won't upgrade in place), "ChoreApp" label, keystore signing via key.properties/env with debug fallback, CI signing via ANDROID_KEYSTORE_* secrets, versionCode from CI run number — archived. |
| TASK-065, TASK-066, TASK-067 | ✅ Done 2026-07-17 — ~750 lines dead code removed, constants/avatar/confirm-complete dedup, `householdByIdProvider`/`isAdminProvider`; accessibility pass (semantic labels, 48dp targets via AccessibleTap); chore detail sheet, splash route, bundled Outfit font (google_fonts dropped), copyWith sentinel, single user-ID source, misc guards. Analyzer now clean with zero infos — CI runs strict `flutter analyze` — archived. |
| TASK-068, TASK-069 | ✅ Done 2026-07-15 — login fixed (`expires_delta` restored), stale integration test fixed; CI runs on all branches; ruff in CI; real coverage 95% against the 75% gate. 137/137 tests pass — archived. |
| TASK-070, TASK-071, TASK-072 | ✅ Done 2026-07-15 — `JWT_EXPIRY_MINUTES=30` (deprecated `JWT_EXPIRY_DAYS` fallback) + `JWT_SECRET` strength validation; chores list ORDER BY + 422 on bad filter params + reassign status guard; idempotent logout, daily expired-token cleanup, refresh-replay revokes the token family, typed `/auth/refresh` response — archived. |
| TASK-073, TASK-080 | ✅ Done 2026-07-16 — scheduler runs at startup + 6h misfire grace; backfill capped at `GRACE_DAYS` (default 3); one rotation lock per household per run; rotation-pointer modulo bug fixed; invite-accept row lock; test suite 2:46 → ~1:10 — archived. |
| TASK-074, TASK-075, TASK-076 | ✅ Done 2026-07-16 — `docker-compose.prod.yml` (GHCR image, migrations-on-start entrypoint); daily `pg_dump` backup sidecar + `make backup`/`make restore`; root `README.md` self-hosting guide — archived. ⚠️ Not runtime-verified (no container runtime in the review session). |
| TASK-077, TASK-078, TASK-079 | ✅ Done 2026-07-15 — `POST /users/me/password` + operator reset CLI; `DELETE /households/{id}` + `DELETE /users/me` (sole-admin guard, redistribution, token revocation, cascade-deletes the user's `PointLedger` rows); email lowercase normalization + `lower(email)` unique index; leaderboard UTC + exclusive window bounds — archived. |
| TASK-081 | ✅ Done 2026-07-17 — nightly per-household reminder summaries (due today + newly overdue, with assignees) via ntfy or Gotify; off unless `NOTIFY_URL` set; delivery failures never break the job; README setup section — archived. |
| TASK-082 | ✅ Done 2026-07-18 — multi-arch backend image: CI publishes a linux/amd64 + linux/arm64 manifest to GHCR (QEMU + buildx `platforms`), so ARM NAS/Raspberry Pi hosts pull a native variant — archived. |
| TASK-083 | ⬜ Pending — GroceryItem model, Alembic migration, Pydantic schemas |
| TASK-084 | ⬜ Pending — Groceries API router (CRUD + purchase/unpurchase) |
| TASK-085 | ⬜ Pending — Register grocery router in main.py + backend integration tests |
| TASK-086 | ⬜ Pending — Flutter grocery models, API constants, Riverpod provider |
| TASK-087 | ⬜ Pending — Flutter grocery list screen, bottom nav tab, router, tests |

---

## TASK-083: Backend — GroceryItem model, Alembic migration, and Pydantic schemas

**Domain**: Backend  
**Depends on**: TASK-082 (latest schema as of 2026-07-18)  
**Description**: Create the SQLAlchemy ORM model for a per-household shared grocery checklist, generate an Alembic migration, and define Pydantic request/response schemas so the API router (TASK-084) has everything it needs to build on.

### Design

A household has exactly one implicit grocery list — no separate `GroceryList` table. Items live directly under the household. This keeps the MVP simple. If named lists are ever needed, a `list_id` FK can be added later without breaking existing items.

### GroceryItem model

Create `backend/app/models/grocery_item.py`:

```python
import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, String, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin


class GroceryItem(Base, TimestampMixin):
    __tablename__ = "grocery_items"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    household_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("households.id", ondelete="CASCADE"), nullable=False, index=True
    )
    added_by_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    quantity: Mapped[str | None] = mapped_column(String(100), nullable=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_purchased: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    purchased_by_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    purchased_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    # relationships
    household: Mapped["Household"] = relationship()
    added_by: Mapped["User | None"] = relationship(foreign_keys=[added_by_id])
    purchased_by: Mapped["User | None"] = relationship(foreign_keys=[purchased_by_id])
```

### Update model __init__.py

In `backend/app/models/__init__.py`:
- Import `GroceryItem` from `app.models.grocery_item`
- Add `"GroceryItem"` to `__all__`

No other model files change (the reverse relationships on `Household` and `User` are not needed; the existing models do not declare back-populates for every FK, and adding them would be a YAGNI violation).

### Alembic migration

Generate from the backend directory:

```bash
cd backend
uv run alembic revision --autogenerate -m "add_grocery_items_table"
```

Then verify it looks correct and run:

```bash
uv run alembic upgrade head
```

The migration must create the `grocery_items` table with:
- `id` UUID PK
- `household_id` UUID FK → `households.id` CASCADE
- `added_by_id` UUID FK → `users.id` SET NULL (nullable)
- `name` VARCHAR(200) NOT NULL
- `quantity` VARCHAR(100) nullable
- `notes` TEXT nullable
- `is_purchased` BOOLEAN NOT NULL DEFAULT false
- `purchased_by_id` UUID FK → `users.id` SET NULL (nullable)
- `purchased_at` TIMESTAMPTZ nullable
- `created_at` TIMESTAMPTZ NOT NULL DEFAULT now()

### Pydantic schemas

Create `backend/app/schemas/grocery.py`:

```python
"""Pydantic v2 schemas for grocery item endpoints."""
import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


class GroceryItemCreate(BaseModel):
    """Payload for adding a new item to the grocery list."""
    name: str = Field(min_length=1, max_length=200)
    quantity: Optional[str] = Field(None, max_length=100)
    notes: Optional[str] = None


class GroceryItemUpdate(BaseModel):
    """Payload for editing an existing item's details."""
    name: Optional[str] = Field(None, min_length=1, max_length=200)
    quantity: Optional[str] = Field(None, max_length=100)
    notes: Optional[str] = None


class GroceryItemResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    household_id: uuid.UUID
    added_by_id: Optional[uuid.UUID]
    added_by_name: Optional[str]  # joined from User.display_name
    name: str
    quantity: Optional[str]
    notes: Optional[str]
    is_purchased: bool
    purchased_by_id: Optional[uuid.UUID]
    purchased_by_name: Optional[str]  # joined from User.display_name
    purchased_at: Optional[datetime]
    created_at: datetime
```

**Acceptance criteria**:
- [ ] `backend/app/models/grocery_item.py` exists with the model above, following the same import/style conventions as `chore_definition.py`.
- [ ] `backend/app/models/__init__.py` imports and exports `GroceryItem`.
- [ ] `uv run alembic revision --autogenerate -m "add_grocery_items_table"` produces a clean migration.
- [ ] `uv run alembic upgrade head` succeeds against a running PostgreSQL instance.
- [ ] `backend/app/schemas/grocery.py` exists with all three Pydantic models.
- [ ] `uv run ruff check backend/app/models/grocery_item.py backend/app/schemas/grocery.py` passes with no errors.

---

## TASK-084: Backend — Groceries API router (CRUD + purchase/unpurchase)

**Domain**: Backend  
**Depends on**: TASK-083 (model + schemas exist)  
**Description**: Create the FastAPI router with six endpoints scoped under `/households/{household_id}/groceries`. All endpoints require active household membership (not admin-only — groceries are a shared collaborative space).

### Endpoints

All routes are on `APIRouter(prefix="/households/{household_id}/groceries", tags=["groceries"])`.

Create `backend/app/api/groceries.py`:

**1. POST /households/{household_id}/groceries — add item (any member)**

```python
@router.post("", response_model=GroceryItemResponse, status_code=status.HTTP_201_CREATED)
async def add_grocery_item(
    household_id: uuid.UUID,
    body: GroceryItemCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
    _membership: HouseholdMembership = Depends(require_household_member),
) -> GroceryItemResponse:
    item = GroceryItem(
        household_id=household_id,
        added_by_id=current_user.id,
        name=body.name,
        quantity=body.quantity,
        notes=body.notes,
    )
    db.add(item)
    await db.flush()
    await db.refresh(item)
    return _item_response(item, current_user.display_name, None)
```

**2. GET /households/{household_id}/groceries — list items (any member)**

Return all items ordered by `created_at` descending (newest first). No pagination needed for MVP (grocery lists are small).

```python
@router.get("", response_model=list[GroceryItemResponse])
async def list_grocery_items(
    household_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _membership: HouseholdMembership = Depends(require_household_member),
) -> list[GroceryItemResponse]:
    stmt = (
        select(GroceryItem, User.display_name, UserPurchased.display_name)
        .outerjoin(User, GroceryItem.added_by_id == User.id)
        .outerjoin(UserPurchased, GroceryItem.purchased_by_id == UserPurchased.id)
        .where(GroceryItem.household_id == household_id)
        .order_by(GroceryItem.created_at.desc())
    )
    result = await db.execute(stmt)
    return [
        _item_response(item, added_by_name, purchased_by_name)
        for item, added_by_name, purchased_by_name in result.all()
    ]
```

Note: `UserPurchased` is an alias for `User` since `purchased_by_id` also joins to `users`:

```python
from sqlalchemy.orm import aliased
UserPurchased = aliased(User)
```

**3. PATCH /households/{household_id}/groceries/{item_id} — update item (any member)**

```python
@router.patch("/{item_id}", response_model=GroceryItemResponse)
async def update_grocery_item(
    household_id: uuid.UUID,
    item_id: uuid.UUID,
    body: GroceryItemUpdate,
    db: AsyncSession = Depends(get_db),
    _membership: HouseholdMembership = Depends(require_household_member),
) -> GroceryItemResponse:
    item = await _get_item_or_404(item_id, household_id, db)
    update_data = body.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(item, field, value)
    await db.flush()
    await db.refresh(item)
    return await _build_item_response(item, db)
```

**4. DELETE /households/{household_id}/groceries/{item_id} — remove item (any member)**

```python
@router.delete("/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_grocery_item(
    household_id: uuid.UUID,
    item_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _membership: HouseholdMembership = Depends(require_household_member),
) -> None:
    item = await _get_item_or_404(item_id, household_id, db)
    await db.delete(item)
    await db.flush()
```

**5. POST /households/{household_id}/groceries/{item_id}/purchase — mark as purchased (any member)**

```python
@router.post("/{item_id}/purchase", response_model=GroceryItemResponse)
async def purchase_grocery_item(
    household_id: uuid.UUID,
    item_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
    _membership: HouseholdMembership = Depends(require_household_member),
) -> GroceryItemResponse:
    item = await _get_item_or_404(item_id, household_id, db)
    item.is_purchased = True
    item.purchased_by_id = current_user.id
    item.purchased_at = datetime.now(timezone.utc)
    await db.flush()
    await db.refresh(item)
    return await _build_item_response(item, db)
```

**6. POST /households/{household_id}/groceries/{item_id}/unpurchase — mark as not purchased (any member)**

```python
@router.post("/{item_id}/unpurchase", response_model=GroceryItemResponse)
async def unpurchase_grocery_item(
    household_id: uuid.UUID,
    item_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _membership: HouseholdMembership = Depends(require_household_member),
) -> GroceryItemResponse:
    item = await _get_item_or_404(item_id, household_id, db)
    item.is_purchased = False
    item.purchased_by_id = None
    item.purchased_at = None
    await db.flush()
    await db.refresh(item)
    return await _build_item_response(item, db)
```

### Internal helpers (in same file)

```python
async def _get_item_or_404(
    item_id: uuid.UUID,
    household_id: uuid.UUID,
    db: AsyncSession,
) -> GroceryItem:
    result = await db.execute(
        select(GroceryItem).where(
            GroceryItem.id == item_id,
            GroceryItem.household_id == household_id,
        )
    )
    item = result.scalar_one_or_none()
    if item is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                            detail="Grocery item not found")
    return item


def _item_response(
    item: GroceryItem,
    added_by_name: str | None,
    purchased_by_name: str | None,
) -> GroceryItemResponse:
    return GroceryItemResponse(
        id=item.id,
        household_id=item.household_id,
        added_by_id=item.added_by_id,
        added_by_name=added_by_name,
        name=item.name,
        quantity=item.quantity,
        notes=item.notes,
        is_purchased=item.is_purchased,
        purchased_by_id=item.purchased_by_id,
        purchased_by_name=purchased_by_name,
        purchased_at=item.purchased_at,
        created_at=item.created_at,
    )


async def _build_item_response(
    item: GroceryItem,
    db: AsyncSession,
) -> GroceryItemResponse:
    """Join User display names and build a full response."""
    added_by_name: str | None = None
    purchased_by_name: str | None = None
    if item.added_by_id:
        u = await db.get(User, item.added_by_id)
        if u:
            added_by_name = u.display_name
    if item.purchased_by_id:
        u = await db.get(User, item.purchased_by_id)
        if u:
            purchased_by_name = u.display_name
    return _item_response(item, added_by_name, purchased_by_name)
```

### Import the router name for main.py

At the bottom of the file:

```python
router = APIRouter(prefix="/households/{household_id}/groceries", tags=["groceries"])
```

Register it in main.py in TASK-085.

**Acceptance criteria**:
- [ ] `POST /households/{id}/groceries` creates an item, returns 201 with `GroceryItemResponse`.
- [ ] `GET /households/{id}/groceries` returns all items, newest first, with `added_by_name` and `purchased_by_name` populated.
- [ ] `PATCH /households/{id}/groceries/{item_id}` updates name/quantity/notes, returns 200.
- [ ] `DELETE /households/{id}/groceries/{item_id}` deletes the item, returns 204.
- [ ] `POST /.../groceries/{item_id}/purchase` marks purchased, sets `purchased_by_id` + `purchased_at`, returns 200.
- [ ] `POST /.../groceries/{item_id}/unpurchase` clears purchase fields, returns 200.
- [ ] Non-member receives 403 on all endpoints.
- [ ] Accessing another household's item returns 404.
- [ ] `uv run ruff check backend/app/api/groceries.py` passes.

---

## TASK-085: Backend — Register grocery router in main.py + integration tests

**Domain**: Backend  
**Depends on**: TASK-084 (router exists)  

### Register the router

In `backend/main.py`:

1. Add import near the top (alongside the other router imports):
```python
from app.api.groceries import router as groceries_router
```

2. Add `app.include_router(groceries_router)` alongside the other `include_router` calls.

### Integration tests

Create `backend/tests/test_groceries.py`. Follow the fixture patterns from existing tests (`test_chores.py` style). Tests must cover:

**Setup fixture**: create a household, two members, and auth tokens for both.

**Test cases** (one test function each):
1. `test_add_item` — POST creates an item, response has all fields, `is_purchased=False`.
2. `test_list_items_ordered_newest_first` — Add 3 items, verify list order.
3. `test_update_item_name` — PATCH changes name, verify it's reflected.
4. `test_update_item_quantity_and_notes` — PATCH both fields, verify.
5. `test_delete_item` — DELETE returns 204, item is gone from list.
6. `test_purchase_item` — POST /purchase sets `is_purchased=True`, `purchased_by_id`, `purchased_at`.
7. `test_unpurchase_item` — POST /unpurchase clears purchase fields.
8. `test_unauthenticated_rejected` — No token → 401.
9. `test_non_member_rejected` — Member of different household → 403.
10. `test_wrong_household_404` — Valid member, but item belongs to another household → 404.
11. `test_add_item_empty_name` — name="" → 422 validation error.
12. `test_purchase_already_purchased_idempotent` — Purchase twice, second call succeeds (just overwrites).
13. `test_update_nonexistent_item_404` — PATCH unknown UUID → 404.

Use `pytest-asyncio`, `httpx.AsyncClient`, and the existing `test_client` fixtures. Pattern reference:

```python
import pytest
from httpx import AsyncClient, ASGITransport
from app.main import app

@pytest.fixture
async def household_with_members(db, test_user, test_user2):
    # Create household, add both users as members
    ...

@pytest.mark.asyncio
async def test_add_item(household_with_members, client):
    response = await client.post(
        f"/households/{household_id}/groceries",
        json={"name": "Milk", "quantity": "2 cartons"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "Milk"
    assert data["is_purchased"] is False
```

**Acceptance criteria**:
- [ ] `app.include_router(groceries_router)` is present in `backend/main.py`.
- [ ] `backend/tests/test_groceries.py` exists with all 13 test cases.
- [ ] `uv run pytest tests/test_groceries.py -v` — all 13 tests pass.
- [ ] `uv run ruff check backend/main.py backend/tests/test_groceries.py` passes.

---

## TASK-086: Flutter — Grocery models, API endpoint constants, and Riverpod provider

**Domain**: Frontend (Flutter)  
**Depends on**: TASK-085 (backend API fully functional)  

### Directory setup

Create:
```
flutter_app/lib/features/groceries/
  models/
    grocery_item_model.dart
  providers/
    groceries_provider.dart
  screens/          (built in TASK-087)
  widgets/          (built in TASK-087)
```

### GroceryItem model

Create `flutter_app/lib/features/groceries/models/grocery_item_model.dart`:

```dart
class GroceryItemModel {
  const GroceryItemModel({
    required this.id,
    required this.householdId,
    this.addedById,
    this.addedByName,
    required this.name,
    this.quantity,
    this.notes,
    required this.isPurchased,
    this.purchasedById,
    this.purchasedByName,
    this.purchasedAt,
    required this.createdAt,
  });

  final String id;
  final String householdId;
  final String? addedById;
  final String? addedByName;
  final String name;
  final String? quantity;
  final String? notes;
  final bool isPurchased;
  final String? purchasedById;
  final String? purchasedByName;
  final DateTime? purchasedAt;
  final DateTime createdAt;

  factory GroceryItemModel.fromJson(Map<String, dynamic> json) {
    return GroceryItemModel(
      id: json['id'] as String,
      householdId: json['household_id'] as String,
      addedById: json['added_by_id'] as String?,
      addedByName: json['added_by_name'] as String?,
      name: json['name'] as String,
      quantity: json['quantity'] as String?,
      notes: json['notes'] as String?,
      isPurchased: json['is_purchased'] as bool,
      purchasedById: json['purchased_by_id'] as String?,
      purchasedByName: json['purchased_by_name'] as String?,
      purchasedAt: json['purchased_at'] != null
          ? DateTime.parse(json['purchased_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() { ... }
}
```

### API endpoint constants

In `flutter_app/lib/core/api/api_endpoints.dart`, add:

```dart
static String householdGroceries(String id) => '/households/$id/groceries';
static String groceryItem(String hId, String itemId) =>
    '/households/$hId/groceries/$itemId';
static String groceryPurchase(String hId, String itemId) =>
    '/households/$hId/groceries/$itemId/purchase';
static String groceryUnpurchase(String hId, String itemId) =>
    '/households/$hId/groceries/$itemId/unpurchase';
```

### Riverpod provider

Create `flutter_app/lib/features/groceries/providers/groceries_provider.dart`:

Pattern: `FamilyAsyncNotifier<List<GroceryItemModel>, String>` keyed on `householdId`, modeled on `ChoresNotifier` but simpler (no pagination, one page per household). Methods needed:

- `build(String householdId)` — fetch all items via `GET /households/{id}/groceries`
- `addItem(String name, String? quantity, String? notes)` — POST, then `ref.invalidateSelf(); await future;`
- `updateItem(String itemId, Map<String, dynamic> body)` — PATCH, then invalidate
- `deleteItem(String itemId)` — DELETE, then invalidate
- `togglePurchased(GroceryItemModel item)` — optimistic update (flip `isPurchased`), POST purchase or unpurchase, revert on error
- `refresh()` — `ref.invalidateSelf(); await future;`

The provider uses `dio` from `ref.read(dioProvider)`, same as all existing providers.

**Acceptance criteria**:
- [ ] `grocery_item_model.dart` exists with `fromJson`/`toJson` matching the backend schema.
- [ ] `api_endpoints.dart` has the four new endpoint helpers.
- [ ] `groceries_provider.dart` compiles and follows Riverpod `FamilyAsyncNotifier` pattern.
- [ ] `flutter analyze --no-pub --no-fatal-infos` from `flutter_app/` passes with zero errors.

---

## TASK-087: Flutter — Grocery list screen, bottom nav tab, router, and tests

**Domain**: Frontend (Flutter)  
**Depends on**: TASK-086 (provider + model exist)  

### Grocery list screen

Create `flutter_app/lib/features/groceries/screens/grocery_list_screen.dart`.

Design: A ConsumerStatefulWidget receiving `householdId`. Shows:
- AppBar with title "Groceries"
- An "Add item" text field row at the top (TextField + IconButton to submit)
- Below: a ListView of `GroceryItemModel` items, each showing:
  - Checkbox (tappable → toggles purchase/unpurchase)
  - Item name (with strikethrough text decoration if `isPurchased`)
  - Quantity in grey text next to name (if set)
  - Notes as a subtitle (if set)
  - Purchased-by line: "Purchased by {name}" in green/grey small text (if purchased)
  - Swipe-to-delete (Dismissible) or trailing delete IconButton
- Tap on an item opens an inline edit (bottom sheet or dialog) for name/quantity/notes
- Empty state: "No items yet — add one above"

Follow the visual style of `chore_list_screen.dart`: teal color palette, card-based layout, `AccessibleTap` for 48dp touch targets.

Import `shared/widgets/accessible_tap.dart`, `shared/widgets/loading_widget.dart`, `shared/widgets/error_widget.dart`.

### Wire into bottom navigation

The household dashboard currently has 3 tabs: Chores, My Chores, Leaderboard.

In `flutter_app/lib/features/household/screens/household_dashboard_screen.dart` (let me check the exact layout):
- Add "Groceries" as the 4th tab with a shopping cart icon (`Icons.shopping_cart`)
- When selected, render `GroceryListScreen(householdId: householdId)`

### Router

In `flutter_app/lib/router/app_router.dart`:
- Add route name constant: `static const String groceryList = 'grocery-list';`
- Add `GoRoute` entry (tab-level, fade transition, same pattern as choreList):
```dart
GoRoute(
  path: '/households/:householdId/groceries',
  name: AppRoutes.groceryList,
  pageBuilder: (context, state) {
    final id = state.pathParameters['householdId']!;
    return _tabPage(state, GroceryListScreen(householdId: id));
  },
),
```

### Widget tests

Create `flutter_app/test/grocery_list_screen_test.dart`:

Minimal test that:
1. Renders the screen with mock provider data
2. Shows "No items yet" when list is empty
3. Shows items when data is present
4. Tapping the checkbox toggles purchase state

Use `flutter_test` with `ProviderScope` overrides to inject mock data.

**Acceptance criteria**:
- [ ] Grocery list screen renders and follows the teal visual style of existing screens.
- [ ] Bottom nav shows 4 tabs: Chores, My Chores, Leaderboard, Groceries.
- [ ] Adding an item creates it via the API and refreshes the list.
- [ ] Tapping the checkbox toggles purchase/unpurchase with optimistic update.
- [ ] Deleting an item removes it from the list.
- [ ] Editing an item's name/quantity/notes updates it via the API.
- [ ] Purchased items show with strikethrough text and "Purchased by {name}".
- [ ] All touch targets are ≥48dp (use `AccessibleTap`).
- [ ] `flutter analyze --no-pub --no-fatal-infos` passes.
- [ ] `flutter test --no-pub` passes (existing + new tests).
