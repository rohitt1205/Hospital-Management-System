@isTest
private class HMSPatientPortalControllerTest {

    @isTest
    static void returnsDataForUserLinkedById() {
        Id userId = UserInfo.getUserId();

        Patient__c patient = new Patient__c(
            Name = 'Portal Patient',
            Email__c = 'linked.by.id@example.invalid',
            Status__c = 'Active',
            Portal_User__c = userId
        );
        insert patient;

        Test.startTest();
        String payload = HMSPatientPortalController.getPortalSummary();
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(payload);
        System.assertEquals(true, result.get('linked'), 'Patient linked by Portal_User__c should resolve.');
        System.assertEquals('Portal Patient', result.get('patientName'), 'Profile name should be returned.');
        System.assertEquals(0, ((List<Object>) result.get('appointments')).size(), 'No appointments expected for this patient.');
    }

    @isTest
    static void selfHealsLinkByEmail() {
        // Patient has no Portal_User__c but its email matches the running user.
        Patient__c patient = new Patient__c(
            Name = 'Email Match Patient',
            Email__c = UserInfo.getUserEmail(),
            Status__c = 'Active'
        );
        insert patient;

        Test.startTest();
        String payload = HMSPatientPortalController.getPortalSummary();
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(payload);
        System.assertEquals(true, result.get('linked'), 'Email fallback should resolve the patient.');

        Patient__c healed = [SELECT Portal_User__c FROM Patient__c WHERE Id = :patient.Id];
        System.assertEquals(UserInfo.getUserId(), healed.Portal_User__c,
            'Link should be self-healed by stamping Portal_User__c.');
    }

    @isTest
    static void reportsNoLinkedPatient() {
        // No patient matches the running user by id or email.
        Test.startTest();
        String payload = HMSPatientPortalController.getPortalSummary();
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(payload);
        System.assertEquals(false, result.get('linked'), 'No matching patient should report unlinked.');
        System.assertEquals('No linked patient record', result.get('status'),
            'Unlinked state should carry a helpful status.');
        System.assertNotEquals(null, result.get('loggedInEmail'),
            'Diagnostics should expose the logged-in email for debugging.');
    }

    @isTest
    static void cacheableWrapperStillWorks() {
        Patient__c patient = new Patient__c(
            Name = 'Wrapper Patient',
            Email__c = 'wrapper@example.invalid',
            Status__c = 'Active',
            Portal_User__c = UserInfo.getUserId()
        );
        insert patient;

        Test.startTest();
        String payload = HMSPatientPortalController.getPortalSummaryJson();
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(payload);
        System.assertEquals(true, result.get('linked'), 'Backward-compatible wrapper should return data.');
    }

    @isTest
    static void returnsEmbeddedChatConfigWhenDeploymentExists() {
        List<Site> eswSites = [
            SELECT Id
            FROM Site
            WHERE Name = 'ESW_Hospital_Patient_Porta_17818759301761'
            LIMIT 1
        ];
        if (eswSites.isEmpty()) {
            return;
        }

        Test.startTest();
        String payload = HMSPatientPortalController.getEmbeddedChatConfig();
        Test.stopTest();

        Map<String, Object> config = (Map<String, Object>) JSON.deserializeUntyped(payload);
        System.assertEquals('Hospital_Patient_Portal_Deployment', config.get('deploymentName'));
        System.assertNotEquals(null, config.get('bootstrapUrl'));
        System.assertNotEquals(null, config.get('scrt2Url'));
    }
}