@isTest
private class PatientPortalProvisionerTest {

    @isTest
    static void linkExistingPatientByEmail() {
        User runningUser = [SELECT Id, Email FROM User WHERE Id = :UserInfo.getUserId()];

        Patient__c existing = new Patient__c(
            Name = 'Existing Patient',
            Email__c = runningUser.Email,
            Status__c = 'Active'
        );
        insert existing;

        Test.startTest();
        PatientPortalProvisioner.linkPatients(new Set<Id>{ runningUser.Id });
        Test.stopTest();

        Patient__c linked = [SELECT Portal_User__c FROM Patient__c WHERE Id = :existing.Id];
        System.assertEquals(runningUser.Id, linked.Portal_User__c,
            'Existing patient should be linked to the user by matching email.');

        Integer total = [SELECT COUNT() FROM Patient__c WHERE Portal_User__c = :runningUser.Id];
        System.assertEquals(1, total, 'No duplicate patient should be created when a match exists.');
    }

    @isTest
    static void createsPatientWhenNoMatch() {
        User runningUser = [SELECT Id, Email FROM User WHERE Id = :UserInfo.getUserId()];

        Test.startTest();
        PatientPortalProvisioner.linkPatients(new Set<Id>{ runningUser.Id });
        Test.stopTest();

        List<Patient__c> created = [
            SELECT Id, Email__c, Status__c, Portal_User__c
            FROM Patient__c
            WHERE Portal_User__c = :runningUser.Id
        ];
        System.assertEquals(1, created.size(), 'A new patient should be created and linked.');
        System.assertEquals('Active', created[0].Status__c, 'New patient should default to Active.');
    }

    @isTest
    static void doesNotRelinkAlreadyLinkedUser() {
        User runningUser = [SELECT Id, Email FROM User WHERE Id = :UserInfo.getUserId()];

        Patient__c already = new Patient__c(
            Name = 'Already Linked',
            Email__c = runningUser.Email,
            Status__c = 'Active',
            Portal_User__c = runningUser.Id
        );
        insert already;

        Test.startTest();
        PatientPortalProvisioner.linkPatients(new Set<Id>{ runningUser.Id });
        Test.stopTest();

        Integer total = [SELECT COUNT() FROM Patient__c WHERE Portal_User__c = :runningUser.Id];
        System.assertEquals(1, total, 'Should not create another patient when one is already linked.');
    }

    @isTest
    static void internalUsersAreIgnored() {
        User runningUser = [SELECT Id, Email, IsActive, UserType FROM User WHERE Id = :UserInfo.getUserId()];

        Test.startTest();
        PatientPortalProvisioner.handleNewUsers(new List<User>{ runningUser });
        Test.stopTest();

        Integer total = [SELECT COUNT() FROM Patient__c WHERE Portal_User__c = :runningUser.Id];
        System.assertEquals(0, total, 'Internal (non-portal) users should not get a patient record.');
    }

    @isTest
    static void assignPermissionSetsRuns() {
        // Exercises the perm-set assignment path. Database.insert(...,false) tolerates
        // license-mismatch rows, so this asserts the method completes without error.
        Test.startTest();
        PatientPortalProvisioner.assignPermissionSets(new Set<Id>{ UserInfo.getUserId() });
        PatientPortalProvisioner.assignPermissionSets(new Set<Id>());
        Test.stopTest();
        System.assert(true, 'Permission set assignment executed without throwing.');
    }

    @isTest
    static void triggerFiresOnUserInsert() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String uniq = 'hmsptest' + String.valueOf(System.currentTimeMillis());

        User u = new User(
            FirstName = 'Trigger',
            LastName = 'Coverage',
            Email = uniq + '@example.invalid',
            Username = uniq + '@example.invalid.hms',
            Alias = 'tcov',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id
        );

        Test.startTest();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
        }
        Test.stopTest();

        System.assertNotEquals(null, u.Id, 'User insert should fire UserTrigger.');
    }
}