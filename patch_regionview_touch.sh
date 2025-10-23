set -euo pipefail

F="app/src/main/java/com/math/app/OverlayRegions.kt"
if [ ! -f "$F" ]; then
  echo "[!] File not found: $F"
  exit 1
fi

python3 - "$F" <<'PY'
import sys, re
from pathlib import Path

fp = Path(sys.argv[1])
src = fp.read_text(encoding="utf-8")

start_pat = r"\bprivate\s+class\s+RegionView\s*\("
m = re.search(start_pat, src)
if not m:
    print("[!] Could not find 'private class RegionView(' in OverlayRegions.kt")
    sys.exit(2)

i = m.end()
while i < len(src) and src[i] != '{':
    i += 1
if i >= len(src) or src[i] != '{':
    print("[!] Could not locate RegionView class body opening brace")
    sys.exit(3)

start_body = i
depth = 0
j = i
while j < len(src):
    if src[j] == '{':
        depth += 1
    elif src[j] == '}':
        depth -= 1
        if depth == 0:
            end_body = j + 1
            break
    j += 1
else:
    print("[!] Could not locate RegionView class body closing brace")
    sys.exit(4)

replacement = r'''
    private class RegionView(
        ctx: Context,
        private val index: Int,
        val rect: RectF,
        private val maxW: Int,
        private val maxH: Int
    ) : View(ctx) {
        private val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = if (index == 0) 0x66FFFFFF.toInt() else 0x66FFFF00.toInt()
            style = Paint.Style.STROKE
            strokeWidth = 5f
        }
        private val fill = Paint().apply { color = 0x2200AAFF.toInt() }
        private val textP = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE; textSize = 36f; typeface = Typeface.MONOSPACE
        }
        private val handle = Paint().apply { color = Color.WHITE }

        private var mode = 0 // 0: drag, 1: resize
        private var lastX = 0f; private var lastY = 0f
        private val hs = 36f // handle size

        override fun onDraw(c: Canvas) {
            c.drawRect(rect, fill)
            c.drawRect(rect, border)
            c.drawText(if (index == 0) "Q" else "A$index", rect.left + 8, rect.top + 40, textP)
            // corner handle
            c.drawRect(rect.right - hs, rect.bottom - hs, rect.right, rect.bottom, handle)
        }

        override fun onTouchEvent(e: MotionEvent): Boolean {
            val x = e.rawX; val y = e.rawY

            // Only handle touches that start near/inside this rectangle (with small margin for the resize handle)
            if (e.action == MotionEvent.ACTION_DOWN &&
                !RectF(rect.left - hs, rect.top - hs, rect.right + hs, rect.bottom + hs).contains(x, y)
            ) {
                return false
            }

            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    lastX = x; lastY = y
                    mode = if (x > rect.right - hs && y > rect.bottom - hs) 1 else 0
                    return true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = x - lastX; val dy = y - lastY
                    lastX = x; lastY = y
                    if (mode == 0) {
                        rect.offset(dx, dy)
                    } else {
                        rect.right += dx; rect.bottom += dy
                    }
                    clamp()
                    invalidate()
                    return true
                }
            }
            return super.onTouchEvent(e)
        }

        private fun clamp() {
            if (rect.left < 0) rect.offset(-rect.left, 0f)
            if (rect.top < 0) rect.offset(0f, -rect.top)
            if (rect.right > maxW) rect.right = maxW.toFloat()
            if (rect.bottom > maxH) rect.bottom = maxH.toFloat()
            if (rect.width() < 80f) rect.right = rect.left + 80f
            if (rect.height() < 60f) rect.bottom = rect.top + 60f
        }
    }
'''.strip('\n')

new_src = src[:m.start()] + replacement + src[end_body:]
fp.write_text(new_src, encoding="utf-8")
print("[+] RegionView patched: per-rectangle touch handling enabled.")
PY

echo "==> Building APK…"
./gradlew --no-daemon assembleDebug

echo "==> Done. APKs:"
ls -lh app/build/outputs/apk/debug/
