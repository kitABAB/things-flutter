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
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/// 「今日小组件」主屏 AppWidget（4×2 紧凑版）。
///
/// 数据由 Flutter 侧 TodayWidgetService 写入 SharedPreferences：
///   rows_shown / more / done / total，row{i}_*，
///   expanded / active_tag / active_tag_title，chip_count / chip{i}_id / chip{i}_title
/// 交互（均为后台广播，不打开 App）：
///   - 复选框 -> todaywidget://complete?id=xxx
///   - 漏斗   -> todaywidget://togglefilter（展开/收起标签行）
///   - 标签   -> todaywidget://filter?tag=xxx（单选；「全部」/✕ 传空清除）
///   - 添加栏 -> 拉起半透明 QuickCaptureActivity 浮层（落入收件箱）
///   - 标题/头部 -> 启动 App things://today
class TodayWidgetProvider : HomeWidgetProvider() {

    private val maxRows = 3
    private val maxChips = 4

    private val blue = 0xFF2D7DF6.toInt()
    private val grey = 0xFF8E8E93.toInt()
    private val chipText = 0xFF3A3A3C.toInt()
    private val white = 0xFFFFFFFF.toInt()

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.today_widget)

            val shown = widgetData.getString("rows_shown", "0")?.toIntOrNull() ?: 0
            val more = widgetData.getString("more", "0")?.toIntOrNull() ?: 0
            val done = widgetData.getString("done", "0")?.toIntOrNull() ?: 0
            val total = widgetData.getString("total", "0")?.toIntOrNull() ?: 0
            val expanded = widgetData.getString("expanded", "0") == "1"
            val activeTag = widgetData.getString("active_tag", "") ?: ""
            val activeTitle = widgetData.getString("active_tag_title", "") ?: ""
            val filtering = activeTag.isNotEmpty()

            // ---- 头部右侧：进度环 vs 已筛标签 ----
            if (filtering) {
                views.setViewVisibility(R.id.w_progress, View.GONE)
                views.setViewVisibility(R.id.w_activetag, View.VISIBLE)
                views.setTextViewText(R.id.w_activetag_title, "#$activeTitle")
                views.setOnClickPendingIntent(R.id.w_activetag, filterIntent(context, ""))
            } else {
                views.setViewVisibility(R.id.w_activetag, View.GONE)
                views.setViewVisibility(R.id.w_progress, View.VISIBLE)
                views.setProgressBar(
                    R.id.w_ring,
                    if (total <= 0) 1 else total,
                    done,
                    false
                )
                views.setTextViewText(R.id.w_count, "$done/$total")
            }

            // ---- 漏斗：高亮 + 切换标签行 ----
            views.setInt(
                R.id.w_funnel, "setColorFilter",
                if (expanded || filtering) blue else grey
            )
            views.setOnClickPendingIntent(
                R.id.w_funnel,
                HomeWidgetBackgroundIntent.getBroadcast(
                    context, Uri.parse("todaywidget://togglefilter")
                )
            )

            // ---- 标签行 ----
            val chipCount = widgetData.getString("chip_count", "0")?.toIntOrNull() ?: 0
            val hasChips = chipCount > 0
            views.setViewVisibility(
                R.id.w_tagrow,
                if (expanded && hasChips) View.VISIBLE else View.GONE
            )
            // 「全部」chip：未筛选时选中
            styleChip(context, views, R.id.w_chip_all, selected = !filtering)
            views.setOnClickPendingIntent(R.id.w_chip_all, filterIntent(context, ""))

            for (i in 0 until maxChips) {
                val chipId = res(context, "w_chip_$i")
                if (i < chipCount) {
                    val id = widgetData.getString("chip${i}_id", "") ?: ""
                    val title = widgetData.getString("chip${i}_title", "") ?: ""
                    views.setViewVisibility(chipId, View.VISIBLE)
                    views.setTextViewText(chipId, title)
                    styleChip(context, views, chipId, selected = id == activeTag)
                    views.setOnClickPendingIntent(chipId, filterIntent(context, id))
                } else {
                    views.setViewVisibility(chipId, View.GONE)
                }
            }

            // ---- 空态 / 任务行 ----
            views.setViewVisibility(R.id.w_empty, if (shown == 0) View.VISIBLE else View.GONE)
            views.setViewVisibility(R.id.w_rows, if (shown == 0) View.GONE else View.VISIBLE)
            views.setTextViewText(
                R.id.w_empty,
                if (filtering) "该标签下今天没有任务" else "今天清零，去享受生活"
            )

            for (i in 0 until maxRows) {
                val rowId = res(context, "row$i")
                val checkId = res(context, "row${i}_check")
                val titleId = res(context, "row${i}_title")
                val flagId = res(context, "row${i}_flag")

                if (i < shown) {
                    val id = widgetData.getString("row${i}_id", "") ?: ""
                    val title = widgetData.getString("row${i}_title", "") ?: ""
                    val flag = widgetData.getBoolean("row${i}_flag", false)
                    val evening = widgetData.getBoolean("row${i}_evening", false)

                    views.setViewVisibility(rowId, View.VISIBLE)
                    views.setTextViewText(titleId, title)
                    views.setTextColor(titleId, if (evening) 0xFF5B6CF0.toInt() else 0xFF1A1A1A.toInt())
                    views.setViewVisibility(flagId, if (flag) View.VISIBLE else View.GONE)

                    views.setOnClickPendingIntent(
                        checkId,
                        HomeWidgetBackgroundIntent.getBroadcast(
                            context, Uri.parse("todaywidget://complete?id=$id")
                        )
                    )
                    views.setOnClickPendingIntent(
                        titleId,
                        HomeWidgetLaunchIntent.getActivity(
                            context, MainActivity::class.java, Uri.parse("things://today")
                        )
                    )
                } else {
                    views.setViewVisibility(rowId, View.GONE)
                }
            }

            if (more > 0) {
                views.setViewVisibility(R.id.w_more, View.VISIBLE)
                views.setTextViewText(R.id.w_more, "还有 $more 项 →")
            } else {
                views.setViewVisibility(R.id.w_more, View.GONE)
            }

            // ---- 添加栏 -> 轻量输入浮层 ----
            var addFlags = PendingIntent.FLAG_UPDATE_CURRENT
            if (Build.VERSION.SDK_INT >= 23) {
                addFlags = addFlags or PendingIntent.FLAG_IMMUTABLE
            }
            val addIntent = PendingIntent.getActivity(
                context,
                0,
                Intent(context, QuickCaptureActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                addFlags
            )
            views.setOnClickPendingIntent(R.id.w_add, addIntent)

            // ---- 头部 -> 打开 App ----
            views.setOnClickPendingIntent(
                R.id.w_header,
                HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("things://today")
                )
            )

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    private fun filterIntent(context: Context, tagId: String): PendingIntent =
        HomeWidgetBackgroundIntent.getBroadcast(
            context, Uri.parse("todaywidget://filter?tag=$tagId")
        )

    private fun styleChip(context: Context, views: RemoteViews, chipId: Int, selected: Boolean) {
        views.setInt(
            chipId, "setBackgroundResource",
            if (selected) R.drawable.chip_bg_sel else R.drawable.chip_bg
        )
        views.setTextColor(chipId, if (selected) white else chipText)
        // setBackgroundResource 会清空内边距，需重新设置（单位：px）。
        val h = dp(context, 11)
        val v = dp(context, 4)
        views.setViewPadding(chipId, h, v, h, v)
    }

    private fun dp(context: Context, value: Int): Int =
        (value * context.resources.displayMetrics.density).toInt()

    private fun res(context: Context, name: String): Int =
        context.resources.getIdentifier(name, "id", context.packageName)
}
