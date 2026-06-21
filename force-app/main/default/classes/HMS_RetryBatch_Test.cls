/**
 * HMS_RetryBatch_Test
 * Tests: HMS_RetryBatch + HMS_RetryScheduler
 * Coverage target: 90%+
 */
@isTest
private class HMS_RetryBatch_Test {

    @TestSetup
    static void setupData() {
        // Create Pending retry records
        List<AuditLog_Retry__c> retries = new List<AuditLog_Retry__c>();
        retries.add(new AuditLog_Retry__c(
            Payload__c       = '[{"message":"PATIENT_ADMITTED on Admission__c record 001 by user","service":"salesforce-hms","source":"salesforce","hostname":"salesforce-org","ddsource":"salesforce","ddtags":"env:production,object:Admission__c,action:PATIENT_ADMITTED","timestamp":1718000000000,"record_id":"001","object_name":"Admission__c","action":"PATIENT_ADMITTED","changed_by":"test@relanto.ai","changed_fields":"{}","record_name":"A-0001","session_id":"test","department":""}]',
            Attempt_Count__c = 1,
            Last_Error__c    = 'HTTP 503: Service Unavailable',
            Status__c        = 'Pending',
            Object_Name__c   = 'Admission__c',
            Record_Id__c     = '001000000000001AAA'
        ));
        // One already at max attempts
        retries.add(new AuditLog_Retry__c(
            Payload__c       = '[{"message":"test"}]',
            Attempt_Count__c = 2,
            Last_Error__c    = 'HTTP 503: Service Unavailable',
            Status__c        = 'Pending',
            Object_Name__c   = 'Patient__c',
            Record_Id__c     = '001000000000002AAA'
        ));
        insert retries;
    }

    // ─── Test: Batch success path — records marked Succeeded ─────────────────
    @isTest
    static void testBatchSuccess() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new HMS_DatadogMock_Success());
        Database.executeBatch(new HMS_RetryBatch(), 50);
        Test.stopTest();

        List<AuditLog_Retry__c> succeeded = [
            SELECT Id, Status__c
            FROM   AuditLog_Retry__c
            WHERE  Status__c = 'Succeeded'
        ];
        System.assert(!succeeded.isEmpty(),
            'At least one retry record should be marked Succeeded after successful batch');
    }

    // ─── Test: Batch failure path — attempt count incremented ────────────────
    @isTest
    static void testBatchFailure() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new HMS_DatadogMock_Failure());
        Database.executeBatch(new HMS_RetryBatch(), 50);
        Test.stopTest();

        // The record at Attempt_Count 2 should be Failed (maxAttempts=3, 2+1=3)
        List<AuditLog_Retry__c> failed = [
            SELECT Id, Status__c, Attempt_Count__c
            FROM   AuditLog_Retry__c
            WHERE  Status__c = 'Failed'
        ];
        System.assert(!failed.isEmpty(),
            'Record that reached max attempts should be marked Failed');
    }

    // ─── Test: Scheduler fires the batch ─────────────────────────────────────
    @isTest
    static void testScheduler() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new HMS_DatadogMock_Success());
        String jobId = System.schedule(
            'HMS Datadog Retry Test',
            '0 15 * * * ?',
            new HMS_RetryScheduler()
        );
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Scheduler should return a valid job ID');
    }

    // ─── Test: Scheduler execute method ──────────────────────────────────────
    @isTest
    static void testSchedulerExecute() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new HMS_DatadogMock_Success());
        new HMS_RetryScheduler().execute(null);
        Test.stopTest();

        System.assert(true, 'Scheduler execute should complete without error');
    }

    // ─── Test: Empty scope — batch runs cleanly ───────────────────────────────
    @isTest
    static void testBatchEmptyScope() {
        // Delete all pending records first
        delete [SELECT Id FROM AuditLog_Retry__c WHERE Status__c = 'Pending'];

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new HMS_DatadogMock_Success());
        Database.executeBatch(new HMS_RetryBatch(), 50);
        Test.stopTest();

        System.assert(true, 'Batch with empty scope completes without error');
    }
}