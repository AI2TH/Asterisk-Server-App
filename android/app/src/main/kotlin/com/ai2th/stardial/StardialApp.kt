package com.ai2th.stardial

import android.app.Application

class StardialApp : Application() {
    lateinit var vmManager: VmManager
        private set

    override fun onCreate() {
        super.onCreate()
        vmManager = VmManager(this)
    }
}
