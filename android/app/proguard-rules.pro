# Keep the accessibility service and lock activity
-keep class com.example.zenlock.watcher.** { *; }

# If you use a bridge accessed from Kotlin/Java (you do)
-keep class com.example.zenlock.RulesBridge { *; }
