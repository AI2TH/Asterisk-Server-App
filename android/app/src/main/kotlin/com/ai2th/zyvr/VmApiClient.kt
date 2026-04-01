package com.ai2th.zyvr

import android.util.Log
import com.google.gson.Gson
import com.google.gson.JsonObject
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit

class VmApiClient(private val token: String) {
    private val TAG = "VmApiClient"
    private val baseUrl = "http://127.0.0.1:7082"
    private val gson = Gson()

    private val client = OkHttpClient.Builder()
        .connectTimeout(5, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .build()

    private val healthClient = OkHttpClient.Builder()
        .connectTimeout(5, TimeUnit.SECONDS)
        .readTimeout(5, TimeUnit.SECONDS)
        .build()

    private fun Request.Builder.withAuth(): Request.Builder =
        header("Authorization", "Bearer $token")

    // -------------------------------------------------------------------------
    // Health
    // -------------------------------------------------------------------------

    fun checkHealth(): Boolean {
        return try {
            val req = Request.Builder().url("$baseUrl/health").withAuth().get().build()
            val resp = healthClient.newCall(req).execute()
            val ok = resp.isSuccessful
            resp.close()
            ok
        } catch (e: Exception) {
            Log.e(TAG, "Health check failed: ${e.message}")
            false
        }
    }

    // -------------------------------------------------------------------------
    // Generic HTTP methods (used by MainActivity MethodChannel handlers)
    // -------------------------------------------------------------------------

    fun get(path: String): String {
        val req = Request.Builder()
            .url("$baseUrl$path")
            .withAuth()
            .get()
            .build()
        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) throw Exception("GET $path failed: ${resp.code}")
            return resp.body?.string() ?: ""
        }
    }

    fun post(path: String, json: String): String {
        val body = json.toRequestBody("application/json; charset=utf-8".toMediaType())
        val req = Request.Builder()
            .url("$baseUrl$path")
            .withAuth()
            .post(body)
            .build()
        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) {
                val err = resp.body?.string() ?: resp.code.toString()
                throw Exception("POST $path failed: $err")
            }
            return resp.body?.string() ?: ""
        }
    }

    fun delete(path: String): String {
        val req = Request.Builder()
            .url("$baseUrl$path")
            .withAuth()
            .delete()
            .build()
        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) throw Exception("DELETE $path failed: ${resp.code}")
            return resp.body?.string() ?: ""
        }
    }

    // -------------------------------------------------------------------------
    // Specific API calls
    // -------------------------------------------------------------------------

    fun vmExec(cmd: String): Map<String, Any> {
        val json = JsonObject().apply { addProperty("cmd", cmd) }
        val respStr = post("/vm/exec", gson.toJson(json))
        @Suppress("UNCHECKED_CAST")
        return gson.fromJson(respStr, Map::class.java) as Map<String, Any>
    }

    fun getLogs(tail: Int = 200): String {
        return try {
            get("/logs?tail=$tail")
        } catch (e: Exception) {
            Log.e(TAG, "getLogs failed: ${e.message}")
            ""
        }
    }
}
