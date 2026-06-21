@IsTest
private class PortalLegacyRedirectControllerTest {
    @IsTest
    static void redirectsToLiveLogin() {
        PortalLegacyRedirectController controller = new PortalLegacyRedirectController();
        PageReference ref = controller.redirectToLivePortal();
        System.assertNotEquals(null, ref);
        System.assert(ref.getUrl().contains('/s/login/'));
    }
}