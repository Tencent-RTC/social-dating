/*
 * Copyright (c) 2025 Tencent
 * All rights reserved.
 *
 * Author: eddardliu
 */

package io.trtc.tuikit.atomicx.albumpicker.util

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.ActivityResultRegistry
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.core.content.edit

internal enum class PermissionState {
    AUTHORIZED,
    LIMITED,
    DENIED,
    NOT_DETERMINED,
}

internal enum class PermissionType {
    MEDIA,
    STORAGE,
}

internal class AlbumPickerPermissionRequester(
    registry: ActivityResultRegistry,
    private val context: Context,
    private val onResult: () -> Unit,
) {
    private companion object {
        const val TAG = "AlbumPickerPermission"
        const val PREFS_NAME = "album_picker_permission_state"
        const val KEY_PERMISSION_REQUESTED = "permission_requested"
        const val KEY_MEDIA_PERMISSIONS = "album_picker_media_permissions"
        const val PERMISSION_READ_MEDIA_VISUAL_USER_SELECTED =
            "android.permission.READ_MEDIA_VISUAL_USER_SELECTED"
    }

    private val targetSdk = context.applicationInfo.targetSdkVersion

    private val launcher: ActivityResultLauncher<Array<String>> =
        registry.register(
            KEY_MEDIA_PERMISSIONS,
            ActivityResultContracts.RequestMultiplePermissions(),
        ) { _ ->
            onResult()
        }

    fun currentPermissionState(): PermissionState {
        val hasRequested =
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getBoolean(KEY_PERMISSION_REQUESTED, false)
        if (!hasRequested) {
            return PermissionState.NOT_DETERMINED
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val hasMediaImages = hasPermission(Manifest.permission.READ_MEDIA_IMAGES)
            val hasMediaVideo = hasPermission(Manifest.permission.READ_MEDIA_VIDEO)
            val hasFullAccess = if (targetSdk >= Build.VERSION_CODES.TIRAMISU) {
                hasMediaImages && hasMediaVideo
            } else {
                val hasStorage = hasPermission(Manifest.permission.READ_EXTERNAL_STORAGE)
                hasStorage || hasMediaImages || hasMediaVideo
            }
            if (hasFullAccess) return PermissionState.AUTHORIZED

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                val hasVisualSelected = hasPermission(PERMISSION_READ_MEDIA_VISUAL_USER_SELECTED)
                if (hasVisualSelected) return PermissionState.LIMITED
            }

            return PermissionState.DENIED
        }

        val hasStorage = hasPermission(Manifest.permission.READ_EXTERNAL_STORAGE)
        return if (hasStorage) PermissionState.AUTHORIZED else PermissionState.DENIED
    }

    fun currentPermissionType(): PermissionType {
        val usesMediaPermissions = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            targetSdk >= Build.VERSION_CODES.TIRAMISU
        return if (usesMediaPermissions) PermissionType.MEDIA else PermissionType.STORAGE
    }

    fun requestPermissions() {
        Log.d(TAG, "requestPermissions: deviceApi=${Build.VERSION.SDK_INT}, targetSdk=$targetSdk")
        markPermissionRequested()
        launcher.launch(getRequiredPermissions())
    }

    fun unregister() {
        launcher.unregister()
    }

    private fun markPermissionRequested() {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit { putBoolean(KEY_PERMISSION_REQUESTED, true) }
    }

    private fun getRequiredPermissions(): Array<String> {
        val permissions = when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE &&
                targetSdk >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> {
                arrayOf(
                    PERMISSION_READ_MEDIA_VISUAL_USER_SELECTED,
                    Manifest.permission.READ_MEDIA_IMAGES,
                    Manifest.permission.READ_MEDIA_VIDEO,
                )
            }

            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                targetSdk >= Build.VERSION_CODES.TIRAMISU -> {
                arrayOf(
                    Manifest.permission.READ_MEDIA_IMAGES,
                    Manifest.permission.READ_MEDIA_VIDEO,
                )
            }

            else -> {
                arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
            }
        }
        for (permission in permissions) {
            if (!isPermissionDeclaredInManifest(permission)) {
                Log.e(TAG, "$permission is not declared in manifest, "
                    + "possibly filtered by maxSdkVersion.")
            }
        }
        return permissions
    }

    private fun isPermissionDeclaredInManifest(permission: String): Boolean =
        try {
            val packageInfo = context.packageManager.getPackageInfo(
                context.packageName, PackageManager.GET_PERMISSIONS
            )
            packageInfo.requestedPermissions?.contains(permission) == true
        } catch (_: Throwable) {
            false
        }

    private fun hasPermission(permission: String): Boolean =
        try {
            ContextCompat.checkSelfPermission(context, permission) ==
                PackageManager.PERMISSION_GRANTED
        } catch (t: Throwable) {
            Log.e(TAG, "hasPermission check failed, permission=$permission, msg=${t.message}")
            false
        }
}
