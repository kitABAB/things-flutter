package com.clone.things3.things3_clone

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/// 「今日小组件 · 2×2 极简方块」。
///
/// 与 4×2 清单版共用同一份 SharedPreferences，但只读「不受标签筛选影响」的字段：
///   today_open（今日待办总数）、first_title（最紧要一条）。
/// 交互：
///   - 右上角 ＋ -> QuickCaptureActivity（落入收件箱）
///   - 其余区域 -> 打开 App things://today
class TodayCompactWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.today_compact_widget)

            val open = widgetData.getString("today_open", "0")?.toIntOrNull() ?: 0
            val first = widgetData.getString("first_title", "") ?: ""

            views.setTextViewText(R.id.c_big, "$open")
            if (open == 0) {
                views.setTextViewText(R.id.c_cap, "今天清零")
                views.setViewVisibility(R.id.c_next, View.GONE)
            } else {
                views.setTextViewText(R.id.c_cap, "件事待办")
                views.setViewVisibility(R.id.c_next, View.VISIBLE)
                views.setTextViewText(R.id.c_next_title, first)
            }

            // 右上角 ＋ -> 轻量输入浮层
            var flags = PendingIntent.FLAG_UPDATE_CURRENT
            if (Build.VERSION.SDK_INT >= 23) {
                flags = flags or PendingIntent.FLAG_IMMUTABLE
            }
            views.setOnClickPendingIntent(
                R.id.c_fab,
                PendingIntent.getActivity(
                    context,
                    1, // 与 4×2 添加栏区分 requestCode，避免 PendingIntent 复用串台
                    Intent(context, QuickCaptureActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    flags
                )
            )

            // 整块 -> 打开 App
            views.setOnClickPendingIntent(
                R.id.c_root,
                HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("things://today")
                )
            )

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
