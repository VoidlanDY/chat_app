package com.ey.echat

import cn.jiguang.android.service.JCommonService

/**
 * JPush 推送服务
 * 继承 JCommonService 以在更多手机平台上保持推送通道稳定
 * 
 * 注意：需要在 AndroidManifest.xml 中注册此 Service
 */
class JPushService : JCommonService()
