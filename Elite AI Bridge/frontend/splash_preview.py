"""Shows the boot splash on its own (no backend, no main window), then exits.
Run with RUN_SPLASH_PREVIEW.bat. The frame rate is written to splash_perf.log."""
import sys
from PySide6.QtCore import Qt
from PySide6.QtGui import QGuiApplication
from PySide6.QtWidgets import QApplication
from boot_splash import BootSplash

if __name__ == "__main__":
    QGuiApplication.setHighDpiScaleFactorRoundingPolicy(Qt.HighDpiScaleFactorRoundingPolicy.PassThrough)
    app = QApplication(sys.argv)
    splash = BootSplash(QGuiApplication.primaryScreen(), None)
    splash.set_ready_probe(lambda: True)
    splash.destroyed.connect(app.quit)
    splash.showFullScreen()
    splash.raise_()
    sys.exit(app.exec())
