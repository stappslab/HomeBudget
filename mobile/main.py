import calendar
from datetime import date, datetime, timedelta

from kivy.app import App
from kivy.core.window import Window
from kivy.core.clipboard import Clipboard
from kivy.graphics import Color, Line, RoundedRectangle
from kivy.metrics import dp
from kivy.clock import Clock
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.anchorlayout import AnchorLayout
from kivy.uix.button import Button
from kivy.uix.checkbox import CheckBox
from kivy.uix.gridlayout import GridLayout
from kivy.uix.label import Label
from kivy.uix.screenmanager import Screen, ScreenManager
from kivy.uix.scrollview import ScrollView
from kivy.uix.spinner import Spinner
from kivy.uix.textinput import TextInput
from kivy.uix.widget import Widget

from local_db.local_db import LocalDatabase
from components.charts import CategoryBarChart
from services.sync import SyncService
from services.i18n import text


database = LocalDatabase()
sync_service = SyncService(database)

APP_BG = (0.08, 0.09, 0.10, 1)
PANEL_BG = (0.11, 0.15, 0.16, 1)
PANEL_ALT = (0.16, 0.20, 0.22, 1)
FIELD_BG = (0.19, 0.24, 0.25, 1)
TEXT = (0.96, 0.97, 0.94, 1)
TEXT_SOFT = (0.71, 0.76, 0.78, 1)
ACCENT_GREEN = (0.67, 0.82, 0.72, 1)
ACCENT_BLUE = (0.55, 0.70, 0.77, 1)
ACCENT_MUTED = (0.18, 0.23, 0.24, 1)
LANGUAGE_OPTIONS = ("Srpski latinica", "Srpski ćirilica", "English")


def language_code(label: str) -> str:
    return {"Srpski ćirilica": "sr_cy", "Srpski latinica": "sr_lat", "English": "en"}.get(label, "sr_lat")


def language_label(code: str) -> str:
    return {"sr_cy": "Srpski ćirilica", "sr_lat": "Srpski latinica", "sr": "Srpski latinica", "en": "English"}.get(code, "Srpski latinica")


def language() -> str:
    household = database.household()
    return household["language"] if household else "sr"


def apply_theme() -> None:
    household = database.household()
    Window.clearcolor = APP_BG if not household or household["theme"] == "dark" else (0.91, 0.91, 0.88, 1)


def field(hint: str) -> TextInput:
    widget = TextInput(
        hint_text=hint,
        multiline=False,
        size_hint_y=None,
        height=dp(48),
        foreground_color=TEXT,
        background_color=FIELD_BG,
        hint_text_color=TEXT_SOFT,
        cursor_color=(0.86, 0.92, 0.82, 1),
        padding=(dp(12), dp(12), dp(12), dp(12)),
    )
    widget.font_size = dp(16)
    widget.bind(focus=_scroll_to_focused_field)
    return widget


def _scroll_to_focused_field(widget: TextInput, focused: bool) -> None:
    if not focused:
        return
    scroll_view = None
    parent = widget.parent
    while parent is not None:
        if isinstance(parent, ScrollView):
            scroll_view = parent
            break
        parent = parent.parent
    if scroll_view is None:
        return

    def scroll(*_args):
        scroll_view.scroll_to(widget, padding=dp(48), animate=False)

    for delay in (0.15, 0.4, 0.75):
        Clock.schedule_once(scroll, delay)


def format_amount_input(widget: TextInput, *_args) -> None:
    if getattr(widget, "_formatting_amount", False):
        return
    raw = widget.text.replace(".", "").replace(",", ".")
    if not raw or raw == ".":
        return
    try:
        value = float(raw)
    except ValueError:
        return
    integer, separator, decimals = f"{value:.2f}".partition(".")
    integer = f"{int(integer):,}".replace(",", ".")
    formatted = integer if not decimals.strip("0") else f"{integer},{decimals.rstrip('0')}"
    if widget.text != formatted:
        widget._formatting_amount = True
        try:
            widget.text = formatted
            widget.cursor = len(formatted)
        finally:
            widget._formatting_amount = False


def format_amount_on_blur(widget: TextInput, focused: bool) -> None:
    if focused or not widget.text.strip():
        return
    raw = widget.text.replace(".", "").replace(",", ".")
    try:
        value = float(raw)
    except ValueError:
        return
    integer, _, decimals = f"{value:.2f}".partition(".")
    integer = f"{int(integer):,}".replace(",", ".")
    widget.text = integer if not decimals.strip("0") else f"{integer},{decimals.rstrip('0')}"


def format_date_input(widget: TextInput, *_args) -> None:
    if getattr(widget, "_formatting_date", False):
        return
    digits = "".join(character for character in widget.text if character.isdigit())[:8]
    parts = [digits[:2], digits[2:4], digits[4:]]
    formatted = "/".join(part for part in parts if part)
    if widget.text != formatted:
        widget._formatting_date = True
        try:
            widget.text = formatted
            widget.cursor = len(formatted)
        finally:
            widget._formatting_date = False


def parse_amount(value: str) -> float:
    normalized = value.strip().replace(" ", "")
    if "," in normalized:
        normalized = normalized.replace(".", "").replace(",", ".")
    elif normalized.count(".") == 1 and len(normalized.rsplit(".", 1)[1]) == 3:
        normalized = normalized.replace(".", "")
    else:
        normalized = normalized.replace(".", "") if normalized.count(".") > 1 else normalized
    return float(normalized)


def action_button(label: str, *, accent: tuple[float, float, float, float] = (0.67, 0.82, 0.72, 1), text_color=(0.08, 0.12, 0.12, 1), font_size=dp(15)) -> Button:
    button = Button(
        text=label,
        size_hint_y=None,
        height=dp(52),
        background_color=(0, 0, 0, 0),
        color=text_color,
        bold=True,
        font_size=font_size,
    )

    def _draw_button(*_args):
        button.canvas.before.clear()
        with button.canvas.before:
            Color(*accent)
            RoundedRectangle(pos=button.pos, size=button.size, radius=[dp(14)])

    button.bind(pos=_draw_button, size=_draw_button)
    button.canvas.before.clear()
    _draw_button()
    return button


def select_button(label: str, *, accent: tuple[float, float, float, float] = (0.18, 0.23, 0.24, 1), text_color=(0.95, 0.95, 0.90, 1), font_size=dp(15)) -> Button:
    button = Button(
        text=label,
        size_hint_y=None,
        height=dp(52),
        background_color=(0, 0, 0, 0),
        color=text_color,
        bold=True,
        font_size=font_size,
    )

    def _draw_button(*_args):
        button.canvas.before.clear()
        with button.canvas.before:
            Color(*accent)
            RoundedRectangle(pos=button.pos, size=button.size, radius=[dp(14)])

    button.bind(pos=_draw_button, size=_draw_button)
    button.canvas.before.clear()
    _draw_button()
    return button


