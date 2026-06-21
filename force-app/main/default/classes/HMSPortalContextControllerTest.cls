@isTest
private class HMSPortalContextControllerTest {

    @isTest
    static void returnsPortalContextPayload() {
        Test.startTest();
        String payload = HMSPortalContextController.getPortalContext();
        Test.stopTest();

        Map<String, Object> ctx = (Map<String, Object>) JSON.deserializeUntyped(payload);
        System.assertNotEquals(null, ctx.get('role'));
        System.assertNotEquals(null, ctx.get('userEmail'));
        System.assertEquals(UserInfo.getUserId(), ctx.get('userId'));
    }

    @isTest
    static void resolveRoleForRunningUser() {
        Test.startTest();
        String role = HMSPortalContextService.resolveRole();
        Boolean staff = HMSPortalContextService.isStaffUser();
        Boolean admin = HMSPortalContextService.isAdminUser();
        Test.stopTest();

        System.assertNotEquals(null, role);
        System.assertNotEquals(null, staff);
        System.assertNotEquals(null, admin);
    }
}