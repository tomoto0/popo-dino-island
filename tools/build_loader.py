#!/usr/bin/env python3
"""Re-theme web/loading.html for Popo's Dino Island (Japanese text, M PLUS Rounded 1c
loader subset, embedded cover art). Engine placeholders, progress, retry and the
loading-screen meta tag are preserved. Usage: python3 tools/build_loader.py <medium.woff2> <extrabold.woff2> <art.webp>"""
import base64
import re
import sys

PATH = "web/loading.html"
medium, bold, art = (open(p, "rb").read() for p in sys.argv[1:4])
b64 = lambda data: base64.b64encode(data).decode("ascii")
s = open(PATH, encoding="utf-8").read()

s = s.replace('<html lang="en">', '<html lang="ja">', 1)
s = re.sub(
    r"<!-- Embedded Noto Sans SC loader subset:.*?-->",
    "<!-- Embedded M PLUS Rounded 1c loader subset (loader text only): SIL Open Font License 1.1; license text: assets/game/fonts/MPLUSRounded1c-OFL.txt. -->",
    s, count=1, flags=re.S)
fonts = (
    "/* manus-loader-cjk:start */\n"
    "/* M PLUS Rounded 1c loader subset. SIL Open Font License 1.1 (https://openfontlicense.org); license text: assets/game/fonts/MPLUSRounded1c-OFL.txt. */\n"
    f'@font-face{{font-family:"Popo Loader";font-style:normal;font-weight:400 600;font-display:block;src:url(data:font/woff2;base64,{b64(medium)}) format("woff2")}}\n'
    f'@font-face{{font-family:"Popo Loader";font-style:normal;font-weight:700 900;font-display:block;src:url(data:font/woff2;base64,{b64(bold)}) format("woff2")}}\n'
    "/* manus-loader-cjk:end */")
s = re.sub(r"/\* manus-loader-cjk:start \*/.*?/\* manus-loader-cjk:end \*/", lambda _m: fonts, s, count=1, flags=re.S)
s = s.replace('font-family: "Noto Sans SC", sans-serif;', 'font-family: "Popo Loader", "Hiragino Maru Gothic ProN", "Yu Gothic", sans-serif;')

art_css = f"""  <style id="loading-art">
    html, body {{ background: #3b2414; color: #fff8e1; }}
    #loading {{ isolation: isolate; box-sizing: border-box; overflow: auto; place-content: end center; gap: 12px; padding-bottom: max(36px, env(safe-area-inset-bottom)); background: #3b2414; }}
    #loading::before {{ content: ""; position: fixed; inset: 0; z-index: -2; background: #4ab3ec url("data:image/webp;base64,{b64(art)}") center top / cover no-repeat; pointer-events: none; }}
    #loading::after {{ content: ""; position: fixed; inset: 0; z-index: -1; background: linear-gradient(0deg, #3b2414 0%, #3b2414e6 14%, #3b241499 28%, transparent 48%); pointer-events: none; }}
    #loading > * {{ max-width: min(560px, 100%); justify-self: center; }}
    #loading h1 {{ font-weight: 800; font-size: clamp(20px, 3vw, 30px); line-height: 1.15; color: #fff4c2; text-shadow: 0 2px 0 #b3261e, 0 3px 12px #3b2414; }}
    #loading-status {{ font-weight: 600; text-shadow: 0 1px 6px #3b2414; }}
    #loading progress {{ display: block; width: min(320px, 75vw); height: 8px; border: 0; border-radius: 20px; overflow: hidden; accent-color: #ffd54a; background: #ffffff33; }}
    #loading progress::-webkit-progress-bar {{ background: #ffffff33; border-radius: 20px; }}
    #loading progress::-webkit-progress-value {{ background: #ffd54a; border-radius: 20px; }}
    #loading progress::-moz-progress-bar {{ background: #ffd54a; border-radius: 20px; }}
    #loading button {{ min-height: 44px; border: 2px solid #ffd54a; border-radius: 12px; background: #d85537; color: #fff8e1; font-weight: 700; }}
    #loading button:focus-visible {{ outline: 3px solid #ffd54a; outline-offset: 4px; }}
    #loading [hidden] {{ display: none; }}
    @media (prefers-reduced-motion: reduce) {{ #loading * {{ transition: none !important; animation: none !important; }} }}
    @media (max-aspect-ratio: 1/1) {{ #loading::before {{ background-size: 100% auto; }} #loading::after {{ background: linear-gradient(180deg, transparent 30%, #3b2414 100%) center top / 100% calc(100vw * 9 / 16) no-repeat; }} #loading {{ place-content: center; padding-top: calc(100vw * 9 / 16); padding-bottom: max(24px, env(safe-area-inset-bottom)); }} }}
    @media (max-height: 480px) and (min-aspect-ratio: 1/1) {{ #loading {{ gap: 8px; padding-bottom: 14px; }} #loading h1 {{ font-size: clamp(18px, 3vw, 24px); }} }}
  </style>"""
s = re.sub(r'  <style id="loading-art">.*?</style>', lambda _m: art_css, s, count=1, flags=re.S)

s = s.replace('<p id="loading-status">Loading…</p>', '<p id="loading-status">読みこみ中…</p>')
s = s.replace('aria-label="Download progress"', 'aria-label="ダウンロードの進みぐあい"')
s = s.replace('type="button" hidden>Retry</button>', 'type="button" hidden>もう一度</button>')
s = s.replace('<noscript>JavaScript is required to play this game.</noscript>', '<noscript>このゲームを遊ぶにはJavaScriptが必要です。</noscript>')

old_locale = re.search(r"      // A language chosen in game wins;.*?progress\.setAttribute\('aria-label'[^\n]*\n", s, flags=re.S)
assert old_locale, "locale block not found"
s = s.replace(old_locale.group(0), """      // The game is Japanese-only.
      document.documentElement.lang = 'ja';
      status.textContent = '読みこみ中…';
      retry.textContent = 'もう一度';
      progress.setAttribute('aria-label', 'ダウンロードの進みぐあい');
""")
replacements = {
    "(zh ? '暂未看到新的加载进度。可以继续等待，或重试。' : 'No recent loading progress. You can keep waiting or retry.')": "'しばらく進みがありません。このまま待つか、もう一度お試しください。'",
    "(zh ? '仍在加载。可以继续等待，或重试。' : 'Still loading. You can keep waiting or retry.')": "'まだ読みこみ中です。このまま待つか、もう一度お試しください。'",
    "status.textContent = zh ? '游戏加载失败，请重试。' : 'Unable to load the game. Please retry.';": "status.textContent = 'ゲームを読みこめませんでした。もう一度お試しください。';",
    "status.textContent = zh ? '正在加载…' : 'Loading…';": "status.textContent = '読みこみ中…';",
    "(zh ? '正在启动游戏…' : 'Starting game…')": "'ゲームを起動中…'",
}
for old, new in replacements.items():
    assert old in s, old
    s = s.replace(old, new)
assert "zh" not in re.sub(r"base64,[A-Za-z0-9+/=]+", "", s).replace("zh-", ""), "leftover zh branch"
open(PATH, "w", encoding="utf-8").write(s)
print("loader bytes", len(s.encode("utf-8")))
