package com.ey.echat

import android.content.Context
import android.content.Intent
import android.util.Log
import cn.jpush.android.api.JPushMessage
import cn.jpush.android.service.JPushMessageReceiver

/**
 * JPush 消息接收器
 * 用于接收 alias 和 tag 操作的回调结果
 * 
 * 从 JPush 3.0.7 开始，需要配置继承 JPushMessageReceiver 的广播
 * 从 JPush 3.3.0 开始，所有事件都将通过该类回调
 */
class JPushReceiver : JPushMessageReceiver() {
    
    companion object {
        private const val TAG = "JPushReceiver"
    }
    
    /**
     * 设置别名回调
     */
    override fun onAliasOperatorResult(context: Context?, message: JPushMessage?) {
        super.onAliasOperatorResult(context, message)
        message?.let {
            Log.d(TAG, "onAliasOperatorResult: alias=${it.alias}, sequence=${it.sequence}, errorCode=${it.errorCode}")
            if (it.errorCode == 0) {
                Log.i(TAG, "设置别名成功: ${it.alias}")
            } else {
                Log.e(TAG, "设置别名失败: errorCode=${it.errorCode}")
            }
        }
    }
    
    /**
     * 设置标签回调
     */
    override fun onTagOperatorResult(context: Context?, message: JPushMessage?) {
        super.onTagOperatorResult(context, message)
        message?.let {
            Log.d(TAG, "onTagOperatorResult: tags=${it.tags}, sequence=${it.sequence}, errorCode=${it.errorCode}")
            if (it.errorCode == 0) {
                Log.i(TAG, "设置标签成功: ${it.tags}")
            } else {
                Log.e(TAG, "设置标签失败: errorCode=${it.errorCode}")
            }
        }
    }
    
    /**
     * 检查标签绑定回调
     */
    override fun onCheckTagOperatorResult(context: Context?, message: JPushMessage?) {
        super.onCheckTagOperatorResult(context, message)
        message?.let {
            Log.d(TAG, "onCheckTagOperatorResult: tag=${it.checkTag}, bound=${it.tagCheckResult}, errorCode=${it.errorCode}")
        }
    }
    
    /**
     * 通知点击回调
     */
    override fun onNotifyMessageOpened(context: Context?, message: cn.jpush.android.api.NotificationMessage?) {
        super.onNotifyMessageOpened(context, message)
        message?.let {
            Log.d(TAG, "onNotifyMessageOpened: messageId=${it.notificationId}, title=${it.notificationTitle}, content=${it.notificationContent}")
            
            // 发送广播通知 Flutter 层
            val intent = Intent("com.ey.echat.JPUSH_NOTIFICATION_OPENED")
            intent.putExtra("message_id", it.notificationId)
            intent.putExtra("title", it.notificationTitle)
            intent.putExtra("content", it.notificationContent)
            intent.putExtra("extras", it.notificationExtras)
            context?.sendBroadcast(intent)
        }
    }
    
    /**
     * 通知收到回调
     */
    override fun onNotifyMessageArrived(context: Context?, message: cn.jpush.android.api.NotificationMessage?) {
        super.onNotifyMessageArrived(context, message)
        message?.let {
            Log.d(TAG, "onNotifyMessageArrived: messageId=${it.notificationId}, title=${it.notificationTitle}")
        }
    }
    
    /**
     * 通知移除回调
     */
    override fun onNotifyMessageDismiss(context: Context?, message: cn.jpush.android.api.NotificationMessage?) {
        super.onNotifyMessageDismiss(context, message)
        message?.let {
            Log.d(TAG, "onNotifyMessageDismiss: messageId=${it.notificationId}")
        }
    }
    
    /**
     * 连接状态变化回调
     */
    override fun onConnected(context: Context?, isConnected: Boolean) {
        super.onConnected(context, isConnected)
        Log.d(TAG, "onConnected: isConnected=$isConnected")
    }
    
    /**
     * Registration ID 变化回调
     */
    override fun onRegister(context: Context?, registrationId: String?) {
        super.onRegister(context, registrationId)
        Log.d(TAG, "onRegister: registrationId=$registrationId")
        
        // 发送广播通知 Flutter 层
        val intent = Intent("com.ey.echat.JPUSH_REGISTRATION_ID")
        intent.putExtra("registration_id", registrationId)
        context?.sendBroadcast(intent)
    }
}
