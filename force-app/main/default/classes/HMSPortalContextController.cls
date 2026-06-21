/**
 * Portal role detection for the Experience Cloud shell (patient vs staff/admin).
 */
public with sharing class HMSPortalContextController {

    @AuraEnabled(cacheable=true)
    public static String getPortalContext() {
        Map<String, Object> ctx = new Map<String, Object>();
        ctx.put('role', HMSPortalContextService.resolveRole());
        ctx.put('userName', UserInfo.getName());
        ctx.put('userEmail', UserInfo.getUserEmail());
        ctx.put('userId', UserInfo.getUserId());
        return JSON.serialize(ctx);
    }
}