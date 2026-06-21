@isTest
private class MedicalRecordServiceTest {

    @isTest
    static void testMedicalRecordApprovalFlow() {
        // 1. Create standard profile user for resident and supervisor
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        
        String rand1 = String.valueOf(Crypto.getRandomInteger());
        User uResident = new User(
            Alias = 'resdoc', Email='resdoc@testorg.com', 
            EmailEncodingKey='UTF-8', LastName='ResidentDoc', LanguageLocaleKey='en_US', 
            LocaleSidKey='en_US', ProfileId = p.Id, 
            TimeZoneSidKey='America/Los_Angeles', UserName='resdoc_' + rand1 + '@testorg.com'
        );
        
        String rand2 = String.valueOf(Crypto.getRandomInteger());
        User uSenior = new User(
            Alias = 'sendoc', Email='sendoc@testorg.com', 
            EmailEncodingKey='UTF-8', LastName='SeniorDoc', LanguageLocaleKey='en_US', 
            LocaleSidKey='en_US', ProfileId = p.Id, 
            TimeZoneSidKey='America/Los_Angeles', UserName='sendoc_' + rand2 + '@testorg.com'
        );

        String rand3 = String.valueOf(Crypto.getRandomInteger());
        User uOther = new User(
            Alias = 'othdoc', Email='othdoc@testorg.com', 
            EmailEncodingKey='UTF-8', LastName='OtherDoc', LanguageLocaleKey='en_US', 
            LocaleSidKey='en_US', ProfileId = p.Id, 
            TimeZoneSidKey='America/Los_Angeles', UserName='othdoc_' + rand3 + '@testorg.com'
        );

        // Insert setup objects inside runAs to avoid Mixed DML Exception
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new List<User>{uResident, uSenior, uOther};
            PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'HMS_Admin' LIMIT 1];
            List<PermissionSetAssignment> psas = new List<PermissionSetAssignment>();
            psas.add(new PermissionSetAssignment(AssigneeId = uResident.Id, PermissionSetId = ps.Id));
            psas.add(new PermissionSetAssignment(AssigneeId = uSenior.Id, PermissionSetId = ps.Id));
            psas.add(new PermissionSetAssignment(AssigneeId = uOther.Id, PermissionSetId = ps.Id));
            insert psas;
        }

        // 2. Create Staff records
        Staff__c staffResident = new Staff__c(
            Salesforce_User__c = uResident.Id,
            Staff_Role__c = 'Resident',
            Status__c = 'Active'
        );
        Staff__c staffSenior = new Staff__c(
            Salesforce_User__c = uSenior.Id,
            Staff_Role__c = 'Doctor',
            Status__c = 'Active'
        );
        Staff__c staffOther = new Staff__c(
            Salesforce_User__c = uOther.Id,
            Staff_Role__c = 'Doctor',
            Status__c = 'Active'
        );
        insert new List<Staff__c>{staffResident, staffSenior, staffOther};

        // 3. Create Doctor records
        Doctor__c docSenior = new Doctor__c(
            Name = 'Dr. Senior',
            Staff__c = staffSenior.Id,
            Active__c = true
        );
        Doctor__c docOther = new Doctor__c(
            Name = 'Dr. Other',
            Staff__c = staffOther.Id,
            Active__c = true
        );
        insert new List<Doctor__c>{docSenior, docOther};

        Doctor__c docResident = new Doctor__c(
            Name = 'Dr. Resident',
            Staff__c = staffResident.Id,
            Supervisor__c = docSenior.Id,
            Active__c = true
        );
        insert docResident;

        // 4. Create Patient record
        Patient__c pat = new Patient__c(
            Email__c = 'pat@testorg.com',
            Phone__c = '1234567890',
            Status__c = 'Active'
        );
        insert pat;

        Medical_Record__c mr;

        // Test Scenario 1: Resident doc cannot create directly in Final status
        System.runAs(uResident) {
            mr = new Medical_Record__c(
                Patient__c = pat.Id,
                Doctor__c = docResident.Id,
                Record_Status__c = 'Final',
                Clinical_Notes__c = 'Test notes'
            );
            try {
                insert mr;
                System.assert(false, 'Expected validation error when resident creates Final medical record.');
            } catch (DmlException e) {
                System.assert(e.getMessage().contains('cannot create medical records directly in Final status'), 'Actual message: ' + e.getMessage());
            }
        }

        // Test Scenario 2: Resident doc can save Draft
        System.runAs(uResident) {
            mr = new Medical_Record__c(
                Patient__c = pat.Id,
                Doctor__c = docResident.Id,
                Record_Status__c = 'Draft',
                Clinical_Notes__c = 'Test notes'
            );
            insert mr;
            
            // Resident doc can submit for approval (Pending Approval)
            mr.Record_Status__c = 'Pending Approval';
            update mr;
        }

        // Test Scenario 3: Non-supervisor doctor cannot approve (Finalize)
        System.runAs(uOther) {
            mr.Record_Status__c = 'Final';
            try {
                update mr;
                System.assert(false, 'Expected validation error when non-supervisor attempts to approve.');
            } catch (DmlException e) {
                System.assert(e.getMessage().contains('Only the supervisor doctor'), 'Actual message: ' + e.getMessage());
            }
        }

        // Test Scenario 4: Supervisor doctor can successfully approve (Finalize)
        System.runAs(uSenior) {
            mr.Record_Status__c = 'Final';
            update mr;
            
            Medical_Record__c updatedMr = [SELECT Record_Status__c FROM Medical_Record__c WHERE Id = :mr.Id];
            System.assertEquals('Final', updatedMr.Record_Status__c, 'Record should be finalized');
        }

        // Test Scenario 5: Once finalized, record is locked (cannot be edited)
        System.runAs(uSenior) {
            mr.Clinical_Notes__c = 'Attempt to modify notes';
            try {
                update mr;
                System.assert(false, 'Expected validation error modifying finalized record.');
            } catch (DmlException e) {
                System.assert(e.getMessage().contains('already been finalized and cannot be modified'), 'Actual message: ' + e.getMessage());
            }
        }
    }
}