package com.example.zenlock.watcher

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import com.example.zenlock.RulesBridge

class AppWatchAccessibilityService : AccessibilityService() {

    private val mainHandler = Handler(Looper.getMainLooper())
    private val selfPkg = "com.example.zenlock"

    // throttle popup so it doesn't re-appear when returning to ZenLock
    private var lastPkgShown: String? = null
    private var lastShownAt = 0L
    private val popupCooldownMs = 900L

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return

        val pkg = event.packageName?.toString() ?: return
        if (pkg == selfPkg) return // never trigger on our own screens

        // If app not locked, do nothing
        if (!RulesBridge.isLocked(this, pkg)) return

        val now = System.currentTimeMillis()
        // Prevent rapid re-launch (e.g., bouncing through HOME/recents)
        if (lastPkgShown == pkg && (now - lastShownAt) < popupCooldownMs) return

        // Leave the blocked app
        performGlobalAction(GLOBAL_ACTION_HOME)

        // Show tiny popup once, then let user continue (e.g., open ZenLock)
        mainHandler.postDelayed({
            val i = Intent(this, LockActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_NO_ANIMATION or
                    Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS
                )
                putExtra("package", pkg)
            }
            startActivity(i)
            lastPkgShown = pkg
            lastShownAt = System.currentTimeMillis()
        }, 120L)
    }

    override fun onInterrupt() {}
}
