from datetime import date, timedelta
from uuid import uuid4

from fastapi.testclient import TestClient

from app.main import app


client = TestClient(app)


def test_household_membership_budget_and_author_rules() -> None:
    household_name = f"Test {uuid4()}"
    created = client.post(
        "/households",
        json={
            "name": household_name,
            "pin": "1234",
            "default_currency": "RSD",
            "creator": {"name": "Creator", "avatar": "sun"},
        },
    )
    assert created.status_code == 201
    household = created.json()

    joined = client.post(
        "/households/join",
        json={"access_code": household["access_code"], "profile": {"name": "Member", "avatar": "moon"}},
    )
    assert joined.status_code == 201
    member = joined.json()
    assert member["approved"] is False

    members = client.get(f"/households/{household['id']}/members").json()
    creator = next(item for item in members if item["profile_name"] == "Creator")
    approved = client.post(
        f"/households/{household['id']}/members/{member['profile_id']}/approve",
        params={"admin_id": creator["profile_id"]},
    )
    assert approved.status_code == 200
    assert approved.json()["approved"] is True

    categories = client.get(f"/households/{household['id']}/categories").json()
    budget = client.post(
        f"/households/{household['id']}/budgets",
        params={"admin_id": creator["profile_id"]},
        json={
            "category_id": categories[0]["id"],
            "amount": "50000",
            "currency": "RSD",
            "period_start": date.today().isoformat(),
            "period_end": (date.today() + timedelta(days=30)).isoformat(),
        },
    )
    assert budget.status_code == 201

    expense = client.post(
        f"/households/{household['id']}/expenses",
        json={
            "author_id": creator["profile_id"],
            "category_id": categories[0]["id"],
            "amount": "1000",
            "currency": "RSD",
            "description": "Test expense",
            "is_shared": True,
            "expense_date": date.today().isoformat(),
        },
    )
    assert expense.status_code == 201
    summary = client.get(
        f"/households/{household['id']}/expenses/summary",
        params={"start": date.today().isoformat(), "end": date.today().isoformat()},
    )
    assert summary.status_code == 200
    assert summary.json()["shared"] == 1000
    assert summary.json()["personal"] == 0
    assert summary.json()["authors"][0]["author_name"] == "Creator"
    update = client.patch(
        f"/households/{household['id']}/expenses/{expense.json()['id']}",
        json={
            "author_id": member["profile_id"],
            "category_id": categories[0]["id"],
            "amount": "900",
            "currency": "RSD",
            "description": "Not allowed",
            "is_shared": False,
            "expense_date": date.today().isoformat(),
        },
    )
    assert update.status_code == 403

    proposed_category = client.post(
        f"/households/{household['id']}/categories",
        params={"profile_id": member["profile_id"]},
        json={"name": "Predlog", "description": "Članov predlog"},
    )
    assert proposed_category.status_code == 201
    assert proposed_category.json()["approved"] is False
    approved_category = client.post(
        f"/households/{household['id']}/categories/{proposed_category.json()['id']}/approve",
        params={"admin_id": creator["profile_id"]},
    )
    assert approved_category.status_code == 200
    assert approved_category.json()["approved"] is True


def test_creator_can_view_and_regenerate_access_code() -> None:
    created = client.post(
        "/households",
        json={
            "name": f"Access {uuid4()}",
            "pin": "1234",
            "default_currency": "RSD",
            "creator": {"name": "Creator", "avatar": "sun"},
        },
    )
    assert created.status_code == 201
    household = created.json()
    first_code = household["access_code"]

    current = client.get(
        f"/households/{household['id']}/access-code",
        params={"admin_id": household["creator_id"]},
    )
    assert current.status_code == 200
    assert current.json()["access_code"] == first_code

    regenerated = client.post(
        f"/households/{household['id']}/access-code",
        params={"admin_id": household["creator_id"]},
    )
    assert regenerated.status_code == 200
    assert regenerated.json()["access_code"] != first_code

    forbidden = client.get(
        f"/households/{household['id']}/access-code",
        params={"admin_id": str(uuid4())},
    )
    assert forbidden.status_code == 403
