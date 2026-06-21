@isTest
private class HMS_DatadogCalloutQueueable_Test {

    @isTest
    static void testQueueableSuccess() {
        HMS_Audit_Event__e evt = new HMS_Audit_Event__e();
        evt.Object_Name__c     = 'Patient__c';
        evt.Action__c          = 'PATIENT_REGISTERED';
        evt.Record_Id__c       = '001000000000001AAA';
        evt.Changed_By_Id__c   = UserInfo.getUserId();
        evt.Changed_By_Name__c = UserInfo.getUserName();
        evt.Changed_Fields__c  = '{}';
        evt.Record_Name__c     = 'Queueable Test';
        evt.Timestamp__c       = DateTime.now();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new HMS_DatadogMock_Success());
        System.enqueueJob(new HMS_DatadogCalloutQueueable(new List<HMS_Audit_Event__e>{ evt }));
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM AuditLog_Retry__c]);
    }

    @isTest
    static void testPlatformEventFieldsSurviveSerialization() {
        HMS_Audit_Event__e evt = new HMS_Audit_Event__e();
        evt.Object_Name__c     = 'Patient__c';
        evt.Action__c          = 'PATIENT_REGISTERED';
        evt.Record_Id__c       = '001000000000001AAA';
        evt.Changed_By_Id__c   = UserInfo.getUserId();
        evt.Changed_By_Name__c = UserInfo.getUserName();
        evt.Changed_Fields__c  = '{"Name":{"new":"Mbappe"}}';
        evt.Record_Name__c     = 'Mbappe';
        evt.Timestamp__c       = DateTime.now();
        evt.Session_Id__c      = 'session-abc';
        evt.Department__c      = 'Cardiology';
        evt.Context__c         = '{"operation":"INSERT","audit_event_id":"HMS-TEST"}';

        HMS_DatadogCalloutQueueable job = new HMS_DatadogCalloutQueueable(
            new List<HMS_Audit_Event__e>{ evt }
        );

        System.assert(job.serializedEvents.contains('Mbappe'),
            'Serialized payload must retain platform event field values');
        System.assert(job.serializedEvents.contains('PATIENT_REGISTERED'),
            'Serialized payload must retain action');
        System.assert(job.serializedEvents.contains('HMS-TEST'),
            'Serialized payload must retain context');

        List<HMS_Audit_Event__e> restored = HMS_DatadogCalloutQueueable.deserializeEvents(
            job.serializedEvents
        );
        System.assertEquals('Mbappe', restored[0].Record_Name__c);
        System.assertEquals('PATIENT_REGISTERED', restored[0].Action__c);
    }
}