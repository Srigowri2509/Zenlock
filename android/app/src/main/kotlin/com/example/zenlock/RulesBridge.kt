package com.example.zenlock

import android.content.Context
import android.content.SharedPreferences

object RulesBridge {
    private fun prefs(ctx: Context): SharedPreferences =
        ctx.getSharedPreferences("zenlock_prefs", Context.MODE_PRIVATE)

    fun isLocked(ctx: Context, pkg: String): Boolean {
        val until = prefs(ctx).getLong("lock_until_$pkg", 0L)
        return System.currentTimeMillis() < until
    }

    fun remainingMs(ctx: Context, pkg: String): Long {
        val until = prefs(ctx).getLong("lock_until_$pkg", 0L)
        return until - System.currentTimeMillis()
    }

    fun lockApp(ctx: Context, pkg: String, durationMs: Long) {
        prefs(ctx).edit().putLong("lock_until_$pkg", System.currentTimeMillis() + durationMs).apply()
    }

    fun unlockApp(ctx: Context, pkg: String) {
        prefs(ctx).edit().remove("lock_until_$pkg").apply()
    }
}
