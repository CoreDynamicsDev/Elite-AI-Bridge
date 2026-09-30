from __future__ import annotations

import random
import time
from pathlib import Path

from PySide6.QtCore import QTimer, Qt
from PySide6.QtGui import QColor, QFont, QPainter, QPen, QPixmap
from PySide6.QtWidgets import QWidget


class BootSplash(QWidget):
    """Cinematic CRT boot screen for Elite AI Bridge.

    The artwork is a static CRT console. Only the deliberately animated pieces
    are painted at runtime: progress fills, status values, and boot-log typing.
    The animation is presentation-only and is intentionally independent of
    real subsystem readiness.
    """

    DESIGN_W = 1672.0
    DESIGN_H = 941.0

    # Exact artwork coordinates on the 1672x941 design canvas.
    BAR_X = 570.0
    BAR_W = 555.0
    BAR_H = 19.0
    # These are the actual rail positions in the source artwork. Keeping all
    # runtime geometry in the artwork's native 1672x941 coordinate space lets
    # Qt scale the entire splash uniformly on 1080p, 1440p, 4K, etc.
    BAR_Y = (439.0, 504.0, 571.0, 638.0)
    PERCENT_X = 1148.0
    PERCENT_W = 50.0
    STEP_X = 1128.0
    STEP_W = 70.0

    def __init__(self, screen, background_path: Path):
        super().__init__(None)
        self.setWindowTitle("Elite AI Bridge")
        self.setWindowFlags(Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool)
        self.setAttribute(Qt.WA_DeleteOnClose, True)
        self.setAttribute(Qt.WA_TranslucentBackground, False)
        self.setStyleSheet("background:#020402;")

        self._screen = screen
        self._bg = QPixmap(str(background_path)) if background_path.exists() else QPixmap()
        self._scaled_bg = QPixmap()
        self._scale = 1.0
        self._offset_x = 0.0
        self._offset_y = 0.0
        self._elapsed = 0.0
        self._last_tick = time.monotonic()
        self._cursor_on = True
        self._closing = False
        self._fade = 1.0
        self._fade_active = False
        self._started_at = time.monotonic()
        self._min_display_seconds = 15.0
        self._max_display_seconds = 30.0
        self._ready_probe = None
        self._main_window = None

        # Four smooth, deliberately different presentation curves.
        self._bar_rates = [0.075, 0.052, 0.064, 0.043]
        self._bar_offsets = [0.03, 0.27, 0.54, 0.79]
        self._bar_caps = [0.96, 0.91, 0.94, 0.88]

        # The boot log is the animated typing surface. One line intentionally
        # corrects itself with a short backspace sequence.
        self._type_lines = [
            "INITIALIZING BRIDGE CORE...",
            "LOADING VOICE SYSTEMS...",
            "CALIBRATING CONTROL INTERFACE...",
            "ESTABLISHING DATA LINK...",
            "PREPARING FLIGHT TOOLS...",
            "SYNCING USER ENVIRONMENT...",
        ]
        self._typed_line = 0
        self._typed_index = 0
        self._typed_pause = 0.18
        self._typed_mode = "type"
        self._typed_speed = 0.038
        self._log_lines: list[str] = []
        self._log_timer = 0.0
        self._log_cursor = True
        self._log_counter = 0

        self._background_lines = [
            "MEMORY CHECK ............... OK",
            "LOCAL CACHE ................ STABLE",
            "COMMAND BUS ................ READY",
            "AUDIO PIPELINE ............. ONLINE",
            "CONTROL MAP ................ LOADED",
            "DATA SERVICES .............. CONNECTED",
            "UI ASSET INDEX ............. READY",
            "SESSION STATE .............. RESTORED",
            "FLIGHT TOOLS ............... ARMED",
            "BRIDGE LINK ................ STABLE",
        ]

        self._anim_timer = QTimer(self)
        self._anim_timer.setInterval(33)
        self._anim_timer.timeout.connect(self._tick)
        self._anim_timer.start()

        self._ready_timer = QTimer(self)
        self._ready_timer.setInterval(100)
        self._ready_timer.timeout.connect(self._probe_ready)
        self._ready_timer.start()

        if screen is not None:
            try:
                self.setGeometry(screen.geometry())
            except Exception:
                pass
        self._update_scaled_background()

    def set_ready_probe(self, probe):
        self._ready_probe = probe

    def set_main_window(self, window):
        self._main_window = window

    def showEvent(self, event):
        super().showEvent(event)
        self._started_at = time.monotonic()
        self._last_tick = self._started_at
        self.raise_()
        self.activateWindow()

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self._update_scaled_background()

    def _update_scaled_background(self):
        if self._bg.isNull():
            self._scaled_bg = QPixmap()
            return
        # Fit the 1672x941 artwork uniformly inside the target display.
        # Do not stretch or crop it. This keeps every overlay coordinate locked
        # to the artwork on different resolutions and aspect ratios.
        w = float(self.width())
        h = float(self.height())
        self._scale = min(w / self.DESIGN_W, h / self.DESIGN_H)
        scaled_w = max(1, int(round(self.DESIGN_W * self._scale)))
        scaled_h = max(1, int(round(self.DESIGN_H * self._scale)))
        self._offset_x = (w - scaled_w) / 2.0
        self._offset_y = (h - scaled_h) / 2.0
        self._scaled_bg = self._bg.scaled(
            scaled_w, scaled_h, Qt.IgnoreAspectRatio, Qt.SmoothTransformation
        )

    @staticmethod
    def _clamp(value, low=0.0, high=1.0):
        return max(low, min(high, value))

    @staticmethod
    def _ease(value):
        value = BootSplash._clamp(value)
        return value * value * (3.0 - 2.0 * value)

    def _bar_value(self, index: int) -> float:
        phase = ((self._elapsed * self._bar_rates[index]) + self._bar_offsets[index]) % 1.0
        # Keep the first second calm, then settle into the looping presentation.
        if self._elapsed < 1.0:
            phase = min(phase, self._elapsed / 1.0)
        return min(self._bar_caps[index], 0.04 + self._ease(phase) * 0.84)

    def _tick(self):
        now = time.monotonic()
        dt = max(0.0, min(0.08, now - self._last_tick))
        self._last_tick = now
        self._elapsed += dt
        self._cursor_on = int(self._elapsed * 2.0) % 2 == 0
        self._log_cursor = int(self._elapsed * 1.8) % 2 == 0

        self._advance_typing(dt)
        self._log_timer += dt
        if self._log_timer >= 1.05:
            self._log_timer = 0.0
            self._log_counter += 1
            line = self._background_lines[(self._log_counter - 1) % len(self._background_lines)]
            stamp = f"[{int(self._elapsed):02d}:{int((self._elapsed * 10) % 60):02d}]  "
            self._log_lines.append(stamp + line)
            self._log_lines = self._log_lines[-6:]

        if self._fade_active:
            self._fade = max(0.0, self._fade - dt / 0.45)
            if self._fade <= 0.0:
                self._anim_timer.stop()
                self._ready_timer.stop()
                self.close()
                return
        self.update()

    def _advance_typing(self, dt):
        self._typed_pause = max(0.0, self._typed_pause - dt)
        if self._typed_pause > 0:
            return

        line = self._type_lines[self._typed_line]
        if self._typed_mode == "type":
            if self._typed_index < len(line):
                self._typed_index += 1
                self._typed_pause = self._typed_speed * (0.60 + random.random() * 0.55)
            else:
                self._typed_mode = "pause"
                self._typed_pause = 0.70
        elif self._typed_mode == "pause":
            if self._typed_line == 2:
                self._typed_mode = "backspace"
                self._typed_pause = 0.08
            else:
                self._advance_to_next_line()
        elif self._typed_mode == "backspace":
            if self._typed_index > 11:
                self._typed_index -= 1
                self._typed_pause = 0.025
            else:
                self._type_lines[self._typed_line] = "CALIBRATING FLIGHT INTERFACE..."
                self._typed_index = 0
                self._typed_mode = "replace"
                self._typed_pause = 0.12
        elif self._typed_mode == "replace":
            if self._typed_index < len(self._type_lines[self._typed_line]):
                self._typed_index += 1
                self._typed_pause = self._typed_speed * (0.60 + random.random() * 0.55)
            else:
                self._typed_mode = "pause"
                self._typed_pause = 0.65
        else:
            self._advance_to_next_line()

    def _advance_to_next_line(self):
        self._typed_line = (self._typed_line + 1) % len(self._type_lines)
        self._typed_index = 0
        self._typed_mode = "type"
        self._typed_pause = 0.16
        self._type_lines[2] = "CALIBRATING CONTROL INTERFACE..."

    def _probe_ready(self):
        if self._closing or self._fade_active:
            return
        age = time.monotonic() - self._started_at
        if age < self._min_display_seconds:
            return
        ready = False
        try:
            ready = bool(self._ready_probe and self._ready_probe())
        except Exception:
            ready = False
        if ready or age >= self._max_display_seconds:
            self.finish()

    def finish(self):
        if self._closing or self._fade_active:
            return
        self._closing = True
        self._fade_active = True

    def _design_rect(self, x, y, w, h, sx=None, sy=None):
        # sx/sy are retained for compatibility with the existing drawing code,
        # but the splash itself always uses one uniform scale.
        scale_x = self._scale if sx is None else sx
        scale_y = self._scale if sy is None else sy
        return (
            int(self._offset_x + x * scale_x),
            int(self._offset_y + y * scale_y),
            int(w * scale_x),
            int(h * scale_y),
        )

    def _font(self, size, scale, bold=False):
        f = QFont("Consolas", max(8, int(size * scale)))
        f.setStyleHint(QFont.Monospace)
        f.setBold(bold)
        return f

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.SmoothPixmapTransform, True)
        w = float(self.width())
        h = float(self.height())
        s = self._scale
        sx = sy = s

        if not self._scaled_bg.isNull():
            painter.drawPixmap(int(self._offset_x), int(self._offset_y), self._scaled_bg)
        else:
            painter.fillRect(self.rect(), QColor("#020402"))

        # Unified CRT treatment. This is intentionally subtle.
        painter.fillRect(self.rect(), QColor(0, 8, 2, 26))
        painter.setPen(QPen(QColor(60, 255, 125, 12), max(1, int(s))))
        step = max(3.0, 4.0 * sy)
        yy = 0.0
        while yy < h:
            painter.drawLine(0, int(yy), int(w), int(yy))
            yy += step

        green = QColor(70, 255, 130, int(235 * self._fade))
        pale = QColor(180, 255, 205, int(230 * self._fade))
        dim = QColor(65, 205, 110, int(205 * self._fade))

        # Animated progress fills. The rails themselves belong to the artwork.
        segments = 24
        gap = 3.0
        seg_w = (self.BAR_W - 6.0 - gap * (segments - 1)) / segments
        for i, by in enumerate(self.BAR_Y):
            active = int(self._bar_value(i) * segments)
            for j in range(active):
                xx = self.BAR_X + 3.0 + j * (seg_w + gap)
                alpha = 145 + int(85 * (j / max(1, segments - 1)))
                painter.fillRect(
                    *self._design_rect(xx, by + 3, seg_w, 13, sx, sy),
                    QColor(55, 245, 120, int(alpha * self._fade)),
                )

        # Dynamic step counter and percentage readouts.
        completed = min(4, int(self._elapsed / 2.4))
        painter.setFont(self._font(20, s, True))
        painter.setPen(green)
        painter.drawText(
            *self._design_rect(self.STEP_X, 357, self.STEP_W, 32, sx, sy),
            Qt.AlignRight | Qt.AlignVCenter,
            f"{completed} / 4",
        )
        for i, y in enumerate((430, 497, 561, 628)):
            pct = int(self._bar_value(i) * 100)
            painter.drawText(
                *self._design_rect(self.PERCENT_X, y, self.PERCENT_W, 34, sx, sy),
                Qt.AlignRight | Qt.AlignVCenter,
                f"{pct}%",
            )

        # Left system/control checks populate the actual bracket fields in the
        # artwork. There are 11 system rows and 4 control rows. Keeping these
        # as two explicit groups prevents the old off-by-one jump that caused
        # OK to land on the wrong labels. This is decorative, not real readiness.
        system_rows = [216, 239, 262, 285, 308, 331, 354, 377, 400, 423, 446]
        control_rows = [557, 581, 605, 629]
        total_checks = len(system_rows) + len(control_rows)
        ok_count = min(total_checks, int(self._elapsed * 2.1))
        painter.setFont(self._font(17, s, True))
        painter.setPen(dim)
        for idx in range(ok_count):
            row_y = system_rows[idx] if idx < len(system_rows) else control_rows[idx - len(system_rows)]
            painter.drawText(
                *self._design_rect(311, row_y - 12, 58, 25, sx, sy),
                Qt.AlignCenter | Qt.AlignVCenter,
                "OK",
            )

        # Vessel panel values stay inside the narrow bracket fields already
        # present in the artwork. Use compact values so they cannot collide with
        # the labels or the right bracket on smaller displays.
        vessel = ["READY", "CD28K", "RAVEN", "NO", "DEEP", "READY"]
        vessel_y = [246, 269, 292, 315, 338, 361]
        painter.setFont(self._font(13, s))
        painter.setPen(dim)
        for value, vy in zip(vessel, vessel_y):
            painter.drawText(
                *self._design_rect(1534, vy - 11, 52, 22, sx, sy),
                Qt.AlignRight | Qt.AlignVCenter,
                value,
            )

        # Network feed values live between the labels and their right-side
        # bracket, rather than starting at the label edge.
        network = ["ONLINE", "ACTIVE", "ONLINE", "3 NEW"]
        network_y = [596, 619, 642, 665]
        painter.setFont(self._font(13, s))
        for value, ny in zip(network, network_y):
            painter.drawText(
                *self._design_rect(1486, ny - 11, 102, 22, sx, sy),
                Qt.AlignRight | Qt.AlignVCenter,
                value,
            )

        # Boot log: typed line plus completed lines. This is the main motion
        # element besides the bars.
        painter.setFont(self._font(15, s))
        painter.setPen(dim)
        log_y = 737.0
        for line in self._log_lines:
            painter.drawText(
                *self._design_rect(540, log_y, 570, 23, sx, sy),
                Qt.AlignLeft | Qt.AlignVCenter,
                line,
            )
            log_y += 23.0

        typed = self._type_lines[self._typed_line][:self._typed_index]
        cursor = "_" if self._log_cursor else " "
        painter.setPen(pale)
        painter.drawText(
            *self._design_rect(540, log_y, 570, 23, sx, sy),
            Qt.AlignLeft | Qt.AlignVCenter,
            typed + cursor,
        )

        # Bottom boot message is intentionally static until the final handoff.
        painter.setFont(self._font(16, s, True))
        painter.setPen(green)
        msg = "SYSTEMS ONLINE // LAUNCHING BRIDGE" if self._closing else "CORE DYNAMICS DEV // BRIDGE INITIALIZATION"
        painter.drawText(
            *self._design_rect(520, 891, 630, 28, sx, sy),
            Qt.AlignCenter | Qt.AlignVCenter,
            msg,
        )

        painter.end()