def spinner_field(label: str, values: tuple[str, ...] | list[str], *, height: int = dp(48)) -> Spinner:
    widget = Spinner(
        text=label,
        values=values,
        size_hint_y=None,
        height=height,
        bold=True,
        color=(0.96, 0.97, 0.94, 1),
        background_color=(0.20, 0.25, 0.26, 1),
        background_normal="",
        background_down="",
    )
    widget.font_size = dp(15)
    return widget


class HomeMark(Widget):
    def __init__(self, **kwargs):
        super().__init__(size_hint=(None, None), width=dp(144), height=dp(112), **kwargs)
        self.bind(pos=self._draw, size=self._draw)

    def _draw(self, *_args):
        self.canvas.clear()
        mark_width = min(self.width * 0.82, dp(120))
        mark_height = min(self.height * 0.82, dp(88))
        left = self.center_x - mark_width / 2
        bottom = self.y + (self.height - mark_height) / 2
        body_height = mark_height * 0.62
        roof_peak = bottom + mark_height * 0.94
        with self.canvas:
            Color(*ACCENT_GREEN)
            Line(
            points=[left + mark_width * 0.08, bottom + body_height,
                        self.center_x, roof_peak,
                left + mark_width * 0.92, bottom + body_height],
                width=max(dp(2), mark_width * 0.055),
                joint="round",
            )
            RoundedRectangle(
                pos=(left + mark_width * 0.09, bottom),
                size=(mark_width * 0.82, body_height),
                radius=[mark_width * 0.08],
            )
            Color(*PANEL_BG)
            RoundedRectangle(
                pos=(self.center_x - mark_width * 0.10, bottom),
                size=(mark_width * 0.20, body_height * 0.55),
                radius=[mark_width * 0.035],
            )


class LegendSwatch(BoxLayout):
    def __init__(self, color, **kwargs):
        super().__init__(size_hint=(None, None), size=(dp(12), dp(12)), **kwargs)
        self.swatch_color = color
        self.bind(pos=self._draw, size=self._draw)

    def _draw(self, *_args):
        self.canvas.before.clear()
        with self.canvas.before:
            Color(*self.swatch_color)
            RoundedRectangle(pos=self.pos, size=self.size, radius=[dp(3)])


class Welcome(Screen):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        Window.softinput_mode = "below_target"
        self.root = ScrollView(do_scroll_x=False, do_scroll_y=True)
        content = DashboardCard(orientation="vertical", padding=dp(24), spacing=dp(12), bg_color=PANEL_BG, size_hint=(1, None))
        content.bind(minimum_height=lambda instance, value: setattr(instance, "height", max(value, self.root.height)))
        self.root.bind(height=lambda instance, value: setattr(content, "height", max(content.minimum_height, value)))
        logo_row = AnchorLayout(size_hint_y=None, height=dp(124), anchor_x="center", anchor_y="center")
        logo_row.add_widget(HomeMark())
        content.add_widget(logo_row)
        content.add_widget(Label(text="HomeBudget", font_size=dp(30), color=TEXT, bold=True, size_hint_y=None, height=dp(42)))
        content.add_widget(Label(text="Porodični pregled potrošnje", color=TEXT_SOFT, size_hint_y=None, height=dp(28)))
        self.message = Label(text="", color=(0.96, 0.70, 0.58, 1), font_size=dp(14), size_hint_y=None, height=dp(34))
        content.add_widget(self.message)
        self.menu = BoxLayout(orientation="vertical", spacing=dp(10), size_hint_y=None)
        self.menu.bind(minimum_height=self.menu.setter("height"))
        self.flex_spacer = Widget(size_hint_y=1)
        content.add_widget(self.flex_spacer)
        content.add_widget(self.menu)
        self.root.add_widget(content)
        self.add_widget(self.root)
        self.show_menu()

    def show_menu(self, *_):
        self.flex_spacer.size_hint_y = 1
        self.flex_spacer.height = 0
        self.menu.clear_widgets()
        join = action_button("Pridruži se domaćinstvu", accent=ACCENT_BLUE, text_color=(0.08, 0.12, 0.12, 1))
        join.bind(on_release=lambda *_: self.show_join())
        create = action_button("Kreiraj domaćinstvo", accent=ACCENT_GREEN, text_color=(0.08, 0.12, 0.12, 1))
        create.bind(on_release=lambda *_: self.show_create())
        self.menu.add_widget(join)
        self.menu.add_widget(create)
        household = database.household()
        if household is not None:
            continue_button = select_button(
                f"Nastavi sa: {household['name']}",
                accent=ACCENT_MUTED,
            )
            continue_button.bind(on_release=lambda *_: self.show_continue())
            self.menu.add_widget(continue_button)

    def show_create(self):
        self._prepare_form_layout()
        self.menu.clear_widgets()
        self.household_name = field("Naziv domaćinstva")
        self.profile_name = field("Tvoje ime")
        self.pin = field("PIN domaćinstva (najmanje 4 znaka)")
        self.currency = spinner_field("RSD", ("RSD", "EUR", "USD"))
        for widget in (self.household_name, self.profile_name, self.pin, self.currency):
            self.menu.add_widget(widget)
        create = action_button("Kreiraj domaćinstvo", accent=ACCENT_GREEN, text_color=(0.08, 0.12, 0.12, 1))
        create.bind(on_release=self.create_household)
        back = select_button("Nazad", accent=ACCENT_MUTED)
        back.bind(on_release=self.show_menu)
        self.menu.add_widget(create)
        self.menu.add_widget(back)

    def show_continue(self):
        self._prepare_form_layout()
        self.menu.clear_widgets()
        household = database.household()
        self.household_selector = spinner_field(
            household["name"] if household else "Domaćinstvo",
            (household["name"],) if household else (),
        )
        self.menu.add_widget(Label(text="Izaberi domaćinstvo", color=TEXT_SOFT, size_hint_y=None, height=dp(26)))
        self.menu.add_widget(self.household_selector)
        self.pin = field("PIN domaćinstva")
        self.menu.add_widget(self.pin)
        enter = action_button("Nastavi", accent=ACCENT_GREEN, text_color=(0.08, 0.12, 0.12, 1))
        enter.bind(on_release=self.continue_household)
        back = select_button("Nazad", accent=ACCENT_MUTED)
        back.bind(on_release=self.show_menu)
        self.menu.add_widget(enter)
        self.menu.add_widget(back)

    def show_join(self):
        self._prepare_form_layout()
        self.menu.clear_widgets()
        self.profile_name = field("Tvoje ime")
        self.access_code = field("Access code domaćinstva")
        self.menu.add_widget(self.profile_name)
        self.menu.add_widget(self.access_code)
        join = action_button("Pridruži se", accent=ACCENT_BLUE, text_color=(0.08, 0.12, 0.12, 1))
        join.bind(on_release=self.join_household)
        back = select_button("Nazad", accent=ACCENT_MUTED)
        back.bind(on_release=self.show_menu)
        self.menu.add_widget(join)
        self.menu.add_widget(back)

    def _prepare_form_layout(self):
        self.flex_spacer.size_hint_y = None
        self.flex_spacer.height = 0
        self.root.scroll_y = 1

    def join_household(self, *_):
        profile_name = self.profile_name.text.strip()
        access_code = self.access_code.text.strip()
        if not profile_name or not access_code:
            self.message.text = "Unesi ime i access code domaćinstva."
            return
        try:
            joined = sync_service.api.join_household(access_code, profile_name)
            database.create_joined_household(
                joined["household_name"],
                profile_name,
                joined["default_currency"],
                access_code,
                joined["household_id"],
                joined["profile_id"],
            )
        except Exception:
            self.message.text = "Pridruživanje nije uspelo. Proveri access code i internet."
            return
        self.manager.get_screen("dashboard").refresh()
        self.manager.current = "dashboard"

    def create_household(self, *_):
        if not self.household_name.text.strip() or not self.profile_name.text.strip() or len(self.pin.text) < 4:
            self.message.text = "Unesi naziv, ime i PIN od najmanje 4 znaka."
            return
        database.create_household(self.household_name.text.strip(), self.profile_name.text.strip(), self.currency.text, self.pin.text)
        self.manager.get_screen("dashboard").refresh()
        self.manager.current = "dashboard"

    def continue_household(self, *_):
        if not self.pin.text.strip():
            self.message.text = "Unesi PIN domaćinstva."
            return
        if not database.valid_pin(self.pin.text.strip()):
            self.message.text = "PIN nije ispravan."
            return
        self.manager.get_screen("dashboard").refresh()
        self.manager.current = "dashboard"


