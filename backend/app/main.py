from datetime import date
from secrets import token_urlsafe

from fastapi import Depends, FastAPI, HTTPException, status
from sqlalchemy import case, func, select
from sqlalchemy.orm import Session

from .database import Base, engine, get_db, run_sqlite_migrations
from .models import Budget, Category, Expense, Household, Membership, Profile
from .schemas import (
    CategoryCreate,
    CategoryRead,
    AccessCodeRead,
    BudgetCreate,
    BudgetRead,
    ExpenseCreate,
    ExpenseRead,
    JoinedHouseholdRead,
    HouseholdCreate,
    HouseholdJoin,
    HouseholdRead,
    MembershipRead,
    MembershipUpdate,
)

Base.metadata.create_all(bind=engine)
run_sqlite_migrations()
app = FastAPI(title="HomeBudget API", version="0.1.0")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "homebudget"}


@app.post("/households", response_model=HouseholdRead, status_code=status.HTTP_201_CREATED)
def create_household(payload: HouseholdCreate, db: Session = Depends(get_db)) -> Household:
    profile = Profile(name=payload.creator.name, avatar=payload.creator.avatar)
    db.add(profile)
    db.flush()
    household = Household(
        name=payload.name,
        pin=payload.pin,
        access_code=token_urlsafe(8),
        default_currency=payload.default_currency,
        creator_id=profile.id,
    )
    db.add(household)
    db.flush()
    db.add(Membership(household_id=household.id, profile_id=profile.id, role_name="Kreator", is_admin=True))
    for name in ("Stan", "Prodavnica", "Hrana", "Benzin", "Pokloni", "Odeća i obuća", "Izlasci", "Ostalo"):
        db.add(Category(household_id=household.id, name=name))
    db.commit()
    db.refresh(household)
    return HouseholdRead(
        id=household.id,
        name=household.name,
        default_currency=household.default_currency,
        access_code=household.access_code,
        creator_id=household.creator_id,
    )


@app.post("/households/join", response_model=JoinedHouseholdRead, status_code=status.HTTP_201_CREATED)
def join_household(payload: HouseholdJoin, db: Session = Depends(get_db)) -> JoinedHouseholdRead:
    household = db.scalar(select(Household).where(Household.access_code == payload.access_code))
    if household is None:
        raise HTTPException(status_code=404, detail="Invalid or expired access code")
    profile = Profile(name=payload.profile.name, avatar=payload.profile.avatar)
    db.add(profile)
    db.flush()
    membership = Membership(
        household_id=household.id,
        profile_id=profile.id,
        role_name="Član",
        approved=False,
    )
    household.access_code = token_urlsafe(8)
    db.add(membership)
    db.commit()
    return JoinedHouseholdRead(
        profile_id=profile.id,
        profile_name=profile.name,
        role_name=membership.role_name,
        is_admin=membership.is_admin,
        approved=membership.approved,
        household_id=household.id,
        household_name=household.name,
        default_currency=household.default_currency,
    )


@app.get("/households/{household_id}/members", response_model=list[MembershipRead])
def list_members(household_id: str, db: Session = Depends(get_db)) -> list[MembershipRead]:
    memberships = db.scalars(select(Membership).where(Membership.household_id == household_id)).all()
    return [
        MembershipRead(
            profile_id=membership.profile_id,
            profile_name=membership.profile.name,
            role_name=membership.role_name,
            is_admin=membership.is_admin,
            approved=membership.approved,
        )
        for membership in memberships
    ]


@app.get("/households/{household_id}/access-code", response_model=AccessCodeRead)
def get_access_code(household_id: str, admin_id: str, db: Session = Depends(get_db)) -> AccessCodeRead:
    require_admin(household_id, admin_id, db)
    household = db.get(Household, household_id)
    if household is None:
        raise HTTPException(status_code=404, detail="Household not found")
    return AccessCodeRead(household_id=household.id, access_code=household.access_code)


@app.post("/households/{household_id}/access-code", response_model=AccessCodeRead)
def regenerate_access_code(household_id: str, admin_id: str, db: Session = Depends(get_db)) -> AccessCodeRead:
    require_admin(household_id, admin_id, db)
    household = db.get(Household, household_id)
    if household is None:
        raise HTTPException(status_code=404, detail="Household not found")
    household.access_code = token_urlsafe(8)
    db.commit()
    return AccessCodeRead(household_id=household.id, access_code=household.access_code)


def require_admin(household_id: str, profile_id: str, db: Session) -> None:
    membership = db.scalar(
        select(Membership).where(
            Membership.household_id == household_id,
            Membership.profile_id == profile_id,
            Membership.approved.is_(True),
            Membership.is_admin.is_(True),
        )
    )
    if membership is None:
        raise HTTPException(status_code=403, detail="Administrator approval is required")


