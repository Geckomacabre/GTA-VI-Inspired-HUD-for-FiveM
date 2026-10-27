"""shots.py: the README's pictures (docs/*.jpg), 1920x1080, from serve.py's preview (run `python serve.py` first).
Needs Python Playwright with its Chromium."""
import os
import tempfile

from PIL import Image
from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), 'docs')
BASE = 'http://127.0.0.1:8767/'
os.makedirs(OUT, exist_ok=True)


def settle(page):
    page.wait_for_timeout(1500)


def home(page):
    page.goto(BASE)
    settle(page)
    page.keyboard.press('ArrowDown')
    page.keyboard.press('ArrowRight')
    page.wait_for_timeout(500)


def settings(page):
    page.goto(BASE + '?screen=settings')
    settle(page)
    page.keyboard.press('ArrowDown')
    page.wait_for_timeout(800)


def stats(page):
    page.goto(BASE + '?screen=stats&bg=boat')
    settle(page)
    for _ in range(3):
        page.keyboard.press('ArrowDown')
    page.wait_for_timeout(800)


def report(page):
    page.goto(BASE + '?screen=report&bg=report')
    settle(page)
    page.keyboard.press('ArrowRight')
    page.keyboard.press('ArrowDown')
    page.keyboard.type('Car stuck in a wall')
    page.keyboard.press('Tab')
    page.keyboard.type('Near the pier my car went through the floor and I cannot get it out. '
                       'It happened just after the 14:00 restart.')
    page.wait_for_timeout(800)


def map_page(page):
    page.goto(BASE + '?map=1&pad=1')
    settle(page)


SHOTS = {'home': home, 'settings': settings, 'stats': stats, 'report': report, 'map': map_page}

with tempfile.TemporaryDirectory() as tmp, sync_playwright() as p:
    browser = p.chromium.launch()
    page = browser.new_page(viewport={'width': 1920, 'height': 1080})
    for name, go in SHOTS.items():
        go(page)
        png = os.path.join(tmp, name + '.png')
        page.screenshot(path=png)
        Image.open(png).convert('RGB').save(os.path.join(OUT, name + '.jpg'), 'JPEG', quality=86, optimize=True)
        print(name, os.path.getsize(os.path.join(OUT, name + '.jpg')) // 1024, 'KB')
    browser.close()