class DashboardCard(BoxLayout):
    def __init__(self, bg_color=(0.18, 0.21, 0.22, 1), **kwargs):
        super().__init__(**kwargs)
        self.bg_color = bg_color
        self.bind(pos=self._draw_background, size=self._draw_background)

    def _draw_background(self, *args):
        self.canvas.before.clear()
        with self.canvas.before:
            Color(*self.bg_color)
            RoundedRectangle(pos=self.pos, size=self.size, radius=[dp(20)])


class Dashboard(Screen):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        root = ScrollView(do_scroll_x=False, do_scroll_y=True)
        content = BoxLayout(orientation="vertical", padding=dp(18), spacing=dp(14), size_hint_y=None)
        content.bind(minimum_height=content.setter("height"))

        self.main_card = DashboardCard(
            orientation="vertical",
            padding=dp(18),
            spacing=dp(6),
            size_hint_y=None,
            height=dp(330),
            bg_color=PANEL_BG,
        )

        self.title = Label(
            text=text(language(), "app_name"),
            font_size=dp(34),
            bold=True,
            color=(0.98, 0.97, 0.93, 1),
            halign="left",
            size_hint_y=None,
            height=dp(40),
        )
        self.subtitle = Label(
            text="Porodični pregled · Septembar 2026",
            color=(0.71, 0.76, 0.78, 1),
            font_size=dp(14),
            halign="left",
            size_hint_y=None,
            height=dp(22),
        )
        self.month_label = Label(
            text="Ukupno ovog meseca",
            color=(0.76, 0.80, 0.82, 1),
            font_size=dp(15),
            halign="left",
            size_hint_y=None,
            height=dp(20),
        )
        self.month_total = Label(
            font_size=dp(42),
            bold=True,
            color=(0.96, 0.97, 0.93, 1),
            halign="left",
            size_hint_y=None,
            height=dp(46),
        )
        self.year_total = Label(
            text="Od početka godine · 0 RSD",
            color=(0.84, 0.88, 0.85, 1),
            font_size=dp(14),
            halign="left",
            size_hint_y=None,
            height=dp(20),
        )

        category_bar = BoxLayout(size_hint_y=None, height=dp(52), spacing=dp(8))
        for color in [(0.70, 0.83, 0.75, 1), (0.86, 0.67, 0.59, 1), (0.71, 0.80, 0.88, 1)]:
            chip = BoxLayout(size_hint_x=1)
            chip.canvas.before.clear()
            with chip.canvas.before:
                Color(*color)
                RoundedRectangle(pos=chip.pos, size=chip.size, radius=[dp(12)])
            chip.bind(pos=lambda instance, value: instance.canvas.before.clear(), size=lambda instance, value: instance.canvas.before.clear())
            category_bar.add_widget(chip)

        self.main_card.add_widget(self.title)
        self.main_card.add_widget(self.subtitle)
        self.main_card.add_widget(self.month_label)
        self.main_card.add_widget(self.month_total)
        self.main_card.add_widget(self.year_total)
        self.main_card.add_widget(Label(size_hint_y=None, height=dp(8)))
        self.main_card.add_widget(category_bar)

        self.activity = DashboardCard(
            orientation="vertical",
            padding=dp(12),
            spacing=dp(6),
            size_hint_y=None,
            height=dp(122),
            bg_color=PANEL_ALT,
        )
        add_button = action_button(
            text(language(), "new_expense"),
            accent=(0.67, 0.82, 0.72, 1),
            text_color=(0.08, 0.12, 0.12, 1),
            font_size=dp(15),
        )
        add_button.bind(on_release=lambda *_: setattr(self.manager, "current", "add"))
        stats_button = select_button(
            "Statistika",
            accent=(0.19, 0.24, 0.24, 1),
            text_color=(0.95, 0.95, 0.90, 1),
            font_size=dp(15),
        )
        stats_button.bind(on_release=lambda *_: setattr(self.manager, "current", "stats"))
        actions = BoxLayout(size_hint_y=None, height=dp(52), spacing=dp(10))
        actions.add_widget(add_button)
        actions.add_widget(stats_button)

        navigation = GridLayout(cols=3, spacing=dp(6), size_hint_y=None, height=dp(88))
        for label, screen_name in (
            ("Troškovi", "expenses"),
            ("Kategorije", "manage"),
            ("Članovi", "members"),
            ("Podešavanja", "settings"),
            ("Početni ekran", "welcome"),
        ):
            button = select_button(label, accent=ACCENT_MUTED, font_size=dp(11))
            button.bind(on_release=lambda _, target=screen_name: setattr(self.manager, "current", target))
            navigation.add_widget(button)

        content.add_widget(self.main_card)
        content.add_widget(self.activity)
        content.add_widget(actions)
        content.add_widget(navigation)
        root.add_widget(content)
        self.add_widget(root)

    def on_pre_enter(self, *args):
        self.refresh()

    def refresh(self):
        household = database.household()
        if household is None:
            return
        self.manager.get_screen("settings").refresh_labels()
        self.title.text = text(language(), "app_name")
        self.month_label.text = text(language(), "this_month")
        self._refresh_activity()
        today = __import__("datetime").date.today()
        month_totals = database.totals_by_currency(today.year, today.month)
        year_totals = database.totals_by_currency(today.year)
        month_total = self._sum_totals(month_totals)
        year_total = self._sum_totals(year_totals)
        self.month_total.text = f"{self._format_value(month_total, household['default_currency'])}"
        self.year_total.text = f"{text(language(), 'year_to_date')} · {self._format_value(year_total, household['default_currency'])}"

    def _refresh_activity(self):
        self.activity.clear_widgets()
        header = BoxLayout(size_hint_y=None, height=dp(22), spacing=dp(10))
        header.add_widget(Label(text=text(language(), "household_activity"), color=TEXT, font_size=dp(14), halign="left"))
        header.add_widget(Label(text=text(language(), "today"), color=TEXT_SOFT, font_size=dp(12), halign="right"))
        self.activity.add_widget(header)
        today = date.today()
        rows = [row for row in database.expenses() if row["expense_date"].startswith(today.strftime("%Y-%m"))]
        if not rows:
            self.activity.add_widget(Label(text=text(language(), "no_month_expenses"), color=TEXT_SOFT, font_size=dp(13)))
            return
        for expense in rows[:2]:
            row = BoxLayout(size_hint_y=None, height=dp(34), spacing=dp(10))
            row.add_widget(Label(text="•", color=ACCENT_GREEN, font_size=dp(18), halign="center"))
            row.add_widget(Label(text=f"{database.household()['profile_name']} · {expense['category']}", color=TEXT, font_size=dp(13), halign="left"))
            row.add_widget(Label(text=self._format_value(float(expense["amount"]), expense["currency"]), color=TEXT, font_size=dp(13), halign="right"))
            self.activity.add_widget(row)

    @staticmethod
    def _sum_totals(totals: dict[str, float]) -> float:
        return sum(totals.values())

    @staticmethod
    def _format_value(value: float, currency: str) -> str:
        formatted = f"{value:,.0f}".replace(",", ".")
        return f"{formatted} {currency}"

    def sync(self, *_):
        result = sync_service.sync()
        self.status.text = f"{result.message}. Poslato: {result.uploaded}, čeka: {result.pending}"


