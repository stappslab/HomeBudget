from collections.abc import Generator
from secrets import token_urlsafe

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

DATABASE_URL = "sqlite:///./homebudget.db"

engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


class Base(DeclarativeBase):
    pass


def run_sqlite_migrations() -> None:
    with engine.begin() as connection:
        household_columns = {row[1] for row in connection.exec_driver_sql("PRAGMA table_info(households)")}
        if "access_code" not in household_columns:
            connection.exec_driver_sql("ALTER TABLE households ADD COLUMN access_code VARCHAR(24)")
            rows = connection.exec_driver_sql("SELECT id FROM households WHERE access_code IS NULL").fetchall()
            for row in rows:
                connection.exec_driver_sql(
                    "UPDATE households SET access_code = ? WHERE id = ?",
                    (token_urlsafe(8), row[0]),
                )
        columns = connection.exec_driver_sql("PRAGMA table_info(categories)").fetchall()
        column_names = {row[1] for row in columns}
        if "proposed_by" not in column_names:
            connection.exec_driver_sql("ALTER TABLE categories ADD COLUMN proposed_by VARCHAR(36)")
        expense_columns = {row[1] for row in connection.exec_driver_sql("PRAGMA table_info(expenses)")}
        if "author_name" not in expense_columns:
            connection.exec_driver_sql("ALTER TABLE expenses ADD COLUMN author_name VARCHAR(80) DEFAULT ''")


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
