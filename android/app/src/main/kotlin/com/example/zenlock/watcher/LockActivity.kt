package com.example.zenlock.watcher

import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import android.os.CountDownTimer
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import com.example.zenlock.RulesBridge

class LockActivity : Activity() {

    private var timer: CountDownTimer? = null

    private fun fmt(ms: Long): String {
        var s = (ms / 1000).toInt()
        val h = s / 3600
        s %= 3600
        val m = s / 60
        s %= 60
        fun two(n: Int) = n.toString().padStart(2, '0')
        return if (h > 0) "$h:${two(m)}:${two(s)}" else "${two(m)}:${two(s)}"
    }

    private fun finishSafely() {
        try { finish() } catch (_: Throwable) {}
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Light, overlay-like
        window.addFlags(
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
            WindowManager.LayoutParams.FLAG_LAYOUT_INSET_DECOR
        )
        window.statusBarColor = Color.TRANSPARENT

        val pkg = intent.getStringExtra("package") ?: ""
        val remaining = RulesBridge.remainingMs(this, pkg)
        if (remaining <= 0L) {
            finishSafely()
            return
        }

        // Scrim
        val root = LinearLayout(this).apply {
            setBackgroundColor(Color.parseColor("#66000000"))
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.MATCH_PARENT
            )
            isClickable = true
            setOnClickListener { finishSafely() } // tap to dismiss
        }

        // Card
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(56, 44, 56, 44)
            setBackgroundColor(Color.WHITE)
            elevation = 18f
        }

        val title = TextView(this).apply {
            text = "ZenLock"
            textSize = 20f
            setTextColor(Color.parseColor("#2C3141"))
        }

        val msg = TextView(this).apply {
            val human = fmt(remaining)
            text = "This app is locked.\nYou can open it after: $human"
            textSize = 16f
            setTextColor(Color.parseColor("#2C3141"))
            setPadding(0, 14, 0, 0)
        }

        val tip = TextView(this).apply {
            text = "Stay focused ✨"
            textSize = 14f
            setTextColor(Color.parseColor("#A6B6CF"))
            setPadding(0, 12, 0, 0)
        }

        card.addView(title)
        card.addView(msg)
        card.addView(tip)
        root.addView(card)
        setContentView(root)

        // Auto-dismiss quickly so user can continue using ZenLock
        timer = object : CountDownTimer(1200, 1200) {
            override fun onTick(millisUntilFinished: Long) {}
            override fun onFinish() { finishSafely() }
        }.start()
    }

    override fun onBackPressed() {
        // never bounce into ZenLock; just close the popup
        finishSafely()
    }

    override fun onPause() {
        super.onPause()
        // If user navigates away (e.g., into ZenLock), ensure popup disappears
        finishSafely()
    }

    override fun onStop() {
        super.onStop()
        timer?.cancel()
        finishSafely()
    }

    override fun onResume() {
        super.onResume()
        // If lock expired while we were shown, close immediately
        val pkg = intent.getStringExtra("package") ?: ""
        if (!RulesBridge.isLocked(this, pkg)) {
            finishSafely()
        }
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_LAYOUT_STABLE
    }
}