class Manage(Screen):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        root = DashboardCard(orientation="vertical", padding=dp(20), spacing=dp(10), bg_color=(0.11, 0.15, 0.16, 1))
        root.add_widget(Label(text="Kategorije i budžet", font_size=dp(23), size_hint_y=None, height=dp(40), color=TEXT, bold=True))
        scroll = ScrollView(do_scroll_x=False, do_scroll_y=True)
        content = BoxLayout(orientation="vertical", spacing=dp(10), size_hint_y=None)
        content.bind(minimum_height=content.setter("height"))
        self.budget_input = field("Mesečni ukupni budžet")
        content.add_widget(self.budget_input)
        save_budget = action_button("Sačuvaj budžet", accent=(0.55, 0.70, 0.77, 1), text_color=(0.09, 0.12, 0.12, 1), font_size=dp(15))
        save_budget.bind(on_release=self.save_budget)
        content.add_widget(save_budget)
        self.category_input = field("Nova kategorija")
        content.add_widget(self.category_input)
        add_category = action_button("Dodaj kategoriju", accent=(0.48, 0.61, 0.68, 1), text_color=(0.09, 0.12, 0.12, 1), font_size=dp(15))
        add_category.bind(on_release=self.add_category)
        content.add_widget(add_category)
        self.edit_category = spinner_field("Kategorija za uređivanje", tuple(database.categories()))
        self.rename_input = field("Novi naziv kategorije")
        content.add_widget(self.edit_category)
        content.add_widget(self.rename_input)
        rename_category = action_button("Preimenuj kategoriju", accent=ACCENT_BLUE, text_color=(0.09, 0.12, 0.12, 1), font_size=dp(15))
        rename_category.bind(on_release=self.rename_category)
        content.add_widget(rename_category)
        archive_category = select_button("Arhiviraj kategoriju", accent=ACCENT_MUTED, font_size=dp(15))
        archive_category.bind(on_release=self.archive_category)
        content.add_widget(archive_category)
        content.add_widget(Label(text="Budžet po kategoriji", size_hint_y=None, height=dp(30), color=TEXT, font_size=dp(17), bold=True))
        self.budget_category = spinner_field("Kategorija", tuple(database.categories()))
        self.budget_category_amount = field("Iznos kategorijskog budžeta")
        content.add_widget(self.budget_category)
        content.add_widget(self.budget_category_amount)
        save_category_budget = action_button("Sačuvaj kategorijski budžet", accent=(0.47, 0.62, 0.71, 1), text_color=(0.09, 0.12, 0.12, 1), font_size=dp(15))
        save_category_budget.bind(on_release=self.save_category_budget)
        content.add_widget(save_category_budget)
        content.add_widget(Label(text="Aktivne kategorije", size_hint_y=None, height=dp(28), color=TEXT, font_size=dp(15), bold=True))
        self.category_rows = GridLayout(cols=1, spacing=dp(4), size_hint_y=None)
        self.category_rows.bind(minimum_height=self.category_rows.setter("height"))
        content.add_widget(self.category_rows)
        scroll.add_widget(content)
        root.add_widget(scroll)
        self.message = Label(text="", color=TEXT_SOFT, font_size=dp(12), size_hint_y=None, height=dp(28))
        root.add_widget(self.message)
        back = select_button("Nazad", accent=(0.21, 0.26, 0.26, 1), text_color=(0.95, 0.95, 0.90, 1), font_size=dp(15))
        back.bind(on_release=lambda *_: setattr(self.manager, "current", "dashboard"))
        root.add_widget(back)
        self.add_widget(root)

    def on_pre_enter(self, *args):
        self.refresh()

    def refresh(self):
        budget = database.monthly_budget()
        self.budget_input.text = str(budget) if budget else ""
        categories = database.categories()
        self.budget_category.values = categories
        self.edit_category.values = categories
        self.category_rows.clear_widgets()
        for category in categories:
            row = BoxLayout(size_hint_y=None, height=dp(34), padding=(dp(10), 0))
            row.add_widget(Label(text=category, color=TEXT_SOFT, font_size=dp(14), halign="left"))
            self.category_rows.add_widget(row)
        category_budgets = database.category_budgets()
        self.budget_category_amount.text = str(category_budgets.get(self.budget_category.text, ""))

    def save_budget(self, *_):
        try:
            amount = parse_amount(self.budget_input.text)
        except ValueError:
            self.message.text = "Unesi ispravan iznos budžeta."
            return
        if amount <= 0:
            self.message.text = "Budžet mora biti veći od nule."
            return
        currency = database.household()["default_currency"]
        database.set_monthly_budget(amount, currency)
        self.message.text = "Budžet je sačuvan."

    def add_category(self, *_):
        name = self.category_input.text.strip()
        if not name:
            self.message.text = "Unesi naziv kategorije."
            return
        database.add_category(name)
        self.category_input.text = ""
        self.refresh()
        self.message.text = "Kategorija je dodata."

    def rename_category(self, *_):
        current = self.edit_category.text
        new_name = self.rename_input.text.strip()
        if current == "Kategorija za uređivanje" or not new_name:
            self.message.text = "Izaberi kategoriju i unesi novi naziv."
            return
        database.rename_category(current, new_name)
        self.rename_input.text = ""
        self.refresh()
        self.message.text = "Kategorija je preimenovana."

    def archive_category(self, *_):
        current = self.edit_category.text
        if current == "Kategorija za uređivanje":
            self.message.text = "Izaberi kategoriju za arhiviranje."
            return
        database.archive_category(current)
        self.refresh()
        self.message.text = "Kategorija je arhivirana, a istorijski troškovi su sačuvani."

    def save_category_budget(self, *_):
        try:
            amount = parse_amount(self.budget_category_amount.text)
        except ValueError:
            self.message.text = "Unesi ispravan iznos kategorijskog budžeta."
            return
        if self.budget_category.text == "Kategorija" or amount <= 0:
            self.message.text = "Izaberi kategoriju i unesi iznos."
            return
        household = database.household()
        if not database.set_category_budget(self.budget_category.text, amount, household["default_currency"]):
            self.message.text = "Zbir kategorijskih budžeta ne može preći ukupni budžet."
            return
        self.message.text = "Kategorijski budžet je sačuvan."


