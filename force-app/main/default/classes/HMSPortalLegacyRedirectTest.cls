@IsTest
private class HMSPortalLegacyRedirectTest {

    @IsTest
    static void exposesLivePortalUrls() {
        System.assert(HMSPortalLegacyRedirect.LIVE_LOGIN_URL.contains('/s/login/'));
        System.assert(HMSPortalLegacyRedirect.LIVE_HOME_URL.contains('/s/'));
    }

    @IsTest
    static void liveLoginRedirectPointsToLivePortal() {
        PageReference ref = HMSPortalLegacyRedirect.liveLoginRedirect();
        System.assertEquals(true, ref.getRedirect());
        System.assert(ref.getUrl().contains('/s/login/'));
    }

    @IsTest
    static void liveHomeRedirectPointsToLivePortal() {
        PageReference ref = HMSPortalLegacyRedirect.liveHomeRedirect();
        System.assertEquals(true, ref.getRedirect());
        System.assert(ref.getUrl().contains('/s/'));
    }

    @IsTest
    static void loginControllerRedirectsRetiredPortalStartUrl() {
        PageReference pageRef = Page.CommunitiesLogin;
        pageRef.getParameters().put('startURL', '/hmspatient/');
        Test.setCurrentPage(pageRef);
        CommunitiesLoginController controller = new CommunitiesLoginController();
        PageReference result = controller.forwardToAuthPage();
        System.assertNotEquals(null, result);
        System.assert(result.getUrl().contains('/s/login/'));
    }

    @IsTest
    static void detectsRetiredPortalFromStartUrlParameter() {
        PageReference pageRef = Page.CommunitiesLogin;
        pageRef.getParameters().put('startURL', '/hmspatient/');
        Test.setCurrentPage(pageRef);
        System.assertEquals(true, HMSPortalLegacyRedirect.isRetiredPortalSite());
    }

    @IsTest
    static void landingControllerRedirectsRetiredPortal() {
        PageReference pageRef = Page.CommunitiesLanding;
        pageRef.getParameters().put('startURL', '/hmspatient/');
        Test.setCurrentPage(pageRef);
        CommunitiesLandingController controller = new CommunitiesLandingController();
        PageReference result = controller.forwardToStartPage();
        System.assertNotEquals(null, result);
        System.assert(result.getUrl().contains('/s/'));
    }
}