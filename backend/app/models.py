from datetime import date, datetime
from decimal import Decimal
from uuid import uuid4

from sqlalchemy import Boolean, Date, DateTime, ForeignKey, Numeric, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .database import Base


def new_id() -> str:
    return str(uuid4())


class Household(Base):
    __tablename__ = "households"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    name: Mapped[str] = mapped_column(String(120))
    pin: Mapped[str] = mapped_column(String(128))
    access_code: Mapped[str] = mapped_column(String(24), unique=True)
    default_currency: Mapped[str] = mapped_column(String(3), default="RSD")
    creator_id: Mapped[str] = mapped_column(ForeignKey("profiles.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    members: Mapped[list["Membership"]] = relationship(back_populates="household", cascade="all, delete-orphan")
    categories: Mapped[list["Category"]] = relationship(back_populates="household", cascade="all, delete-orphan")
    expenses: Mapped[list["Expense"]] = relationship(back_populates="household", cascade="all, delete-orphan")


class Profile(Base):
    __tablename__ = "profiles"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    name: Mapped[str] = mapped_column(String(80))
    avatar: Mapped[str] = mapped_column(String(40), default="sun")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class Membership(Base):
    __tablename__ = "memberships"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    household_id: Mapped[str] = mapped_column(ForeignKey("households.id"))
    profile_id: Mapped[str] = mapped_column(ForeignKey("profiles.id"))
    role_name: Mapped[str] = mapped_column(String(40), default="Član")
    is_admin: Mapped[bool] = mapped_column(Boolean, default=False)
    approved: Mapped[bool] = mapped_column(Boolean, default=True)

    household: Mapped[Household] = relationship(back_populates="members")
    profile: Mapped[Profile] = relationship()


class Category(Base):
    __tablename__ = "categories"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    household_id: Mapped[str] = mapped_column(ForeignKey("households.id"))
    proposed_by: Mapped[str | None] = mapped_column(ForeignKey("profiles.id"), nullable=True)
    name: Mapped[str] = mapped_column(String(80))
    description: Mapped[str] = mapped_column(Text, default="")
    color: Mapped[str] = mapped_column(String(20), default="#5F8D7A")
    icon: Mapped[str] = mapped_column(String(30), default="wallet")
    archived: Mapped[bool] = mapped_column(Boolean, default=False)
    approved: Mapped[bool] = mapped_column(Boolean, default=True)

    household: Mapped[Household] = relationship(back_populates="categories")


class Budget(Base):
    __tablename__ = "budgets"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    household_id: Mapped[str] = mapped_column(ForeignKey("households.id"))
    category_id: Mapped[str | None] = mapped_column(ForeignKey("categories.id"), nullable=True)
    amount: Mapped[Decimal] = mapped_column(Numeric(12, 2))
    currency: Mapped[str] = mapped_column(String(3), default="RSD")
    period_start: Mapped[date] = mapped_column(Date)
    period_end: Mapped[date] = mapped_column(Date)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class Expense(Base):
    __tablename__ = "expenses"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    household_id: Mapped[str] = mapped_column(ForeignKey("households.id"))
    author_id: Mapped[str] = mapped_column(ForeignKey("profiles.id"))
    author_name: Mapped[str] = mapped_column(String(80), default="")
    category_id: Mapped[str] = mapped_column(ForeignKey("categories.id"))
    amount: Mapped[Decimal] = mapped_column(Numeric(12, 2))
    currency: Mapped[str] = mapped_column(String(3), default="RSD")
    description: Mapped[str] = mapped_column(String(240), default="")
    is_shared: Mapped[bool] = mapped_column(Boolean, default=False)
    expense_date: Mapped[date] = mapped_column(Date, default=date.today)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    household: Mapped[Household] = relationship(back_populates="expenses")