class Members(Screen):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        root = DashboardCard(orientation="vertical", padding=dp(20), spacing=dp(12), bg_color=(0.11, 0.15, 0.16, 1))
        root.add_widget(Label(text="Članovi household-a", font_size=dp(25), size_hint_y=None, height=dp(44), color=(0.96, 0.97, 0.94, 1), bold=True))
        self.items = GridLayout(cols=1, spacing=dp(8), size_hint_y=None)
        self.items.bind(minimum_height=self.items.setter("height"))
        scroll = ScrollView()
        scroll.add_widget(self.items)
        root.add_widget(scroll)
        self.message = Label(text="")
        root.add_widget(self.message)
        self.access_code_label = Label(text="", color=TEXT_SOFT, font_size=dp(14), size_hint_y=None, height=dp(30))
        root.add_widget(self.access_code_label)
        access_actions = BoxLayout(size_hint_y=None, height=dp(46), spacing=dp(8))
        copy_code = select_button("Kopiraj access code", accent=ACCENT_MUTED, font_size=dp(13))
        copy_code.bind(on_release=self.copy_access_code)
        regenerate = select_button("Novi access code", accent=(0.26, 0.20, 0.22, 1), font_size=dp(13))
        regenerate.bind(on_release=self.regenerate_access_code)
        access_actions.add_widget(copy_code)
        access_actions.add_widget(regenerate)
        root.add_widget(access_actions)
        refresh = action_button("Osveži članove", accent=(0.57, 0.72, 0.79, 1), text_color=(0.09, 0.12, 0.12, 1), font_size=dp(15))
        refresh.bind(on_release=lambda *_: self.refresh())
        root.add_widget(refresh)
        back = select_button("Nazad", accent=(0.21, 0.26, 0.26, 1), text_color=(0.95, 0.95, 0.90, 1), font_size=dp(15))
        back.bind(on_release=lambda *_: setattr(self.manager, "current", "dashboard"))
        root.add_widget(back)
        self.add_widget(root)

    def on_pre_enter(self, *args):
        self.refresh()

    def refresh(self):
        self.items.clear_widgets()
        household = database.household()
        if household is None:
            return
        self.items.add_widget(
            Label(text=f"Lokalni profil: {household['profile_name']}", size_hint_y=None, height=dp(42))
        )
        if not household["remote_id"]:
            self.message.text = "Poveži aplikaciju sinhronizacijom da bi upravljao članovima."
            return
        try:
            access = sync_service.api.access_code(household["remote_id"], household["remote_profile_id"])
            self.access_code_label.text = f"Access code: {access['access_code']}"
            members = sync_service.api.members(household["remote_id"])
        except Exception:
            self.message.text = "Članovi trenutno nisu dostupni bez interneta."
            return
        for member in members:
            row = BoxLayout(size_hint_y=None, height=dp(92), spacing=dp(6))
            status = "odobren" if member["approved"] else "čeka odobrenje"
            details = BoxLayout(orientation="vertical")
            details.add_widget(Label(text=f"{member['profile_name']} ({status})"))
            role_input = TextInput(
                text=member["role_name"],
                multiline=False,
                size_hint_y=None,
                height=dp(36),
            )
            details.add_widget(role_input)
            row.add_widget(details)
            admin_box = CheckBox(active=member["is_admin"], size_hint=(None, None), size=(dp(36), dp(36)))
            row.add_widget(admin_box)
            save = Button(text="Sačuvaj", size_hint_x=None, width=dp(88))
            save.bind(
                on_release=lambda _, profile_id=member["profile_id"], role=role_input, admin=admin_box: self.update(
                    profile_id, role.text, admin.active
                )
            )
            row.add_widget(save)
            if not member["approved"]:
                approve = Button(text="Odobri", size_hint_x=None, width=dp(86))
                approve.bind(
                    on_release=lambda _, profile_id=member["profile_id"]: self.approve(profile_id)
                )
                row.add_widget(approve)
            self.items.add_widget(row)

    def copy_access_code(self, *_):
        household = database.household()
        if household is None or not household["remote_id"]:
            self.message.text = "Prvo poveži domaćinstvo sa serverom."
            return
        try:
            access = sync_service.api.access_code(household["remote_id"], household["remote_profile_id"])
            Clipboard.copy(access["access_code"])
            self.message.text = "Access code je kopiran."
        except Exception:
            self.message.text = "Access code trenutno nije dostupan."

    def regenerate_access_code(self, *_):
        household = database.household()
        if household is None or not household["remote_id"]:
            self.message.text = "Prvo poveži domaćinstvo sa serverom."
            return
        try:
            access = sync_service.api.regenerate_access_code(
                household["remote_id"], household["remote_profile_id"]
            )
            self.access_code_label.text = f"Access code: {access['access_code']}"
            Clipboard.copy(access["access_code"])
            self.message.text = "Novi access code je generisan i kopiran."
        except Exception:
            self.message.text = "Generisanje access code-a nije uspelo."

    def update(self, profile_id: str, role_name: str, is_admin: bool):
        household = database.household()
        if not role_name.strip():
            self.message.text = "Naziv uloge ne može biti prazan."
            return
        try:
            sync_service.api.update_member(
                household["remote_id"],
                profile_id,
                household["remote_profile_id"],
                role_name.strip(),
                is_admin,
            )
            self.message.text = "Uloga je sačuvana."
            self.refresh()
        except Exception:
            self.message.text = "Izmena uloge nije uspela. Proveri administratorska prava."

    def approve(self, profile_id: str):
        household = database.household()
        try:
            sync_service.api.approve_member(
                household["remote_id"], profile_id, household["remote_profile_id"]
            )
            self.message.text = "Član je odobren."
            self.refresh()
        except Exception:
            self.message.text = "Odobravanje nije uspelo. Proveri internet i administratorska prava."


