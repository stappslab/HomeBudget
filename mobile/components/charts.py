from kivy.graphics import Color, RoundedRectangle
from kivy.metrics import dp
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.label import Label
from kivy.uix.widget import Widget


class StackedCategoryBar(Widget):
    def __init__(self, shared: float, personal: float, maximum: float, **kwargs):
        super().__init__(size_hint_y=None, height=dp(12), **kwargs)
        self.shared = shared
        self.personal = personal
        self.maximum = maximum or 1
        self.bind(pos=self._draw, size=self._draw)

    def _draw(self, *_args):
        self.canvas.clear()
        total_width = self.width * min((self.shared + self.personal) / self.maximum, 1)
        shared_width = total_width * self.shared / max(self.shared + self.personal, 1)
        with self.canvas:
            Color(0.20, 0.27, 0.27, 1)
            RoundedRectangle(pos=self.pos, size=self.size, radius=[dp(6)])
            if shared_width > 0:
                Color(0.41, 0.60, 0.50, 1)
                RoundedRectangle(pos=self.pos, size=(shared_width, self.height), radius=[dp(6)])
            personal_width = total_width - shared_width
            if personal_width > 0:
                Color(0.78, 0.52, 0.39, 1)
                RoundedRectangle(
                    pos=(self.x + shared_width, self.y),
                    size=(personal_width, self.height),
                    radius=[dp(6)],
                )


class CategoryBarChart(BoxLayout):
    def __init__(self, **kwargs):
        super().__init__(orientation="vertical", spacing=dp(10), **kwargs)
        self.data: list[tuple[str, float, float, float, str]] = []

    def set_data(self, data: list[tuple[str, float, float, float, str]]) -> None:
        self.data = data[:8]
        self.clear_widgets()
        maximum = max((row[1] for row in self.data), default=0) or 1
        for category, total, shared, personal, currency in self.data:
            row = BoxLayout(orientation="vertical", spacing=dp(4), size_hint_y=None, height=dp(38))
            heading = BoxLayout(size_hint_y=None, height=dp(20), spacing=dp(8))
            heading.add_widget(Label(
                text=category,
                color=(0.96, 0.97, 0.94, 1),
                font_size=dp(13),
                bold=True,
                halign="left",
                valign="middle",
                text_size=(None, None),
            ))
            heading.add_widget(Label(
                text=f"{total:,.0f} {currency}".replace(",", "."),
                color=(0.83, 0.88, 0.84, 1),
                font_size=dp(12),
                halign="right",
                valign="middle",
            ))
            row.add_widget(heading)
            row.add_widget(StackedCategoryBar(shared, personal, maximum))
            self.add_widget(row)
