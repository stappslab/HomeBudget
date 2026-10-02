from datetime import date
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field


class ProfileCreate(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    avatar: str = "sun"


class ProfileRead(ProfileCreate):
    model_config = ConfigDict(from_attributes=True)
    id: str


class HouseholdCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    pin: str = Field(min_length=4, max_length=128)
    default_currency: str = Field(default="RSD", pattern="^(RSD|EUR|USD)$")
    creator: ProfileCreate


class HouseholdJoin(BaseModel):
    profile: ProfileCreate
    access_code: str = Field(min_length=4, max_length=24)


class HouseholdRead(BaseModel):
    id: str
    name: str
    default_currency: str
    access_code: str
    creator_id: str


class MembershipRead(BaseModel):
    profile_id: str
    profile_name: str
    role_name: str
    is_admin: bool
    approved: bool


class JoinedHouseholdRead(MembershipRead):
    household_id: str
    household_name: str
    default_currency: str


class AccessCodeRead(BaseModel):
    household_id: str
    access_code: str


class MembershipUpdate(BaseModel):
    role_name: str = Field(min_length=1, max_length=40)
    is_admin: bool = False


class BudgetCreate(BaseModel):
    category_id: str | None = None
    amount: Decimal = Field(gt=0)
    currency: str = Field(default="RSD", pattern="^(RSD|EUR|USD)$")
    period_start: date
    period_end: date


class BudgetRead(BudgetCreate):
    model_config = ConfigDict(from_attributes=True)
    id: str
    household_id: str


class ExpenseCreate(BaseModel):
    author_id: str
    author_name: str = Field(default="", max_length=80)
    category_id: str
    amount: Decimal = Field(gt=0)
    currency: str = Field(default="RSD", pattern="^(RSD|EUR|USD)$")
    description: str = Field(default="", max_length=240)
    is_shared: bool = False
    expense_date: date = Field(default_factory=date.today)


class ExpenseRead(ExpenseCreate):
    model_config = ConfigDict(from_attributes=True)
    id: str
    household_id: str


class CategoryCreate(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    description: str = ""
    color: str = "#5F8D7A"
    icon: str = "wallet"


class CategoryRead(CategoryCreate):
    model_config = ConfigDict(from_attributes=True)
    id: str
    household_id: str
    archived: bool
    approved: bool
