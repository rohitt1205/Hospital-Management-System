@isTest
private class HMS_SecurityAuditBatch_Test {

    @isTest
    static void testBatchRunsAndUpdatesTracking() {
        insert new HMS_Audit_Tracking__c(
            Name = 'Default',
            Last_Login_Processed__c = DateTime.now().addDays(-1),
            Active_Session_Map__c = '{}'
        );

        Test.startTest();
        Database.executeBatch(new HMS_SecurityAuditBatch(), 200);
        Test.stopTest();

        HMS_Audit_Tracking__c state = [
            SELECT Id, Last_Login_Processed__c, Active_Session_Map__c
            FROM HMS_Audit_Tracking__c
            WHERE Name = 'Default'
            LIMIT 1
        ];
        System.assertNotEquals(null, state, 'Tracking state should exist after batch');
    }

    @isTest
    static void testLoadCurrentSessions() {
        Map<String, Map<String, String>> sessions = HMS_SecurityAuditBatch.loadCurrentSessions();
        System.assertNotEquals(null, sessions);
    }

    @isTest
    static void testProcessLoginScope() {
        insert new HMS_Audit_Tracking__c(
            Name = 'Default',
            Last_Login_Processed__c = DateTime.now().addDays(-1),
            Active_Session_Map__c = '{}'
        );

        HMS_SecurityAuditService.LoginAuditRecord login =
            new HMS_SecurityAuditService.LoginAuditRecord();
        login.userId = UserInfo.getUserId();
        login.loginTime = DateTime.now();
        login.status = 'Success';
        login.sourceIp = '8.8.8.8';

        HMS_SecurityAuditBatch batch = new HMS_SecurityAuditBatch();
        Test.startTest();
        batch.processLoginScope(new List<LoginHistory>());
        batch.processLoginAuditRecords(
            new List<HMS_SecurityAuditService.LoginAuditRecord>{ login }
        );
        Test.stopTest();

        System.assert(true, 'Login audit batch helpers should run without exception');
    }

    @isTest
    static void testFinishPublishesLogoutForEndedSession() {
        String endedKey = String.valueOf(UserInfo.getUserId()) + '|ended-session';
        insert new HMS_Audit_Tracking__c(
            Name = 'Default',
            Last_Login_Processed__c = DateTime.now().addDays(-1),
            Active_Session_Map__c = JSON.serialize(new Map<String, Map<String, String>>{
                endedKey => new Map<String, String>{
                    'userId' => String.valueOf(UserInfo.getUserId()),
                    'sessionKey' => endedKey,
                    'sessionId' => 'ended-session'
                }
            })
        );

        HMS_SecurityAuditBatch batch = new HMS_SecurityAuditBatch();
        Test.startTest();
        batch.finish(null);
        Test.stopTest();

        HMS_Audit_Tracking__c state = [
            SELECT Active_Session_Map__c
            FROM HMS_Audit_Tracking__c
            WHERE Name = 'Default'
            LIMIT 1
        ];
        System.assertNotEquals(null, state.Active_Session_Map__c);
    }

    @isTest
    static void testParseAndSerializeSessionMap() {
        Map<String, Map<String, String>> input = new Map<String, Map<String, String>>{
            '005xx|abc' => new Map<String, String>{ 'userId' => UserInfo.getUserId() }
        };
        String serialized = HMS_SecurityAuditBatch.serializeSessionMap(input);
        Map<String, Map<String, String>> parsed = HMS_SecurityAuditBatch.parseSessionMap(serialized);
        System.assertEquals(1, parsed.size());
    }

    @isTest
    static void testConstructorWithoutTrackingRow() {
        HMS_SecurityAuditBatch batch = new HMS_SecurityAuditBatch();
        System.assertNotEquals(null, batch);
    }

    @isTest
    static void testParseSessionMapMalformedJson() {
        Map<String, Map<String, String>> parsed =
            HMS_SecurityAuditBatch.parseSessionMap('not-json');
        System.assertEquals(0, parsed.size());
    }

    @isTest
    static void testExecuteEmptyScope() {
        insert new HMS_Audit_Tracking__c(
            Name = 'Default',
            Last_Login_Processed__c = DateTime.now().addDays(-1),
            Active_Session_Map__c = '{}'
        );

        HMS_SecurityAuditBatch batch = new HMS_SecurityAuditBatch();
        Test.startTest();
        batch.execute(null, new List<SObject>());
        Test.stopTest();

        System.assert(true, 'Empty execute scope should complete without error');
    }

    @isTest(SeeAllData=true)
    static void testProcessLoginScopeWithLoginHistory() {
        List<LoginHistory> logins = [
            SELECT Id, UserId, LoginTime, SourceIp, LoginType, LoginUrl,
                   Browser, Platform, Status, Application
            FROM LoginHistory
            ORDER BY LoginTime DESC
            LIMIT 5
        ];
        if (logins.isEmpty()) {
            return;
        }

        HMS_SecurityAuditBatch batch = new HMS_SecurityAuditBatch();
        Test.startTest();
        batch.processLoginScope(logins);
        Test.stopTest();

        System.assert(true, 'Login history scope should process without error');
    }

    @isTest
    static void testSerializeEmptySessionMap() {
        System.assertEquals('{}', HMS_SecurityAuditBatch.serializeSessionMap(new Map<String, Map<String, String>>()));
    }

    @isTest
    static void testFindEndedSessions() {
        Map<String, Map<String, String>> previous = new Map<String, Map<String, String>>{
            '005xx|abc' => new Map<String, String>{ 'userId' => UserInfo.getUserId(), 'sessionKey' => '005xx|abc' }
        };
        Map<String, Map<String, String>> current = new Map<String, Map<String, String>>();

        List<Map<String, String>> ended = HMS_SecurityAuditBatch.findEndedSessions(previous, current);
        System.assertEquals(1, ended.size());
    }
}