class Expenses(Screen):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.filter_mode = "all"
        root = DashboardCard(orientation="vertical", padding=dp(16), spacing=dp(10), bg_color=PANEL_BG)
        root.add_widget(Label(text=text(language(), "expenses"), font_size=dp(25), size_hint_y=None, height=dp(38), color=TEXT, bold=True, halign="left"))
        filters = BoxLayout(size_hint_y=None, height=dp(38), spacing=dp(6))
        self.filter_buttons = {}
        for mode, label in (("all", "Sve"), ("shared", "Zajedničko"), ("personal", "Lično")):
            button = select_button(label, accent=ACCENT_MUTED, font_size=dp(11))
            button.bind(on_release=lambda _button, selected=mode: self.set_filter(selected))
            self.filter_buttons[mode] = button
            filters.add_widget(button)
        root.add_widget(filters)
        self.summary = Label(text="", color=TEXT_SOFT, font_size=dp(12), halign="left", size_hint_y=None, height=dp(24))
        root.add_widget(self.summary)
        self.items = GridLayout(cols=1, spacing=dp(8), size_hint_y=None)
        self.items.bind(minimum_height=self.items.setter("height"))
        scroll = ScrollView(do_scroll_x=False, do_scroll_y=True)
        scroll.add_widget(self.items)
        root.add_widget(scroll)
        add = action_button(text(language(), "new_expense"), accent=ACCENT_GREEN, text_color=(0.08, 0.12, 0.12, 1), font_size=dp(14))
        add.bind(on_release=lambda *_: setattr(self.manager, "current", "add"))
        root.add_widget(add)
        back = select_button(text(language(), "back"), accent=ACCENT_MUTED, text_color=TEXT, font_size=dp(14))
        back.bind(on_release=lambda *_: setattr(self.manager, "current", "dashboard"))
        root.add_widget(back)
        self.add_widget(root)

    def on_pre_enter(self, *args):
        self.refresh()

    def refresh(self):
        self.items.clear_widgets()
        rows = database.expenses()
        if self.filter_mode == "shared":
            rows = [row for row in rows if row["is_shared"]]
        elif self.filter_mode == "personal":
            rows = [row for row in rows if not row["is_shared"]]
        totals: dict[str, float] = {}
        for expense in rows:
            totals[expense["currency"]] = totals.get(expense["currency"], 0) + float(expense["amount"])
        total_text = " · ".join(f"{value:,.0f} {currency}".replace(",", ".") for currency, value in sorted(totals.items()))
        self.summary.text = f"{len(rows)} · {total_text}" if rows else "0"
        for mode, button in self.filter_buttons.items():
            button.color = TEXT if mode != self.filter_mode else (0.08, 0.12, 0.12, 1)
            self._draw_filter(button)
        if not rows:
            self.items.add_widget(Label(text="Nema troškova za izabrani prikaz.", color=TEXT_SOFT, size_hint_y=None, height=dp(72)))
            return
        for expense in rows:
            row = DashboardCard(orientation="horizontal", padding=(dp(10), dp(8)), spacing=dp(9), size_hint_y=None, height=dp(78), bg_color=PANEL_ALT)
            marker = Label(text=expense["category"][:1].upper(), size_hint_x=None, width=dp(34), color=ACCENT_GREEN, bold=True, font_size=dp(17))
            details = BoxLayout(orientation="vertical", spacing=dp(2))
            details.add_widget(Label(text=expense["category"], color=TEXT, font_size=dp(13), bold=True, halign="left", valign="middle"))
            description = expense["description"] or "Bez opisa"
            author = expense["author_name"] or database.household()["profile_name"]
            day = datetime.strptime(expense["expense_date"], "%Y-%m-%d").strftime("%d.%m.")
            mode = "Zajedničko" if expense["is_shared"] else "Lično"
            details.add_widget(Label(text=f"{description} · {author} · {day} · {mode}", color=TEXT_SOFT, font_size=dp(10), halign="left", valign="middle", shorten=True, shorten_from="right"))
            value = Label(text=f"{float(expense['amount']):,.0f} {expense['currency']}".replace(",", "."), color=TEXT, font_size=dp(12), bold=True, halign="right", size_hint_x=None, width=dp(82))
            remove = Button(text="×", size_hint=(None, None), size=(dp(30), dp(34)), background_normal="", background_down="", background_color=(0, 0, 0, 0), color=(0.88, 0.63, 0.49, 1), font_size=dp(20))
            remove.bind(on_release=lambda _, expense_id=expense["id"]: self.remove(expense_id))
            row.add_widget(marker)
            row.add_widget(details)
            row.add_widget(value)
            row.add_widget(remove)
            self.items.add_widget(row)

    def _draw_filter(self, button):
        button.canvas.before.clear()
        with button.canvas.before:
            Color(*(ACCENT_GREEN if button.color == (0.08, 0.12, 0.12, 1) else ACCENT_MUTED))
            RoundedRectangle(pos=button.pos, size=button.size, radius=[dp(10)])

    def set_filter(self, mode: str):
        self.filter_mode = mode
        self.refresh()

    def remove(self, expense_id: str):
        database.delete_expense(expense_id)
        self.refresh()


class AddExpense(Screen):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        Window.softinput_mode = "resize"
        scroll = ScrollView(do_scroll_x=False, do_scroll_y=True)
        root = DashboardCard(orientation="vertical", padding=dp(24), spacing=dp(16), bg_color=PANEL_BG, size_hint_y=None)
        root.bind(minimum_height=root.setter("height"))
        root.add_widget(Label(text="Novi trošak", font_size=dp(26), color=(0.96, 0.97, 0.94, 1), bold=True))
        self.amount = field("Iznos")
        self.amount.bind(focus=format_amount_on_blur)
        self.description = field("Opis")
        household = database.household()
        author_name = household["profile_name"] if household else "Autor troška"
        self.author = spinner_field(author_name, (author_name,))
        self.category = spinner_field("Kategorija", tuple(database.categories()))
        self.currency = spinner_field(
            household["default_currency"] if household else "RSD",
            ("RSD", "EUR", "USD"),
            height=dp(48),
        )
        self.shared = CheckBox(size_hint=(None, None), size=(dp(36), dp(36)))
        shared_row = BoxLayout(size_hint_y=None, height=dp(40))
        shared_row.add_widget(self.shared)
        shared_row.add_widget(Label(text="Zajednički trošak"))
        root.add_widget(self.amount)
        root.add_widget(self.category)
        root.add_widget(self.currency)
        root.add_widget(self.description)
        root.add_widget(self.author)
        root.add_widget(shared_row)
        save = action_button("Sačuvaj", accent=(0.67, 0.82, 0.72, 1), text_color=(0.08, 0.12, 0.12, 1), font_size=dp(15))
        save.bind(on_release=self.save)
        root.add_widget(save)
        self.message = Label(text="", color=(0.96, 0.96, 0.92, 1), font_size=dp(14))
        root.add_widget(self.message)
        back = select_button("Nazad", accent=(0.21, 0.26, 0.26, 1), text_color=(0.95, 0.95, 0.90, 1), font_size=dp(15))
        back.bind(on_release=lambda *_: setattr(self.manager, "current", "dashboard"))
        root.add_widget(back)
        scroll.add_widget(root)
        self.add_widget(scroll)

    def on_pre_enter(self, *args):
        household = database.household()
        categories = database.categories()
        self.category.values = categories
        if self.category.text not in categories:
            self.category.text = "Kategorija"
        if household:
            self.currency.text = household["default_currency"]
            self.author.values = (household["profile_name"],)
            self.author.text = household["profile_name"]
            if household["remote_id"] and household["remote_profile_id"]:
                try:
                    members = sync_service.api.members(household["remote_id"])
                    approved = tuple(member["profile_name"] for member in members if member["approved"])
                    if approved:
                        self.author.values = approved
                        if self.author.text not in approved:
                            self.author.text = approved[0]
                except Exception:
                    pass

    def save(self, *_):
        try:
            amount = parse_amount(self.amount.text)
        except ValueError:
            self.message.text = "Unos nije validan. Trošak nije sačuvan."
            return
        if amount <= 0:
            self.message.text = "Unos nije validan. Trošak nije sačuvan."
            return
        if self.category.text == "Kategorija":
            self.message.text = "Izaberi kategoriju. Trošak nije sačuvan."
            return
        database.add_expense(
            amount,
            self.currency.text,
            self.category.text,
            self.description.text.strip(),
            self.shared.active,
            self.author.text.strip() or (database.household()["profile_name"] if database.household() else ""),
        )
        self.amount.text = ""
        self.description.text = ""
        self.category.text = "Kategorija"
        self.shared.active = False
        self.message.text = "Trošak je sačuvan."


