@IsTest
private class PatientPortalLinkServiceTest {

    @IsTest
    static void resolvesByPortalUserField() {
        User portalUser = createPortalUser('resolve.byuser@test.hms');
        Patient__c patient = createPatient('Resolve By User', 'resolve.byuser@test.hms', portalUser.Id);

        System.runAs(portalUser) {
            Patient__c found = PatientPortalLinkService.resolveForRunningUser();
            System.assertEquals(patient.Id, found.Id);
        }
    }

    @IsTest
    static void selfHealsFromEmailMatch() {
        User portalUser = createPortalUser('resolve.email@test.hms');
        Patient__c patient = createPatient('Resolve By Email', 'resolve.email@test.hms', null);

        System.runAs(portalUser) {
            Patient__c found = PatientPortalLinkService.resolveForRunningUser();
            System.assertEquals(patient.Id, found.Id);
        }

        Patient__c healed = [SELECT Portal_User__c FROM Patient__c WHERE Id = :patient.Id];
        System.assertEquals(portalUser.Id, healed.Portal_User__c);
    }

    @IsTest
    static void enforceUniquePortalUserClearsDuplicate() {
        User portalUser = createPortalUser('unique.user@test.hms');
        Patient__c keeper = createPatient('Keeper Patient', 'unique.user@test.hms', portalUser.Id);
        Patient__c other = createPatient('Other Patient', 'other@test.hms', portalUser.Id);

        Test.startTest();
        PatientPortalLinkService.enforceUniquePortalUser(
            new List<Patient__c>{ keeper },
            new Map<Id, Patient__c>{ keeper.Id => new Patient__c(Id = keeper.Id, Portal_User__c = null) }
        );
        Test.stopTest();

        Patient__c cleared = [SELECT Portal_User__c FROM Patient__c WHERE Id = :other.Id];
        System.assertEquals(null, cleared.Portal_User__c);
    }

    private static User createPortalUser(String emailLocal) {
        Profile communityProfile = [
            SELECT Id FROM Profile WHERE Name = 'Customer Community Plus User' LIMIT 1
        ];
        Account acct = new Account(Name = 'Portal Test ' + emailLocal);
        insert acct;
        Contact con = new Contact(
            FirstName = 'Portal',
            LastName = 'Test',
            Email = emailLocal,
            AccountId = acct.Id
        );
        insert con;
        User u = new User(
            Alias = 'ptst',
            Email = emailLocal,
            EmailEncodingKey = 'UTF-8',
            LastName = 'PortalTest',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = communityProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = emailLocal + '.hms',
            ContactId = con.Id
        );
        insert u;
        return u;
    }

    private static Patient__c createPatient(String name, String email, Id portalUserId) {
        Patient__c p = new Patient__c(
            Name = name,
            Email__c = email,
            Status__c = 'Active',
            Portal_User__c = portalUserId
        );
        insert p;
        return p;
    }
}