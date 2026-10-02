from datetime import date
from pathlib import Path
from uuid import uuid4
import sqlite3


class LocalDatabase:
    def __init__(self, path: str | None = None):
        db_path = Path(path or "homebudget_local.sqlite3")
        self.connection = sqlite3.connect(db_path)
        self.connection.row_factory = sqlite3.Row
        self.connection.executescript(
            """
            CREATE TABLE IF NOT EXISTS household (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                profile_name TEXT NOT NULL,
                default_currency TEXT NOT NULL,
                pin TEXT NOT NULL,
                remote_id TEXT,
                remote_profile_id TEXT,
                language TEXT NOT NULL DEFAULT 'sr',
                theme TEXT NOT NULL DEFAULT 'dark'
            );
            CREATE TABLE IF NOT EXISTS categories (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                archived INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS expenses (
                id TEXT PRIMARY KEY,
                amount REAL NOT NULL,
                currency TEXT NOT NULL,
                category TEXT NOT NULL,
                description TEXT NOT NULL,
                is_shared INTEGER NOT NULL,
                expense_date TEXT NOT NULL,
                synced INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS budgets (
                id TEXT PRIMARY KEY,
                amount REAL NOT NULL,
                currency TEXT NOT NULL,
                category TEXT,
                period TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS app_state (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            """
        )
        self._migrate_household()
        self._migrate_expenses()
        self.connection.commit()

    def _migrate_household(self) -> None:
        columns = {row[1] for row in self.connection.execute("PRAGMA table_info(household)")}
        if "remote_id" not in columns:
            self.connection.execute("ALTER TABLE household ADD COLUMN remote_id TEXT")
        if "remote_profile_id" not in columns:
            self.connection.execute("ALTER TABLE household ADD COLUMN remote_profile_id TEXT")
        if "language" not in columns:
            self.connection.execute("ALTER TABLE household ADD COLUMN language TEXT NOT NULL DEFAULT 'sr'")
        if "theme" not in columns:
            self.connection.execute("ALTER TABLE household ADD COLUMN theme TEXT NOT NULL DEFAULT 'dark'")

    def _migrate_expenses(self) -> None:
        columns = {row[1] for row in self.connection.execute("PRAGMA table_info(expenses)")}
        if "author_name" not in columns:
            profile = self.household()
            author = profile["profile_name"] if profile else ""
            self.connection.execute("ALTER TABLE expenses ADD COLUMN author_name TEXT NOT NULL DEFAULT ''")
            self.connection.execute("UPDATE expenses SET author_name = ? WHERE author_name = ''", (author,))

    def household(self):
        return self.connection.execute("SELECT * FROM household LIMIT 1").fetchone()

    def valid_pin(self, pin: str) -> bool:
        household = self.household()
        return household is not None and household["pin"] == pin

    def set_default_currency(self, currency: str) -> None:
        self.connection.execute("UPDATE household SET default_currency = ?", (currency,))
        self.connection.commit()

    def set_language(self, language: str) -> None:
        self.connection.execute("UPDATE household SET language = ?", (language,))
        self.connection.commit()

    def set_theme(self, theme: str) -> None:
        self.connection.execute("UPDATE household SET theme = ?", (theme,))
        self.connection.commit()

    def create_household(self, name: str, profile_name: str, currency: str, pin: str) -> None:
        self.connection.execute(
            "INSERT INTO household (id, name, profile_name, default_currency, pin) VALUES (?, ?, ?, ?, ?)",
            (str(uuid4()), name, profile_name, currency, pin),
        )
        for category in ("Stan", "Prodavnica", "Hrana", "Benzin", "Pokloni", "Odeća i obuća", "Izlasci", "Ostalo"):
            self.connection.execute("INSERT INTO categories VALUES (?, ?, 0)", (str(uuid4()), category))
        self.connection.commit()

    def create_joined_household(
        self,
        name: str,
        profile_name: str,
        currency: str,
        access_code: str,
        remote_id: str,
        remote_profile_id: str,
    ) -> None:
        self.connection.execute(
            "INSERT INTO household (id, name, profile_name, default_currency, pin, remote_id, remote_profile_id) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (str(uuid4()), name, profile_name, currency, access_code, remote_id, remote_profile_id),
        )
        for category in ("Stan", "Prodavnica", "Hrana", "Benzin", "Pokloni", "Odeća i obuća", "Izlasci", "Ostalo"):
            self.connection.execute("INSERT INTO categories VALUES (?, ?, 0)", (str(uuid4()), category))
        self.connection.commit()

    def categories(self) -> list[str]:
        rows = self.connection.execute("SELECT name FROM categories WHERE archived = 0 ORDER BY name").fetchall()
        return [row["name"] for row in rows]

    def all_categories(self) -> list[sqlite3.Row]:
        return list(self.connection.execute("SELECT * FROM categories ORDER BY archived, name"))

    def add_category(self, name: str) -> None:
        self.connection.execute("INSERT INTO categories VALUES (?, ?, 0)", (str(uuid4()), name.strip()))
        self.connection.commit()

    def rename_category(self, current_name: str, new_name: str) -> None:
        self.connection.execute("UPDATE categories SET name = ? WHERE name = ?", (new_name.strip(), current_name))
        self.connection.execute("UPDATE expenses SET category = ? WHERE category = ?", (new_name.strip(), current_name))
        self.connection.commit()

    def archive_category(self, name: str) -> None:
        self.connection.execute("UPDATE categories SET archived = 1 WHERE name = ?", (name,))
        self.connection.commit()

    def set_monthly_budget(self, amount: float, currency: str) -> None:
        self.connection.execute("DELETE FROM budgets WHERE category IS NULL AND period = 'monthly'")
        self.connection.execute(
            "INSERT INTO budgets VALUES (?, ?, ?, NULL, 'monthly')",
            (str(uuid4()), amount, currency),
        )
        self.connection.commit()

    def set_category_budget(self, category: str, amount: float, currency: str) -> bool:
        total_budget = self.monthly_budget()
        current = self.connection.execute(
            "SELECT COALESCE(SUM(amount), 0) AS total FROM budgets WHERE category IS NOT NULL AND period = 'monthly' AND category != ?",
            (category,),
        ).fetchone()["total"]
        if total_budget <= 0 or float(current) + amount > total_budget:
            return False
        self.connection.execute(
            "DELETE FROM budgets WHERE category = ? AND period = 'monthly'", (category,)
        )
        self.connection.execute(
            "INSERT INTO budgets VALUES (?, ?, ?, ?, 'monthly')",
            (str(uuid4()), amount, currency, category),
        )
        self.connection.commit()
        return True

    def category_budgets(self) -> dict[str, float]:
        rows = self.connection.execute(
            "SELECT category, amount FROM budgets WHERE category IS NOT NULL AND period = 'monthly'"
        ).fetchall()
        return {row["category"]: float(row["amount"]) for row in rows}

    def monthly_budget(self) -> float:
        row = self.connection.execute(
            "SELECT amount FROM budgets WHERE category IS NULL AND period = 'monthly' LIMIT 1"
        ).fetchone()
        return float(row["amount"]) if row else 0.0

    def add_expense(self, amount: float, currency: str, category: str, description: str, is_shared: bool, author_name: str) -> None:
        self.connection.execute(
            "INSERT INTO expenses (id, amount, currency, category, description, is_shared, expense_date, synced, author_name) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?)",
            (str(uuid4()), amount, currency, category, description, int(is_shared), date.today().isoformat(), author_name),
        )
        self.connection.commit()

    def total(self, year: int | None = None, month: int | None = None) -> float:
        query = "SELECT COALESCE(SUM(amount), 0) AS total FROM expenses WHERE 1=1"
        values: list[str | int] = []
        if year is not None:
            query += " AND substr(expense_date, 1, 4) = ?"
            values.append(str(year))
        if month is not None:
            query += " AND substr(expense_date, 6, 2) = ?"
            values.append(f"{month:02d}")
        return float(self.connection.execute(query, values).fetchone()["total"])

    def totals_by_currency(self, year: int | None = None, month: int | None = None) -> dict[str, float]:
        query = "SELECT currency, COALESCE(SUM(amount), 0) AS total FROM expenses WHERE 1=1"
        values: list[str] = []
        if year is not None:
            query += " AND substr(expense_date, 1, 4) = ?"
            values.append(str(year))
        if month is not None:
            query += " AND substr(expense_date, 6, 2) = ?"
            values.append(f"{month:02d}")
        query += " GROUP BY currency"
        return {row["currency"]: float(row["total"]) for row in self.connection.execute(query, values)}

    def category_totals(self, start: str, end: str) -> list[sqlite3.Row]:
        return list(
            self.connection.execute(
                """
                SELECT category, currency,
                    COALESCE(SUM(amount), 0) AS total,
                    COALESCE(SUM(CASE WHEN is_shared = 1 THEN amount ELSE 0 END), 0) AS shared,
                    COALESCE(SUM(CASE WHEN is_shared = 0 THEN amount ELSE 0 END), 0) AS personal
                FROM expenses
                WHERE expense_date BETWEEN ? AND ?
                GROUP BY category, currency
                ORDER BY total DESC
                """,
                (start, end),
            )
        )

    def spending_summary(self, start: str, end: str) -> dict[str, object]:
        reset_date = self.connection.execute("SELECT value FROM app_state WHERE key = 'running_reset_date'").fetchone()
        running_start = reset_date["value"] if reset_date else "0000-01-01"
        totals = self.connection.execute(
            "SELECT COALESCE(SUM(amount), 0) AS total, COALESCE(SUM(CASE WHEN is_shared = 1 THEN amount ELSE 0 END), 0) AS shared, COALESCE(SUM(CASE WHEN is_shared = 0 THEN amount ELSE 0 END), 0) AS personal FROM expenses WHERE expense_date BETWEEN ? AND ?",
            (start, end),
        ).fetchone()
        authors = list(self.connection.execute(
            "SELECT author_name, COALESCE(SUM(amount), 0) AS total, COALESCE(SUM(CASE WHEN is_shared = 1 THEN amount ELSE 0 END), 0) AS shared FROM expenses WHERE expense_date BETWEEN ? AND ? GROUP BY author_name ORDER BY total DESC",
            (start, end),
        ))
        running = list(self.connection.execute(
            "SELECT author_name, COALESCE(SUM(amount), 0) AS shared FROM expenses WHERE is_shared = 1 AND expense_date >= ? GROUP BY author_name ORDER BY shared DESC",
            (running_start,),
        ))
        return {"total": float(totals["total"]), "shared": float(totals["shared"]), "personal": float(totals["personal"]), "authors": authors, "running": running}

    def reset_running_total(self) -> None:
        self.connection.execute(
            "INSERT INTO app_state (key, value) VALUES ('running_reset_date', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            (date.today().isoformat(),),
        )
        self.connection.commit()

    def expenses(self) -> list[sqlite3.Row]:
        return list(self.connection.execute("SELECT * FROM expenses ORDER BY expense_date DESC, rowid DESC"))

    def delete_expense(self, expense_id: str) -> None:
        self.connection.execute("DELETE FROM expenses WHERE id = ?", (expense_id,))
        self.connection.commit()

    def pending_expenses(self) -> list[sqlite3.Row]:
        return list(self.connection.execute("SELECT * FROM expenses WHERE synced = 0"))

    def set_remote_identity(self, household_id: str, profile_id: str) -> None:
        self.connection.execute(
            "UPDATE household SET remote_id = ?, remote_profile_id = ?",
            (household_id, profile_id),
        )
        self.connection.commit()

    def mark_synced(self, expense_id: str) -> None:
        self.connection.execute("UPDATE expenses SET synced = 1 WHERE id = ?", (expense_id,))
        self.connection.commit()