@app.post("/households/{household_id}/members/{profile_id}/approve", response_model=MembershipRead)
def approve_member(
    household_id: str,
    profile_id: str,
    admin_id: str,
    db: Session = Depends(get_db),
) -> MembershipRead:
    require_admin(household_id, admin_id, db)
    membership = db.scalar(
        select(Membership).where(Membership.household_id == household_id, Membership.profile_id == profile_id)
    )
    if membership is None:
        raise HTTPException(status_code=404, detail="Member not found")
    membership.approved = True
    db.commit()
    db.refresh(membership)
    return MembershipRead(
        profile_id=membership.profile_id,
        profile_name=membership.profile.name,
        role_name=membership.role_name,
        is_admin=membership.is_admin,
        approved=membership.approved,
    )


@app.patch("/households/{household_id}/members/{profile_id}", response_model=MembershipRead)
def update_member(
    household_id: str,
    profile_id: str,
    payload: MembershipUpdate,
    admin_id: str,
    db: Session = Depends(get_db),
) -> MembershipRead:
    require_admin(household_id, admin_id, db)
    household = db.get(Household, household_id)
    membership = db.scalar(
        select(Membership).where(Membership.household_id == household_id, Membership.profile_id == profile_id)
    )
    if household is None or membership is None:
        raise HTTPException(status_code=404, detail="Member not found")
    if profile_id == household.creator_id and (not payload.is_admin or payload.role_name != "Kreator"):
        raise HTTPException(status_code=422, detail="Household creator must remain the creator administrator")
    membership.role_name = payload.role_name
    membership.is_admin = payload.is_admin or profile_id == household.creator_id
    db.commit()
    db.refresh(membership)
    return MembershipRead(
        profile_id=membership.profile_id,
        profile_name=membership.profile.name,
        role_name=membership.role_name,
        is_admin=membership.is_admin,
        approved=membership.approved,
    )


@app.get("/households/{household_id}/categories", response_model=list[CategoryRead])
def list_categories(household_id: str, db: Session = Depends(get_db)) -> list[Category]:
    return list(db.scalars(select(Category).where(Category.household_id == household_id, Category.archived.is_(False))))


@app.post("/households/{household_id}/categories", response_model=CategoryRead, status_code=status.HTTP_201_CREATED)
def create_category(
    household_id: str,
    payload: CategoryCreate,
    profile_id: str,
    db: Session = Depends(get_db),
) -> Category:
    if db.get(Household, household_id) is None:
        raise HTTPException(status_code=404, detail="Household not found")
    membership = db.scalar(
        select(Membership).where(
            Membership.household_id == household_id,
            Membership.profile_id == profile_id,
            Membership.approved.is_(True),
        )
    )
    if membership is None:
        raise HTTPException(status_code=403, detail="Approved household membership is required")
    category = Category(
        household_id=household_id,
        proposed_by=profile_id,
        approved=membership.is_admin,
        **payload.model_dump(),
    )
    db.add(category)
    db.commit()
    db.refresh(category)
    return category


@app.post("/households/{household_id}/categories/{category_id}/approve", response_model=CategoryRead)
def approve_category(
    household_id: str,
    category_id: str,
    admin_id: str,
    db: Session = Depends(get_db),
) -> Category:
    require_admin(household_id, admin_id, db)
    category = db.scalar(
        select(Category).where(Category.id == category_id, Category.household_id == household_id)
    )
    if category is None:
        raise HTTPException(status_code=404, detail="Category not found")
    category.approved = True
    db.commit()
    db.refresh(category)
    return category


@app.post("/households/{household_id}/budgets", response_model=BudgetRead, status_code=status.HTTP_201_CREATED)
def create_budget(
    household_id: str,
    payload: BudgetCreate,
    admin_id: str,
    db: Session = Depends(get_db),
) -> Budget:
    require_admin(household_id, admin_id, db)
    if payload.period_end < payload.period_start:
        raise HTTPException(status_code=422, detail="Budget period ends before it starts")
    if payload.category_id is not None:
        category = db.scalar(
            select(Category).where(Category.id == payload.category_id, Category.household_id == household_id)
        )
        if category is None:
            raise HTTPException(status_code=404, detail="Category not found")
    budget = Budget(household_id=household_id, **payload.model_dump())
    db.add(budget)
    db.commit()
    db.refresh(budget)
    return budget


@app.get("/households/{household_id}/budgets", response_model=list[BudgetRead])
def list_budgets(household_id: str, db: Session = Depends(get_db)) -> list[Budget]:
    return list(db.scalars(select(Budget).where(Budget.household_id == household_id)))


