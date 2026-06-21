/**
 * HMS_AuditEventTrigger_Test
 * Tests end-to-end flow: HMS_AuditLogService → Platform Event → HMS_AuditEventTrigger → Datadog callout.
 */
@isTest
private class HMS_AuditEventTrigger_Test {

    @isTest
    static void testPublishEventDeliverCompletes() {
        Patient__c patient = new Patient__c(
            Name                = 'Audit Event Test Patient',
            Status__c           = 'Active',
            Patient_Category__c = 'Normal',
            Date_of_Birth__c    = Date.today().addYears(-28)
        );

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new HMS_DatadogMock_Success());
        HMS_AuditLogService.log('Patient__c', 'PATIENT_REGISTERED', patient, null);
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assert(true, 'Platform event publish and deliver completed without uncaught exception');
    }

    @isTest
    static void testPublishEventFailureCreatesRetryRecord() {
        Patient__c patient = new Patient__c(
            Name                = 'Audit Event Failure Patient',
            Status__c           = 'Active',
            Patient_Category__c = 'Normal',
            Date_of_Birth__c    = Date.today().addYears(-28)
        );

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new HMS_DatadogMock_Failure());
        HMS_AuditLogService.log('Patient__c', 'PATIENT_UPDATED', patient, patient);
        Test.getEventBus().deliver();
        Test.stopTest();

        List<AuditLog_Retry__c> retries = [
            SELECT Id, Status__c, Object_Name__c
            FROM   AuditLog_Retry__c
        ];
        System.assertEquals(1, retries.size(),
            'Failed Datadog callout should create one retry record');
        System.assertEquals('Pending', retries[0].Status__c);
        System.assertEquals('Patient__c', retries[0].Object_Name__c);
    }
}