package com.example.smart_meal_management

import android.content.Context
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.cos.COSBase
import com.tom_roush.pdfbox.cos.COSName
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.graphics.image.JPEGFactory
import com.tom_roush.pdfbox.pdmodel.graphics.image.PDImageXObject
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.IdentityHashMap
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Live-Test-16 ISSUE-13 — on-device PDF compression (PdfBox-Android,
 * Apache-2.0). App-side only: the server is never asked to compress.
 *
 * Quality-first ladder, stopping at the FIRST result that fits [maxBytes]:
 *   1. lossless re-save (no pixel touched);
 *   2. embedded photos re-encoded as JPEG, stepping (max edge, quality)
 *      down gently — text and vector graphics are NEVER rasterised.
 * Images with transparency (SMask/Mask) or 1-bit stencils are left as-is so
 * they can never turn black. Large images are decoded SUBSAMPLED to stay
 * memory-safe. Runs on a single background thread; the UI never blocks.
 *
 * Channel "emeal/pdf_compress", method "compress"
 *   args: { bytes: ByteArray, maxBytes: Int }
 *   → ByteArray (fits) | null (cannot fit without unacceptable quality)
 *   → error "PDF_UNREADABLE" (encrypted / corrupt input)
 */
object PdfCompressorChannel {
    private const val CHANNEL = "emeal/pdf_compress"
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var initialized = false

    /** (max image edge px, JPEG quality) — highest quality first. */
    private val LADDER = listOf(
        1600 to 0.85f,
        1400 to 0.78f,
        1200 to 0.70f,
        1024 to 0.62f,
        900 to 0.55f,
        768 to 0.48f,
        640 to 0.40f,
    )

    fun register(engine: FlutterEngine, context: Context) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "compress") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val bytes = call.argument<ByteArray>("bytes")
                val maxBytes = call.argument<Int>("maxBytes")
                if (bytes == null || maxBytes == null || maxBytes <= 0) {
                    result.error("BAD_ARGS", "bytes and maxBytes are required", null)
                    return@setMethodCallHandler
                }
                val appContext = context.applicationContext
                worker.execute {
                    try {
                        if (!initialized) {
                            PDFBoxResourceLoader.init(appContext)
                            initialized = true
                        }
                        val out = compress(bytes, maxBytes)
                        main.post { result.success(out) }
                    } catch (t: Throwable) {
                        // Encrypted (no crypto provider bundled) or corrupt.
                        main.post {
                            result.error("PDF_UNREADABLE", t.message ?: t.javaClass.simpleName, null)
                        }
                    }
                }
            }
    }

    private fun compress(input: ByteArray, maxBytes: Int): ByteArray? {
        if (input.size <= maxBytes) return input
        // 1) Lossless re-save.
        PDDocument.load(input).use { doc ->
            val out = save(doc)
            if (out.size <= maxBytes) return out
        }
        // 2) Gentle image re-encoding ladder, best quality first.
        for ((maxEdge, quality) in LADDER) {
            PDDocument.load(input).use { doc ->
                recompressImages(doc, maxEdge, quality)
                val out = save(doc)
                if (out.size <= maxBytes) return out
            }
        }
        return null
    }

    private fun recompressImages(doc: PDDocument, maxEdge: Int, quality: Float) {
        // An image shared by several pages (logo, letterhead) is re-encoded
        // ONCE and the same replacement reused — never duplicated per page.
        // null = already tried, keep the original.
        val done = IdentityHashMap<COSBase, PDImageXObject?>()
        for (page in doc.pages) {
            val resources = page.resources ?: continue
            for (name in resources.xObjectNames.toList()) {
                val xo = try {
                    resources.getXObject(name)
                } catch (_: Throwable) {
                    null
                } as? PDImageXObject ?: continue
                if (xo.isStencil ||
                    xo.cosObject.containsKey(COSName.SMASK) ||
                    xo.cosObject.containsKey(COSName.MASK)
                ) continue
                val w = xo.width
                val h = xo.height
                if (w <= 0 || h <= 0) continue
                val original: COSBase = xo.cosObject
                if (done.containsKey(original)) {
                    done[original]?.let { resources.put(name, it) }
                    continue
                }
                done[original] = null
                val originalLength = xo.cosObject.length
                try {
                    // Subsampled decode: never inflate a huge scan into RAM.
                    val subsampling = max(1, max(w, h) / (maxEdge * 2))
                    val decoded: Bitmap = xo.getImage(null, subsampling) ?: continue
                    val scaled = scaleToFit(decoded, maxEdge)
                    val jpeg = JPEGFactory.createFromImage(doc, scaled, quality)
                    if (scaled !== decoded) scaled.recycle()
                    decoded.recycle()
                    // Only ever swap in something SMALLER than the original.
                    if (jpeg.cosObject.length < originalLength) {
                        resources.put(name, jpeg)
                        done[original] = jpeg
                        // Pages sharing ONE resources dict read the new JPEG
                        // back — never re-encode it a second time.
                        done[jpeg.cosObject] = jpeg
                    }
                } catch (_: OutOfMemoryError) {
                    // Leave this image untouched; the ladder continues.
                } catch (_: Throwable) {
                    // Unsupported encoding (e.g. JPEG 2000 — decoder not
                    // bundled, may surface as a LinkageError): leave this ONE
                    // image untouched; never fail the whole document.
                }
            }
        }
    }

    private fun scaleToFit(src: Bitmap, maxEdge: Int): Bitmap {
        val longest = max(src.width, src.height)
        if (longest <= maxEdge) return src
        val ratio = maxEdge.toFloat() / longest
        return Bitmap.createScaledBitmap(
            src,
            (src.width * ratio).roundToInt().coerceAtLeast(1),
            (src.height * ratio).roundToInt().coerceAtLeast(1),
            true,
        )
    }

    private fun save(doc: PDDocument): ByteArray {
        val bos = ByteArrayOutputStream()
        doc.save(bos)
        return bos.toByteArray()
    }
}
