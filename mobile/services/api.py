import json
from typing import Any
from urllib.error import HTTPError
from urllib.request import Request, urlopen


class ApiClient:
    def __init__(self, base_url: str = "http://127.0.0.1:8000"):
        self.base_url = base_url.rstrip("/")

    def _request(self, method: str, path: str, payload: dict[str, Any] | None = None) -> Any:
        body = json.dumps(payload).encode("utf-8") if payload is not None else None
        request = Request(
            f"{self.base_url}{path}",
            data=body,
            method=method,
            headers={"Content-Type": "application/json"} if body else {},
        )
        try:
            with urlopen(request, timeout=5) as response:
                data = response.read()
                return json.loads(data.decode("utf-8")) if data else None
        except HTTPError as error:
            raise RuntimeError(f"API request failed ({error.code})") from error

    def health(self) -> dict[str, Any]:
        return self._request("GET", "/health")

    def create_household(self, name: str, pin: str, profile_name: str, currency: str = "RSD") -> dict[str, Any]:
        return self._request("POST", "/households", {
                "name": name,
                "pin": pin,
                "default_currency": currency,
                "creator": {"name": profile_name, "avatar": "sun"},
            })

    def join_household(self, access_code: str, profile_name: str) -> dict[str, Any]:
        return self._request("POST", "/households/join", {
            "access_code": access_code,
            "profile": {"name": profile_name, "avatar": "sun"},
        })

    def categories(self, household_id: str) -> list[dict[str, Any]]:
        return self._request("GET", f"/households/{household_id}/categories")

    def expenses(self, household_id: str) -> list[dict[str, Any]]:
        return self._request("GET", f"/households/{household_id}/expenses")

    def expense_summary(self, household_id: str, start: str, end: str) -> dict[str, Any]:
        return self._request(
            "GET",
            f"/households/{household_id}/expenses/summary?start={start}&end={end}",
        )

    def create_expense(self, household_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        return self._request("POST", f"/households/{household_id}/expenses", payload)

    def members(self, household_id: str) -> list[dict[str, Any]]:
        return self._request("GET", f"/households/{household_id}/members")

    def access_code(self, household_id: str, admin_id: str) -> dict[str, Any]:
        return self._request("GET", f"/households/{household_id}/access-code?admin_id={admin_id}")

    def regenerate_access_code(self, household_id: str, admin_id: str) -> dict[str, Any]:
        return self._request("POST", f"/households/{household_id}/access-code?admin_id={admin_id}")

    def approve_member(self, household_id: str, profile_id: str, admin_id: str) -> dict[str, Any]:
        return self._request(
            "POST",
            f"/households/{household_id}/members/{profile_id}/approve?admin_id={admin_id}",
        )

    def update_member(
        self, household_id: str, profile_id: str, admin_id: str, role_name: str, is_admin: bool
    ) -> dict[str, Any]:
        return self._request(
            "PATCH",
            f"/households/{household_id}/members/{profile_id}?admin_id={admin_id}",
            {"role_name": role_name, "is_admin": is_admin},
        )
