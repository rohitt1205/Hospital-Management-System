@isTest
private class GuardianTriggerTest {
    @isTest
    static void testSinglePrimaryGuardianConstraint() {
        // Create Patient
        Patient__c pat = new Patient__c(Name = 'Test Patient');
        insert pat;
        
        // Create first primary guardian
        Guardian__c g1 = new Guardian__c(
            Name = 'Guardian One',
            Patient__c = pat.Id,
            Primary_Guardian__c = true
        );
        insert g1;
        
        // Create second primary guardian (should fail)
        Guardian__c g2 = new Guardian__c(
            Name = 'Guardian Two',
            Patient__c = pat.Id,
            Primary_Guardian__c = true
        );
        
        Test.startTest();
        try {
            insert g2;
            System.assert(false, 'Should have failed with duplicate primary guardian error.');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('Only one primary guardian is allowed per patient'));
        }
        Test.stopTest();
    }
}