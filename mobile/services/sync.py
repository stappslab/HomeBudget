from dataclasses import dataclass

from .api import ApiClient
from local_db.local_db import LocalDatabase


@dataclass
class SyncResult:
    uploaded: int
    pending: int
    message: str


class SyncService:
    def __init__(self, database: LocalDatabase, api: ApiClient | None = None):
        self.database = database
        self.api = api or ApiClient()

    def sync(self) -> SyncResult:
        household = self.database.household()
        if household is None:
            return SyncResult(0, 0, "Household nije kreiran")
        try:
            if not household["remote_id"]:
                remote = self.api.create_household(
                    household["name"],
                    household["pin"],
                    household["profile_name"],
                    household["default_currency"],
                )
                self.database.set_remote_identity(remote["id"], remote["creator_id"])
                household = self.database.household()
            categories = {item["name"]: item["id"] for item in self.api.categories(household["remote_id"])}
            uploaded = 0
            for expense in self.database.pending_expenses():
                category_id = categories.get(expense["category"])
                if category_id is None:
                    continue
                self.api.create_expense(
                    household["remote_id"],
                    {
                        "author_id": household["remote_profile_id"],
                        "author_name": expense["author_name"],
                        "category_id": category_id,
                        "amount": expense["amount"],
                        "currency": expense["currency"],
                        "description": expense["description"],
                        "is_shared": bool(expense["is_shared"]),
                        "expense_date": expense["expense_date"],
                    },
                )
                self.database.mark_synced(expense["id"])
                uploaded += 1
            pending = len(self.database.pending_expenses())
            return SyncResult(uploaded, pending, "Sinhronizacija završena")
        except Exception:
            return SyncResult(0, len(self.database.pending_expenses()), "Sinhronizacija čeka internet")