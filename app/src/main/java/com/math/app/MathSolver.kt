package com.math.app

import java.math.BigInteger

object MathSolver {

    // يدعم + - × ÷ مع أعداد صحيحة بأي طول (BigInteger)
    fun solveEquation(raw: String): String {
        try {
            // 1) توحيد الرموز وإزالة المسافات
            val s = raw
                .replace("\\s+".toRegex(), "")
                .replace('x', '×')
                .replace('X', '×')
                .replace('*', '×')
                .replace('/', '÷')

            if (s.isEmpty()) return ""

            // 2) تحويل السلسلة لتوكنز: [رقم, رمز, رقم, ...]
            val tokens = mutableListOf<String>()
            val num = StringBuilder()
            fun flushNum() {
                if (num.isNotEmpty()) {
                    tokens += num.toString()
                    num.setLength(0)
                }
            }
            for (ch in s) {
                if (ch.isDigit()) {
                    num.append(ch)
                } else if (ch == '+' || ch == '-' || ch == '×' || ch == '÷') {
                    flushNum()
                    tokens += ch.toString()
                } else {
                    // تجاهل أي رموز غير معروفة بدل ما نكسر
                    // (لو عايز تشدد، ارجع "ERR")
                }
            }
            flushNum()
            if (tokens.isEmpty()) return ""

            // إزالة أي رموز زائدة في البداية/النهاية
            while (tokens.isNotEmpty() && tokens.first() in listOf("+","-","×","÷")) tokens.removeAt(0)
            while (tokens.isNotEmpty() && tokens.last()  in listOf("+","-","×","÷")) tokens.removeAt(tokens.lastIndex)
            if (tokens.isEmpty()) return ""

            // 3) مرحلة ضرب/قسمة أولاً (أولوية)
            val md = mutableListOf<String>()
            var i = 0
            while (i < tokens.size) {
                val t = tokens[i]
                if (t == "×" || t == "÷") {
                    // لازم يكون فيه رقم قبل وبعد
                    if (md.isEmpty()) return "ERR"
                    val left = md.removeAt(md.lastIndex).toBigIntegerOrZero()
                    if (i + 1 >= tokens.size) return "ERR"
                    val right = tokens[i + 1].toBigIntegerOrZero()

                    val res = if (t == "×") {
                        left * right
                    } else {
                        if (right == BigInteger.ZERO) return "ERR_DIV0"
                        left / right // قسمة صحيحة
                    }
                    md += res.toString()
                    i += 2
                } else {
                    md += t
                    i += 1
                }
            }

            // 4) مرحلة جمع/طرح من اليسار لليمين
            if (md.isEmpty()) return ""
            var acc = md[0].toBigIntegerOrZero()
            var j = 1
            while (j < md.size) {
                val op = md[j]
                val rhs = md.getOrNull(j + 1)?.toBigIntegerOrZero() ?: return "ERR"
                when (op) {
                    "+" -> acc = acc + rhs
                    "-" -> acc = acc - rhs
                    else -> return "ERR"
                }
                j += 2
            }
            return acc.toString()
        } catch (_: Exception) {
            return "ERR"
        }
    }

    private fun String.toBigIntegerOrZero(): BigInteger {
        // يمنع NumberFormatException مهما كان طول الرقم
        return if (this.all { it.isDigit() }) {
            if (this.isEmpty()) BigInteger.ZERO else BigInteger(this)
        } else BigInteger.ZERO
    }


    // --- shim: normalizeDigits ---
    // تُحوّل الأرقام العربية/الفارسية إلى ASCII 0-9
    // وتوحّد الرموز: x * -> ×  ،  / -> ÷ ، وتزيل أي محارف أخرى.
    fun normalizeDigits(raw: String): String {
        if (raw.isEmpty()) return ""
        val out = StringBuilder()
        for (ch in raw) {
            when (ch) {
                // ASCII digits
                in '0'..'9' -> out.append(ch)

                // Arabic-Indic digits ٠..٩ (U+0660..U+0669)
                '٠' -> out.append('0'); '١' -> out.append('1'); '٢' -> out.append('2'); '٣' -> out.append('3'); '٤' -> out.append('4')
                '٥' -> out.append('5'); '٦' -> out.append('6'); '٧' -> out.append('7'); '٨' -> out.append('8'); '٩' -> out.append('9')

                // Extended Arabic-Indic (Persian) ۰..۹ (U+06F0..U+06F9)
                '۰' -> out.append('0'); '۱' -> out.append('1'); '۲' -> out.append('2'); '۳' -> out.append('3'); '۴' -> out.append('4')
                '۵' -> out.append('5'); '۶' -> out.append('6'); '۷' -> out.append('7'); '۸' -> out.append('8'); '۹' -> out.append('9')

                // Operators (normalize all to one set)
                '+', '-' -> out.append(ch)
                'x', 'X', '*', '×' -> out.append('×')
                '/', '÷' -> out.append('÷')

                // ignore everything else (spaces, punctuation, noise)
                else -> { /* skip */ }
            }
        }
        return out.toString()
    }

}
