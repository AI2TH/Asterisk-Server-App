package com.ai2th.zyvr

import android.app.Application

class ZyvrApp : Application() {
    lateinit var vmManager: VmManager
        private set

    override fun onCreate() {
        super.onCreate()
        vmManager = VmManager(this)
    }
}
