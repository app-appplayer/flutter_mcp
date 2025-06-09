package com.example.flutter_mcp.storage

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.example.flutter_mcp.utils.Constants

class SecureStorageService(private val context: Context) {
    private val masterKey: MasterKey by lazy {
        MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
    }
    
    private val sharedPreferences: SharedPreferences by lazy {
        EncryptedSharedPreferences.create(
            context,
            Constants.SECURE_STORAGE_ALIAS,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }
    
    fun store(key: String, value: String): Boolean {
        return try {
            sharedPreferences.edit().putString(key, value).commit()
        } catch (e: Exception) {
            false
        }
    }
    
    fun read(key: String): String? {
        return try {
            sharedPreferences.getString(key, null)
        } catch (e: Exception) {
            null
        }
    }
    
    fun delete(key: String): Boolean {
        return try {
            sharedPreferences.edit().remove(key).commit()
        } catch (e: Exception) {
            false
        }
    }
    
    fun containsKey(key: String): Boolean {
        return try {
            sharedPreferences.contains(key)
        } catch (e: Exception) {
            false
        }
    }
    
    fun deleteAll(): Boolean {
        return try {
            sharedPreferences.edit().clear().commit()
        } catch (e: Exception) {
            false
        }
    }
}