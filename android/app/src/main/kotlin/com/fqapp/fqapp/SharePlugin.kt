package com.fqapp.fqapp

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * 系统分享桥（官方用 `Intent.ACTION_SEND` + `text/plain`，
 * 见 com.dragon.read.base.share2.utils.m0 的系统分享分支）。
 *
 * 两种载荷：
 * - `shareText`：标题+正文交给系统选择器；没有可分享的应用时返回 false，
 *   Dart 侧会降级为「复制链接」并提示，而不是假装分享成功。
 * - `shareFile`：手环安装包（rpk）这类二进制文件。先落到 cacheDir/rpk_share，
 *   再用 FileProvider 授权给接收方 —— 直接传 file:// 在 Android 7 以上会被
 *   系统拒绝（FileUriExposedException）。
 *
 * 落盘与取 URI 都放在单线程池里：rpk 有几 MB，写主线程会掉帧。
 */
class SharePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var context: Context? = null
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "fqapp/share")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "shareText" -> shareText(call, result)
            "shareFile" -> shareFile(call, result)
            else -> result.notImplemented()
        }
    }

    private fun shareText(call: MethodCall, result: MethodChannel.Result) {
        val ctx = context
        if (ctx == null) {
            result.success(false)
            return
        }
        val title = call.argument<String>("title").orEmpty()
        val text = call.argument<String>("text").orEmpty()
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_SUBJECT, title)
            putExtra(Intent.EXTRA_TEXT, text)
        }
        val chooser = Intent.createChooser(send, title).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            ctx.startActivity(chooser)
            result.success(true)
        } catch (error: Exception) {
            result.success(false)
        }
    }

    private fun shareFile(call: MethodCall, result: MethodChannel.Result) {
        val ctx = context
        val bytes = call.argument<ByteArray>("bytes")
        if (ctx == null || bytes == null || bytes.isEmpty()) {
            result.success(false)
            return
        }
        val fileName = sanitize(call.argument<String>("fileName").orEmpty())
        val mime = call.argument<String>("mime") ?: "application/octet-stream"
        val title = call.argument<String>("title") ?: fileName
        io.execute {
            val launched = try {
                // 只保留最近一次分享的文件：分享面板可能被反复打开，
                // 缓存目录不能无限长。
                val dir = File(ctx.cacheDir, "rpk_share").apply { mkdirs() }
                dir.listFiles()?.forEach { it.delete() }
                val file = File(dir, fileName)
                file.writeBytes(bytes)
                val uri = FileProvider.getUriForFile(
                    ctx,
                    "${ctx.packageName}.fileprovider",
                    file,
                )
                val send = Intent(Intent.ACTION_SEND).apply {
                    type = mime
                    putExtra(Intent.EXTRA_STREAM, uri)
                    putExtra(Intent.EXTRA_SUBJECT, title)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                val chooser = Intent.createChooser(send, title).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                ctx.startActivity(chooser)
                true
            } catch (error: Exception) {
                false
            }
            main.post { result.success(launched) }
        }
    }

    /** 只留安全字符：文件名来自远端 manifest，不能让它拼出 ../。 */
    private fun sanitize(name: String): String {
        val cleaned = name.replace(Regex("[^A-Za-z0-9._\\-\\u4e00-\\u9fa5]"), "_")
        return cleaned.ifBlank { "share.bin" }
    }
}
