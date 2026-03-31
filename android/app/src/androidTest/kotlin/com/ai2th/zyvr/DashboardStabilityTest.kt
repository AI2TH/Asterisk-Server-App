package com.ai2th.zyvr

import androidx.test.espresso.Espresso.onView
import androidx.test.espresso.action.ViewActions.click
import androidx.test.espresso.matcher.ViewMatchers.withText
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.rule.ActivityTestRule
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Stability test: Click "Start" button, idle on Dashboard for 20+ minutes
 *
 * Run with:
 *   adb shell am instrument -w \
 *     -e class com.ai2th.zyvr.DashboardStabilityTest \
 *     com.ai2th.zyvr.test/androidx.test.runner.AndroidJUnitRunner
 *
 * Or via Firebase Test Lab:
 *   gcloud firebase test android run \
 *     --app=build/zyvr-release.apk \
 *     --test-apk=build/zyvr-test.apk \
 *     --test-runner-class androidx.test.runner.AndroidJUnitRunner \
 *     --device model=Pixel2.arm,version=31
 */
@RunWith(AndroidJUnit4::class)
class DashboardStabilityTest {

    @get:Rule
    val activityRule = ActivityTestRule(MainActivity::class.java)

    @Test
    fun testDashboardStability() {
        // Wait for app to stabilize
        Thread.sleep(2000)

        // Tap "Start" button
        onView(withText("Start")).perform(click())

        // Wait for VM to start (2-5 minutes)
        println("VM starting... waiting 5 minutes")
        Thread.sleep(300000)  // 5 minutes

        // Idle on Dashboard for 20 minutes
        println("Idling on Dashboard for 20 minutes...")
        Thread.sleep(1200000)  // 20 minutes

        // If we reach here, test passed (no crashes, no ANR)
        println("Test complete!")
    }
}
