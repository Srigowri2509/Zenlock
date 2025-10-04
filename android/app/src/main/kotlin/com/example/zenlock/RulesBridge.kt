package com.example.zenlock

import android.content.Context

object RulesBridge {
    // Returns true if current time is before the stored deadline for this package.
    @JvmStatic
    fun isLocked(ctx: Context, pkg: String): Boolean {
        val sp = ctx.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val untilStr = sp.getString("flutter.lock_$pkg", null) ?: return false
        val until = untilStr.toLongOrNull() ?: return false
        return System.currentTimeMillis() < until
    }

    // Remaining milliseconds (0 if not locked)
    @JvmStatic
    fun remainingMs(ctx: Context, pkg: String): Long {
        val sp = ctx.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val untilStr = sp.getString("flutter.lock_$pkg", null) ?: return 0L
        val until = untilStr.toLongOrNull() ?: return 0L
        val rem = until - System.currentTimeMillis()
        return if (rem > 0) rem else 0L
    }
}
