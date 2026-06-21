public with sharing class PortalLegacyRedirectController {
    public PageReference redirectToLivePortal() {
        return HMSPortalLegacyRedirect.liveLoginRedirect();
    }
}