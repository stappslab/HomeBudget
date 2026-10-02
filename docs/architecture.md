# HomeBudget architecture

The MVP is split into a FastAPI backend and a Kivy mobile client. The first backend persistence layer is SQLite so development stays local. Supabase/PostgreSQL and offline synchronization are planned behind the same API boundary.

Core rules:

- A profile belongs to one household context.
- Every expense has one author and is immutable by other members.
- `is_shared` describes household purpose; it does not split the amount.
- Household totals include both individual and shared expenses.
- Archived categories remain valid for historical expenses.
