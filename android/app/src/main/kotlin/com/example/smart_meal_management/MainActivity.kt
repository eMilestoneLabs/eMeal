package com.example.smart_meal_management

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Live-Test-16 ISSUE-13: on-device PDF compression for notice
        // attachments (the server is never asked to compress).
        PdfCompressorChannel.register(flutterEngine, applicationContext)
    }
}
