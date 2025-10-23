package com.math.app

object MathSolver {

    private val arabicDigits = mapOf(
        '٠' to '0','١' to '1','٢' to '2','٣' to '3','٤' to '4',
        '٥' to '5','٦' to '6','٧' to '7','٨' to '8','٩' to '9'
    )
    fun normalizeDigits(s: String): String =
        s.map { arabicDigits[it] ?: it }.joinToString("")

    fun solveEquation(raw: String): Int? {
        val s = ImageUtils.normalizeDigitLike(
            normalizeDigits(raw)
        )
            .replace("\\s+".toRegex(), "")
            .replace('×','*').replace('x','*').replace('·','*').replace('﹢','+').replace('＋','+')
            .replace('÷','/').replace('＝','=')

        // يسمح بأية مسافات ويقبل = اختياريًا
        val m = Regex("^(-?\\d+)\\s*([+\\-*/])\\s*(-?\\d+)\\s*=?$").find(s) ?: return null
        val a = m.groupValues[1].toLong()
        val op = m.groupValues[2][0]
        val b = m.groupValues[3].toLong()
        val r = when (op) {
            '+' -> a + b
            '-' -> a - b
            '*' -> a * b
            '/' -> if (b != 0L && a % b == 0L) a / b else return null
            else -> return null
        }
        return r.toInt()
    }
}