class Settings(Screen):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        root = DashboardCard(orientation="vertical", padding=dp(20), spacing=dp(12), bg_color=PANEL_BG)
        self.heading = Label(text=text(language(), "settings"), font_size=dp(25), size_hint_y=None, height=dp(44), color=TEXT, bold=True)
        root.add_widget(self.heading)
        root.add_widget(Label(text="Podrazumevana valuta", size_hint_y=None, height=dp(34), color=(0.94, 0.95, 0.90, 1), font_size=dp(16)))
        household = database.household()
        self.currency = spinner_field(
            household["default_currency"] if household else "RSD",
            ("RSD", "EUR", "USD"),
            height=dp(48),
        )
        root.add_widget(self.currency)
        root.add_widget(Label(text=text(language(), "language"), size_hint_y=None, height=dp(34), color=(0.94, 0.95, 0.90, 1), font_size=dp(16)))
        self.language_spinner = spinner_field(
            language_label(language()),
            LANGUAGE_OPTIONS,
            height=dp(48),
        )
        root.add_widget(self.language_spinner)
        root.add_widget(Label(text="Tema", size_hint_y=None, height=dp(34), color=(0.94, 0.95, 0.90, 1), font_size=dp(16)))
        household = database.household()
        self.theme_spinner = spinner_field(
            "Tamna" if not household or household["theme"] == "dark" else "Svetla",
            ("Tamna", "Svetla"),
            height=dp(48),
        )
        root.add_widget(self.theme_spinner)
        save = action_button("Sačuvaj izmene", accent=(0.62, 0.78, 0.73, 1), text_color=(0.09, 0.12, 0.12, 1), font_size=dp(15))
        save.bind(on_release=self.save)
        root.add_widget(save)
        self.message = Label(text="", color=(0.96, 0.96, 0.92, 1), font_size=dp(14))
        root.add_widget(self.message)
        self.reset_armed = False
        reset_running = select_button("Resetuj running zbir", accent=(0.26, 0.20, 0.22, 1), font_size=dp(15))
        reset_running.bind(on_release=self.reset_running)
        root.add_widget(reset_running)
        back = select_button("Nazad", accent=(0.21, 0.26, 0.26, 1), text_color=(0.95, 0.95, 0.90, 1), font_size=dp(15))
        back.bind(on_release=lambda *_: setattr(self.manager, "current", "dashboard"))
        root.add_widget(back)
        self.add_widget(root)

    def reset_running(self, *_):
        if not self.reset_armed:
            self.reset_armed = True
            self.message.text = "Ponovo pritisni Resetuj running zbir za potvrdu."
            return
        database.reset_running_total()
        self.reset_armed = False
        self.message.text = "Running zbir je resetovan. Istorijski troškovi su sačuvani."

    def refresh_labels(self):
        self.heading.text = text(language(), "settings")

    def refresh(self):
        household = database.household()
        if household:
            self.currency.text = household["default_currency"]
            self.language_spinner.text = language_label(household["language"])
            self.theme_spinner.text = "Tamna" if household["theme"] == "dark" else "Svetla"

    def save(self, *_):
        database.set_default_currency(self.currency.text)
        database.set_language(language_code(self.language_spinner.text))
        database.set_theme("dark" if self.theme_spinner.text == "Tamna" else "light")
        apply_theme()
        self.message.text = "Podešavanja su sačuvana."
        self.manager.get_screen("dashboard").refresh()