@app.get("/households/{household_id}/expenses", response_model=list[ExpenseRead])
def list_expenses(household_id: str, db: Session = Depends(get_db)) -> list[Expense]:
    return list(db.scalars(select(Expense).where(Expense.household_id == household_id).order_by(Expense.expense_date.desc())))


@app.get("/households/{household_id}/expenses/summary")
def expense_summary(
    household_id: str,
    start: date,
    end: date,
    db: Session = Depends(get_db),
) -> dict[str, object]:
    if end < start:
        raise HTTPException(status_code=422, detail="Summary period ends before it starts")
    totals = db.execute(
        select(
            func.coalesce(func.sum(Expense.amount), 0),
            func.coalesce(func.sum(case((Expense.is_shared.is_(True), Expense.amount), else_=0)), 0),
        ).where(
            Expense.household_id == household_id,
            Expense.expense_date.between(start, end),
        )
    ).one()
    total = float(totals[0])
    shared = float(totals[1])
    authors = db.execute(
        select(
            func.coalesce(func.nullif(Expense.author_name, ""), Profile.name).label("author_name"),
            func.coalesce(func.sum(Expense.amount), 0).label("total"),
            func.coalesce(func.sum(case((Expense.is_shared.is_(True), Expense.amount), else_=0)), 0).label("shared"),
        )
        .join(Profile, Profile.id == Expense.author_id)
        .where(Expense.household_id == household_id, Expense.expense_date.between(start, end))
        .group_by(func.coalesce(func.nullif(Expense.author_name, ""), Profile.name))
        .order_by(func.sum(Expense.amount).desc())
    ).all()
    running = db.execute(
        select(
            func.coalesce(func.nullif(Expense.author_name, ""), Profile.name).label("author_name"),
            func.coalesce(func.sum(Expense.amount), 0).label("shared"),
        )
        .join(Profile, Profile.id == Expense.author_id)
        .where(Expense.household_id == household_id, Expense.is_shared.is_(True))
        .group_by(func.coalesce(func.nullif(Expense.author_name, ""), Profile.name))
        .order_by(func.sum(Expense.amount).desc())
    ).all()
    return {
        "total": total,
        "shared": shared,
        "personal": total - shared,
        "authors": [dict(row._mapping) for row in authors],
        "running": [dict(row._mapping) for row in running],
    }


@app.post("/households/{household_id}/expenses", response_model=ExpenseRead, status_code=status.HTTP_201_CREATED)
def create_expense(household_id: str, payload: ExpenseCreate, db: Session = Depends(get_db)) -> Expense:
    if db.get(Household, household_id) is None:
        raise HTTPException(status_code=404, detail="Household not found")
    membership = db.scalar(
        select(Membership).where(
            Membership.household_id == household_id,
            Membership.profile_id == payload.author_id,
            Membership.approved.is_(True),
        )
    )
    if membership is None:
        raise HTTPException(status_code=403, detail="Approved household membership is required")
    category = db.scalar(
        select(Category).where(
            Category.id == payload.category_id,
            Category.household_id == household_id,
            Category.archived.is_(False),
            Category.approved.is_(True),
        )
    )
    if category is None:
        raise HTTPException(status_code=404, detail="Approved category not found")
    expense = Expense(household_id=household_id, **payload.model_dump())
    db.add(expense)
    db.commit()
    db.refresh(expense)
    return expense


@app.patch("/households/{household_id}/expenses/{expense_id}", response_model=ExpenseRead)
def update_expense(
    household_id: str,
    expense_id: str,
    payload: ExpenseCreate,
    db: Session = Depends(get_db),
) -> Expense:
    expense = db.scalar(
        select(Expense).where(Expense.id == expense_id, Expense.household_id == household_id)
    )
    if expense is None:
        raise HTTPException(status_code=404, detail="Expense not found")
    if expense.author_id != payload.author_id:
        raise HTTPException(status_code=403, detail="Only the author can edit this expense")
    for key, value in payload.model_dump().items():
        setattr(expense, key, value)
    db.commit()
    db.refresh(expense)
    return expense


@app.delete("/households/{household_id}/expenses/{expense_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_expense(
    household_id: str,
    expense_id: str,
    author_id: str,
    db: Session = Depends(get_db),
) -> None:
    expense = db.scalar(
        select(Expense).where(Expense.id == expense_id, Expense.household_id == household_id)
    )
    if expense is None:
        raise HTTPException(status_code=404, detail="Expense not found")
    if expense.author_id != author_id:
        raise HTTPException(status_code=403, detail="Only the author can delete this expense")
    db.delete(expense)
    db.commit()
