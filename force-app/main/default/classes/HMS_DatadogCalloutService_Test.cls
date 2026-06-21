/**
 * HMS_DatadogCalloutService_Test
 * Tests: HMS_DatadogCalloutService
 * Coverage target: 90%+
 */
@isTest
private class HMS_DatadogCalloutService_Test {

    // ─── Helper: build a mock Platform Event ─────────────────────────────────
    private static HMS_Audit_Event__e buildEvent(String objectName, String action, String recordId) {
        HMS_Audit_Event__e evt = new HMS_Audit_Event__e();
        evt.Object_Name__c     = objectName;
        evt.Action__c          = action;
        evt.Record_Id__c       = recordId;
        evt.Changed_By_Id__c   = UserInfo.getUserId();
        evt.Changed_By_Name__c = UserInfo.getUserName();
        evt.Changed_Fields__c  = '{"Status__c":{"old":"Active","new":"Admitted"}}';
        evt.Record_Name__c     = 'Test Record';
        evt.Timestamp__c       = DateTime.now();
        evt.Session_Id__c      = 'test-session-123';
        evt.Department__c      = 'Cardiology';
        return evt;
    }

    // ─── Test: Success path (202) — no retry records created ─────────────────
    @isTest
    static void testSendToDatadog_Success() {
        List<HMS_Audit_Event__e> events = new List<HMS_Audit_Event__e>{
            buildEvent('Patient__c', 'PATIENT_REGISTERED', '001000000000001AAA'),
            buildEvent('Admission__c', 'PATIENT_ADMITTED',  '001000000000002AAA')
        };

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new HMS_DatadogMock_Success());
        HMS_DatadogCalloutService.sendToDatadog(events);
        Test.stopTest();

        // No retry records should be created on success
        List<AuditLog_Retry__c> retries = [SELECT Id FROM AuditLog_Retry__c];
        System.assertEquals(0, retries.size(),
            'No retry records should be created on successful Datadog response');
    }

    // ─── Test: Failure path (503) — retry records created ─────────────────────
    @isTest
    static void testSendToDatadog_Failure() {
        List<HMS_Audit_Event__e> events = new List<HMS_Audit_Event__e>{
            buildEvent('Admission__c', 'PATIENT_ADMITTED', '001000000000003AAA')
        };

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new HMS_DatadogMock_Failure());
        HMS_DatadogCalloutService.sendToDatadog(events);
        Test.stopTest();

        // One retry record should be created
        List<AuditLog_Retry__c> retries = [
            SELECT Id, Status__c, Attempt_Count__c, Object_Name__c
            FROM   AuditLog_Retry__c
        ];
        System.assertEquals(1, retries.size(),
            'One retry record should be created on Datadog 503 failure');
        System.assertEquals('Pending', retries[0].Status__c,
            'Retry record should start as Pending');
        System.assertEquals('Admission__c', retries[0].Object_Name__c,
            'Object name should match the failed event');
    }

    // ─── Test: Empty list — no callout, no exception ──────────────────────────
    @isTest
    static void testSendToDatadog_EmptyList() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new HMS_DatadogMock_Success());
        HMS_DatadogCalloutService.sendToDatadog(new List<HMS_Audit_Event__e>());
        HMS_DatadogCalloutService.sendToDatadog(null);
        Test.stopTest();

        System.assert(true, 'Empty/null list handled without exception');
    }

    // ─── Test: Bulk events (10 events) on success ────────────────────────────
    @isTest
    static void testSendToDatadog_BulkSuccess() {
        List<HMS_Audit_Event__e> events = new List<HMS_Audit_Event__e>();
        for (Integer i = 0; i < 10; i++) {
            events.add(buildEvent('Medical_Record__c', 'MEDICAL_RECORD_CHANGED',
                '001000000000' + String.valueOf(i).leftPad(3, '0') + 'AAA'));
        }

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new HMS_DatadogMock_Success());
        HMS_DatadogCalloutService.sendToDatadog(events);
        Test.stopTest();

        List<AuditLog_Retry__c> retries = [SELECT Id FROM AuditLog_Retry__c];
        System.assertEquals(0, retries.size(),
            'No retry records for bulk success scenario');
    }

    // ─── Test: retryPayload success ──────────────────────────────────────────
    @isTest
    static void testRetryPayload_Success() {
        String payload = '[{"message":"test","service":"salesforce-hms"}]';

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new HMS_DatadogMock_Success());
        Boolean result = HMS_DatadogCalloutService.retryPayload(payload, 'RETRY001');
        Test.stopTest();

        System.assertEquals(true, result, 'retryPayload should return true on 202');
    }

    // ─── Test: retryPayload failure ───────────────────────────────────────────
    @isTest
    static void testRetryPayload_Failure() {
        String payload = '[{"message":"test"}]';

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new HMS_DatadogMock_Failure());
        Boolean result = HMS_DatadogCalloutService.retryPayload(payload, 'RETRY002');
        Test.stopTest();

        System.assertEquals(false, result, 'retryPayload should return false on 503');
    }
}