class Stats(Screen):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        screen_root = BoxLayout(orientation="vertical", padding=dp(16), spacing=dp(10))
        scroll = ScrollView(do_scroll_x=False, do_scroll_y=True)
        root = DashboardCard(orientation="vertical", padding=dp(20), spacing=dp(12), bg_color=PANEL_BG, size_hint=(1, None))
        root.bind(minimum_height=root.setter("height"))
        root.add_widget(Label(text="Statistika", font_size=dp(25), size_hint_y=None, height=dp(38), color=TEXT, bold=True))
        self.month_periods = self._month_periods()
        self.period = spinner_field("Ovaj mesec", self.month_periods, height=dp(48))
        self.period.bind(text=lambda *_: self.refresh())
        root.add_widget(self.period)
        self.start_input = field("Početni datum (dd/mm/yyyy)")
        self.end_input = field("Krajnji datum (dd/mm/yyyy)")
        self.start_input.bind(text=format_date_input)
        self.end_input.bind(text=format_date_input)
        root.add_widget(self.start_input)
        root.add_widget(self.end_input)
        root.add_widget(Label(text="Ukupna potrošnja", color=TEXT_SOFT, font_size=dp(13), halign="left", size_hint_y=None, height=dp(20)))
        self.total_value = Label(text="0 RSD", color=TEXT, font_size=dp(34), bold=True, halign="left", size_hint_y=None, height=dp(42))
        root.add_widget(self.total_value)

        metrics = BoxLayout(size_hint_y=None, height=dp(54), spacing=dp(12))
        shared_metric = BoxLayout(orientation="vertical", spacing=dp(2))
        shared_metric.add_widget(Label(text="ZAJEDNIČKA", color=ACCENT_GREEN, font_size=dp(11), halign="left"))
        self.shared_value = Label(text="0 RSD", color=TEXT, font_size=dp(16), bold=True, halign="left")
        shared_metric.add_widget(self.shared_value)
        personal_metric = BoxLayout(orientation="vertical", spacing=dp(2))
        personal_metric.add_widget(Label(text="LIČNA", color=(0.88, 0.63, 0.49, 1), font_size=dp(11), halign="left"))
        self.personal_value = Label(text="0 RSD", color=TEXT, font_size=dp(16), bold=True, halign="left")
        personal_metric.add_widget(self.personal_value)
        metrics.add_widget(shared_metric)
        metrics.add_widget(personal_metric)
        root.add_widget(metrics)

        root.add_widget(Label(text="Potrošnja po kategoriji", color=TEXT, font_size=dp(15), bold=True, halign="left", size_hint_y=None, height=dp(24)))
        legend = BoxLayout(size_hint_y=None, height=dp(22), spacing=dp(16))
        shared_legend = BoxLayout(size_hint=(None, 1), width=dp(112), spacing=dp(6))
        shared_legend.add_widget(LegendSwatch((0.41, 0.60, 0.50, 1)))
        shared_legend.add_widget(Label(text="Zajednička", color=TEXT_SOFT, font_size=dp(11), size_hint_x=None, width=dp(82)))
        personal_legend = BoxLayout(size_hint=(None, 1), width=dp(72), spacing=dp(6))
        personal_legend.add_widget(LegendSwatch((0.78, 0.52, 0.39, 1)))
        personal_legend.add_widget(Label(text="Lična", color=TEXT_SOFT, font_size=dp(11), size_hint_x=None, width=dp(46)))
        legend.add_widget(shared_legend)
        legend.add_widget(personal_legend)
        root.add_widget(legend)

        self.chart = CategoryBarChart(size_hint_y=None, height=dp(12))
        root.add_widget(self.chart)
        root.add_widget(Label(text="Po članu", color=TEXT, font_size=dp(15), bold=True, halign="left", size_hint_y=None, height=dp(24)))
        self.members_summary = BoxLayout(orientation="vertical", spacing=dp(4), size_hint_y=None)
        self.members_summary.bind(minimum_height=self.members_summary.setter("height"))
        root.add_widget(self.members_summary)
        self.balance = Label(text="", color=TEXT, font_size=dp(14), bold=True, halign="left", valign="middle", size_hint_y=None, height=dp(52))
        root.add_widget(self.balance)
        self.validation = Label(text="", color=(0.96, 0.70, 0.58, 1), font_size=dp(13), size_hint_y=None, height=dp(24))
        root.add_widget(self.validation)
        scroll.add_widget(root)
        screen_root.add_widget(scroll)
        back = select_button("Nazad", accent=ACCENT_MUTED, text_color=TEXT, font_size=dp(15))
        back.bind(on_release=lambda *_: setattr(self.manager, "current", "dashboard"))
        screen_root.add_widget(back)
        self.add_widget(screen_root)

    def on_pre_enter(self, *args):
        self.refresh()

    def refresh(self):
        custom = self.period.text == "Prilagođeni period"
        self.start_input.height = dp(48) if custom else 0
        self.end_input.height = dp(48) if custom else 0
        self.start_input.opacity = 1 if custom else 0
        self.end_input.opacity = 1 if custom else 0
        self.start_input.disabled = not custom
        self.end_input.disabled = not custom
        end = date.today()
        starts = {
            "Danas": end,
            "Ova nedelja": end - timedelta(days=end.weekday()),
            "Ovaj mesec": end.replace(day=1),
            "Ova godina": end.replace(month=1, day=1),
        }
        if self.period.text == "Prilagođeni period":
            try:
                start = datetime.strptime(self.start_input.text, "%d/%m/%Y").date()
                custom_end = datetime.strptime(self.end_input.text, "%d/%m/%Y").date()
            except ValueError:
                self.validation.text = "Unesi datume u formatu dd/mm/yyyy."
                return
            if custom_end < start:
                self.validation.text = "Krajnji datum ne može biti pre početnog."
                return
            start_date, end_date = start, custom_end
        elif self.period.text in self._month_period_map:
            start_date = self._month_period_map[self.period.text]
            end_date = date(
                start_date.year,
                start_date.month,
                calendar.monthrange(start_date.year, start_date.month)[1],
            )
        else:
            start_date, end_date = starts[self.period.text], end
        rows = database.category_totals(start_date.isoformat(), end_date.isoformat())
        spending = database.spending_summary(start_date.isoformat(), end_date.isoformat())
        self.validation.text = ""
        self.total_value.text = self._format_stat(spending["total"])
        self.shared_value.text = self._format_stat(spending["shared"])
        self.personal_value.text = self._format_stat(spending["personal"])
        chart_rows = [
            (row["category"], float(row["total"]), float(row["shared"]), float(row["personal"]), row["currency"])
            for row in rows
        ]
        self.chart.height = max(dp(12), dp(38) * len(chart_rows))
        self.chart.set_data(chart_rows)
        self.members_summary.clear_widgets()
        for author in spending["authors"]:
            name = author["author_name"] or "Nepoznat autor"
            total = float(author["total"])
            shared = float(author["shared"])
            personal = total - shared
            member_row = BoxLayout(orientation="vertical", spacing=dp(2), size_hint_y=None, height=dp(42))
            member_row.add_widget(Label(text=f"{name} · {self._format_stat(total)}", color=TEXT, font_size=dp(13), bold=True, halign="left"))
            member_row.add_widget(Label(text=f"Zajedničko {self._format_stat(shared)}   ·   Lično {self._format_stat(personal)}", color=TEXT_SOFT, font_size=dp(11), halign="left"))
            self.members_summary.add_widget(member_row)
        running = spending["running"]
        if len(running) >= 2:
            leader, second = running[0], running[1]
            difference = float(leader["shared"]) - float(second["shared"])
            self.balance.text = f"Kumulativno od resetovanja\n{leader['author_name'] or 'Nepoznat autor'} · prednost {self._format_stat(difference)}"
        elif running:
            self.balance.text = "Kumulativno od resetovanja\nPotrebna su najmanje dva člana za poređenje."
        else:
            self.balance.text = "Kumulativno od resetovanja\nJoš nema zajedničkih troškova."
        if not rows:
            self.chart.set_data([])
            self.validation.text = "Nema troškova za izabrani period."
            return

    @staticmethod
    def _format_stat(value: float) -> str:
        return f"{value:,.0f}".replace(",", ".") + " RSD"

    @staticmethod
    def _month_periods() -> list[str]:
        today = date.today().replace(day=1)
        periods = ["Danas", "Ova nedelja", "Ovaj mesec", "Ova godina", "Prilagođeni period"]
        Stats._month_period_map = {"Ovaj mesec": today}
        year, month = today.year, today.month
        for offset in range(1, 37):
            month -= 1
            if month == 0:
                month = 12
                year -= 1
            label = f"{month:02d}/{year}"
            Stats._month_period_map[label] = date(year, month, 1)
            periods.insert(-1, label)
        return periods


class HomeBudgetApp(App):
    def build(self):
        apply_theme()
        manager = ScreenManager()
        manager.add_widget(Welcome(name="welcome"))
        manager.add_widget(Dashboard(name="dashboard"))
        manager.add_widget(Expenses(name="expenses"))
        manager.add_widget(Manage(name="manage"))
        manager.add_widget(Members(name="members"))
        manager.add_widget(AddExpense(name="add"))
        manager.add_widget(Settings(name="settings"))
        manager.add_widget(Stats(name="stats"))
        manager.current = "welcome"
        return manager


if __name__ == "__main__":
    HomeBudgetApp().run()
