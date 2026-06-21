@isTest
private class HMS_SecurityAuditService_Test {

    @isTest
    static void testPublishEmptyLists() {
        System.assertEquals(0, HMS_SecurityAuditService.publishLoginEvents(new List<LoginHistory>()));
        System.assertEquals(0, HMS_SecurityAuditService.publishLogoutEvents(new List<Map<String, String>>()));
        System.assertEquals(true, HMS_SecurityAuditService.isEnabled());
    }

    @isTest
    static void testPublishLoginAndLogoutEvents() {
        HMS_SecurityAuditService.LoginAuditRecord login =
            new HMS_SecurityAuditService.LoginAuditRecord();
        login.userId = UserInfo.getUserId();
        login.loginTime = DateTime.now();
        login.status = 'Success';
        login.sourceIp = '8.8.8.8';
        login.browser = 'Chrome';
        login.platform = 'Windows';
        login.loginType = 'Application';
        login.application = 'Salesforce';

        List<Map<String, String>> endedSessions = new List<Map<String, String>>{
            new Map<String, String>{
                'userId' => String.valueOf(UserInfo.getUserId()),
                'sessionKey' => String.valueOf(UserInfo.getUserId()) + '|logout-test',
                'sessionId' => 'logout-test'
            }
        };

        Test.startTest();
        Integer loginCount = HMS_SecurityAuditService.publishLoginAuditRecords(
            new List<HMS_SecurityAuditService.LoginAuditRecord>{ login }
        );
        Integer logoutCount = HMS_SecurityAuditService.publishLogoutEvents(endedSessions);
        Test.stopTest();

        System.assertEquals(1, loginCount);
        System.assertEquals(1, logoutCount);
    }

    @isTest
    static void testPublishFailedLoginEvent() {
        HMS_SecurityAuditService.LoginAuditRecord login =
            new HMS_SecurityAuditService.LoginAuditRecord();
        login.userId = UserInfo.getUserId();
        login.loginTime = DateTime.now();
        login.status = 'Failed';
        login.sourceIp = '203.0.113.10';

        Test.startTest();
        Integer loginCount = HMS_SecurityAuditService.publishLoginAuditRecords(
            new List<HMS_SecurityAuditService.LoginAuditRecord>{ login }
        );
        Test.stopTest();

        System.assertEquals(1, loginCount);
    }

    @isTest
    static void testPublishLoginAuditRecordsNullAndEmpty() {
        System.assertEquals(0, HMS_SecurityAuditService.publishLoginAuditRecords(null));
        System.assertEquals(0, HMS_SecurityAuditService.publishLoginAuditRecords(
            new List<HMS_SecurityAuditService.LoginAuditRecord>()
        ));
    }

    @isTest
    static void testBuildAuthContext() {
        Map<String, Object> context = HMS_SecurityAuditService.buildAuthContext(
            'USER_LOGIN_SUCCESS',
            UserInfo.getUserId(),
            UserInfo.getUserName(),
            'Test User',
            null,
            DateTime.now(),
            '8.8.8.8',
            'Chrome',
            'Windows',
            'Application',
            'Salesforce',
            '',
            'Success',
            DateTime.now(),
            null
        );
        System.assertEquals('LOGIN', context.get('operation'));
    }
}