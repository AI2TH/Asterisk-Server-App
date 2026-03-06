package com.ai2th.stardial

import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.NetworkInterface
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.ai2th.stardial/vm"
    private val vm get() = (applicationContext as StardialApp).vmManager
    private val executor = Executors.newSingleThreadExecutor()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "startVm" -> executor.execute {
                        try {
                            startVmService()
                            vm.startVm()
                            runOnUiThread { result.success(null) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("VM_START_ERROR", e.message, null) }
                        }
                    }

                    "stopVm" -> executor.execute {
                        try {
                            vm.stopVm()
                            stopVmService()
                            runOnUiThread { result.success(null) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("VM_STOP_ERROR", e.message, null) }
                        }
                    }

                    "restartVm" -> executor.execute {
                        try {
                            vm.stopVm()
                            Thread.sleep(1000)
                            vm.startVm()
                            runOnUiThread { result.success(null) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("VM_RESTART_ERROR", e.message, null) }
                        }
                    }

                    "checkHealth" -> executor.execute {
                        try {
                            val healthy = vm.checkHealth()
                            runOnUiThread { result.success(healthy) }
                        } catch (e: Exception) {
                            runOnUiThread { result.success(false) }
                        }
                    }

                    "getVmStatus" -> {
                        try {
                            result.success(vm.getStatus())
                        } catch (e: Exception) {
                            result.success("unknown")
                        }
                    }

                    "getToken" -> result.success(vm.token)

                    "apiGet" -> executor.execute {
                        try {
                            val path = call.argument<String>("path") ?: ""
                            val resp = vm.apiGet(path)
                            runOnUiThread { result.success(resp) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("API_ERROR", e.message, null) }
                        }
                    }

                    "apiPost" -> executor.execute {
                        try {
                            val path = call.argument<String>("path") ?: ""
                            val body = call.argument<String>("body") ?: "{}"
                            val resp = vm.apiPost(path, body)
                            runOnUiThread { result.success(resp) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("API_ERROR", e.message, null) }
                        }
                    }

                    "apiDelete" -> executor.execute {
                        try {
                            val path = call.argument<String>("path") ?: ""
                            val resp = vm.apiDelete(path)
                            runOnUiThread { result.success(resp) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("API_ERROR", e.message, null) }
                        }
                    }

                    "vmExec" -> executor.execute {
                        try {
                            val cmd = call.argument<String>("cmd")
                                ?: return@execute runOnUiThread {
                                    result.error("VM_EXEC_ERROR", "cmd required", null)
                                }
                            val output = vm.vmExec(cmd)
                            runOnUiThread { result.success(output) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("VM_EXEC_ERROR", e.message, null) }
                        }
                    }

                    "getLogs" -> executor.execute {
                        try {
                            val tail = call.argument<Int>("tail") ?: 200
                            val logs = vm.getLogs(tail)
                            runOnUiThread { result.success(logs) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("LOGS_ERROR", e.message, null) }
                        }
                    }

                    "getWifiIp" -> {
                        result.success(getWifiIpAddress())
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        executor.shutdown()
        super.onDestroy()
    }

    private fun getWifiIpAddress(): String {
        try {
            val ifaces = NetworkInterface.getNetworkInterfaces()?.toList() ?: return ""
            for (iface in ifaces) {
                if (!iface.isUp || iface.isLoopback) continue
                for (addr in iface.inetAddresses.toList()) {
                    if (addr.isLoopbackAddress) continue
                    val ip = addr.hostAddress ?: continue
                    if (ip.contains(':')) continue  // skip IPv6
                    return ip
                }
            }
        } catch (_: Exception) {}
        return ""
    }

    private fun startVmService() {
        startForegroundService(Intent(this, VmService::class.java))
    }

    private fun stopVmService() {
        stopService(Intent(this, VmService::class.java))
    }
}
