package com.clone.things3.things3_clone

import android.app.Activity
import android.net.Uri
import android.os.Bundle
import android.view.Gravity
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.TextView
import android.widget.Toast
import es.antonborri.home_widget.HomeWidgetBackgroundIntent

/// 小组件「快速添加」的轻量输入浮层。
///
/// 它是一个**半透明 Activity**（不是完整 App）：只显示一个输入框 + 键盘盖在桌面上，
/// 提交后通过 home_widget 后台广播把任务投递进**收件箱**（由 Dart 后台 isolate 写库），
/// 然后立即关闭。符合小组件「便捷添加、随后整理」的定位。
class QuickCaptureActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 浮层贴底显示，点外部可关闭。
        setFinishOnTouchOutside(true)
        window.setGravity(Gravity.BOTTOM)
        window.setLayout(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT
        )
        window.setSoftInputMode(
            WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE or
                WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
        )
        setContentView(R.layout.quick_capture)

        val input = findViewById<EditText>(R.id.qc_input)
        val send = findViewById<TextView>(R.id.qc_send)

        input.requestFocus()
        input.post {
            val imm = getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager
            imm.showSoftInput(input, InputMethodManager.SHOW_IMPLICIT)
        }

        send.setOnClickListener { submit(input) }
        input.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_DONE || actionId == EditorInfo.IME_ACTION_SEND) {
                submit(input)
                true
            } else {
                false
            }
        }
    }

    private fun submit(input: EditText) {
        val text = input.text?.toString()?.trim().orEmpty()
        if (text.isEmpty()) {
            finish()
            return
        }
        val pending = HomeWidgetBackgroundIntent.getBroadcast(
            this,
            Uri.parse("todaywidget://add?title=${Uri.encode(text)}")
        )
        pending.send()
        Toast.makeText(this, "已添加到收件箱", Toast.LENGTH_SHORT).show()
        finish()
    }
}
