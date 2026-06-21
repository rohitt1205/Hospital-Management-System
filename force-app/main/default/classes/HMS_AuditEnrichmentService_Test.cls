@isTest
private class HMS_AuditEnrichmentService_Test {

    @isTest
    static void testEnrichAddsGeoAndMasksPii() {
        HMS_GeolocationService.clearCacheForTest();
        Test.setMock(HttpCalloutMock.class, new HMS_GeolocationMock_Success());

        HMS_Audit_Event__e evt = new HMS_Audit_Event__e();
        evt.Object_Name__c = 'Patient__c';
        evt.Action__c = 'PATIENT_REGISTERED';
        evt.Record_Id__c = '001000000000001AAA';
        evt.Changed_By_Name__c = 'test@example.com';
        evt.Changed_Fields__c = '{"Phone__c":{"new":"9999999999"}}';
        evt.Context__c = JSON.serialize(new Map<String, Object>{
            'session' => new Map<String, Object>{ 'source_ip' => '8.8.8.8' },
            'user' => new Map<String, Object>{ 'email' => 'secret@example.com' }
        });

        Test.startTest();
        List<HMS_Audit_Event__e> enriched = HMS_AuditEnrichmentService.enrich(
            new List<HMS_Audit_Event__e>{ evt }
        );
        Test.stopTest();

        System.assert(enriched[0].Context__c.contains('geo_country'));
        System.assert(enriched[0].Changed_Fields__c.contains('******'));
    }
}