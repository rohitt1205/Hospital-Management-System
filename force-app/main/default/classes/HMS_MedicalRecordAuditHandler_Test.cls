/**
 * HMS_MedicalRecordAuditHandler_Test
 * Tests: HMS_MedicalRecordAuditHandler (via HMS_MedicalRecordAuditTrigger)
 * Coverage target: 90%+
 */
@isTest
private class HMS_MedicalRecordAuditHandler_Test {

    @isTest
    static void testMedicalRecordAuditAccess() {
        // 1. Create standard profile user for doctor, other user, admin user
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        Profile adminProfile = [SELECT Id FROM Profile WHERE Name='System Administrator' LIMIT 1];
        
        String rand1 = String.valueOf(Crypto.getRandomInteger());
        User uDoc = new User(
            Alias = 'docuser', Email='docuser@testorg.com', 
            EmailEncodingKey='UTF-8', LastName='DoctorUser', LanguageLocaleKey='en_US', 
            LocaleSidKey='en_US', ProfileId = standardProfile.Id, 
            TimeZoneSidKey='America/Los_Angeles', UserName='docuser_' + rand1 + '@testorg.com'
        );
        
        String rand2 = String.valueOf(Crypto.getRandomInteger());
        User uOther = new User(
            Alias = 'othuser', Email='othuser@testorg.com', 
            EmailEncodingKey='UTF-8', LastName='OtherUser', LanguageLocaleKey='en_US', 
            LocaleSidKey='en_US', ProfileId = standardProfile.Id, 
            TimeZoneSidKey='America/Los_Angeles', UserName='othuser_' + rand2 + '@testorg.com'
        );

        String rand3 = String.valueOf(Crypto.getRandomInteger());
        User uAdmin = new User(
            Alias = 'admuser', Email='admuser@testorg.com', 
            EmailEncodingKey='UTF-8', LastName='AdminUser', LanguageLocaleKey='en_US', 
            LocaleSidKey='en_US', ProfileId = adminProfile.Id, 
            TimeZoneSidKey='America/Los_Angeles', UserName='admuser_' + rand3 + '@testorg.com'
        );

        // Insert setup objects inside runAs to avoid Mixed DML Exception
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new List<User>{uDoc, uOther, uAdmin};

            PermissionSet hospitalStaffPS = [
                SELECT Id FROM PermissionSet WHERE Name = 'HMS_Hospital_Staff' LIMIT 1
            ];
            PermissionSet hmsAdminPS = [
                SELECT Id FROM PermissionSet WHERE Name = 'HMS_Admin' LIMIT 1
            ];
            List<PermissionSetAssignment> psas = new List<PermissionSetAssignment>();
            psas.add(new PermissionSetAssignment(AssigneeId = uDoc.Id, PermissionSetId = hospitalStaffPS.Id));
            psas.add(new PermissionSetAssignment(AssigneeId = uOther.Id, PermissionSetId = hospitalStaffPS.Id));
            psas.add(new PermissionSetAssignment(AssigneeId = uAdmin.Id, PermissionSetId = hmsAdminPS.Id));
            insert psas;
        }

        // 2. Create Staff records
        Staff__c staffDoc = new Staff__c(
            Salesforce_User__c = uDoc.Id,
            Staff_Role__c = 'Doctor',
            Status__c = 'Active'
        );
        Staff__c staffOther = new Staff__c(
            Salesforce_User__c = uOther.Id,
            Staff_Role__c = 'Doctor',
            Status__c = 'Active'
        );
        insert new List<Staff__c>{staffDoc, staffOther};

        // 3. Create Doctor records
        Doctor__c doc = new Doctor__c(
            Name = 'Dr. Assigned',
            Staff__c = staffDoc.Id,
            Active__c = true
        );
        Doctor__c docOther = new Doctor__c(
            Name = 'Dr. Other',
            Staff__c = staffOther.Id,
            Active__c = true
        );
        insert new List<Doctor__c>{doc, docOther};

        // 4. Create Patient record
        Patient__c pat = new Patient__c(
            Email__c = 'pat@testorg.com',
            Phone__c = '1234567890',
            Status__c = 'Active'
        );
        insert pat;

        Medical_Record__c mr;

        // Test Scenario 1: Insert medical record (after insert trigger fires)
        System.runAs(uDoc) {
            mr = new Medical_Record__c(
                Patient__c = pat.Id,
                Doctor__c = doc.Id,
                Record_Status__c = 'Draft',
                Clinical_Notes__c = 'Initial Notes'
            );
            Test.startTest();
            insert mr;
            Test.stopTest();
            
            System.assertNotEquals(null, mr.Id, 'Medical record should be created successfully.');
        }

        // Test Scenario 2: Assigned doctor can update
        System.runAs(uDoc) {
            mr.Clinical_Notes__c = 'Updated Notes by Doctor';
            update mr;
            
            Medical_Record__c updatedMr = [SELECT Clinical_Notes__c FROM Medical_Record__c WHERE Id = :mr.Id];
            System.assertEquals('Updated Notes by Doctor', updatedMr.Clinical_Notes__c);
        }

        // Test Scenario 3: Non-assigned user without special permission is blocked
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new Medical_Record__Share(
                ParentId       = mr.Id,
                UserOrGroupId  = uOther.Id,
                AccessLevel    = 'Edit',
                RowCause       = 'Manual'
            );
        }

        System.runAs(uOther) {
            mr.Clinical_Notes__c = 'Attempted update by other doctor';

            try {
                update mr;
                System.assert(false, 'Expected Access Denied error.');
            } catch (DmlException e) {
                System.assert(
                    e.getMessage().contains('Access Denied: Only the assigned doctor'),
                    'Actual error: ' + e.getMessage()
                );
            }
        }

        // Test Scenario 4: Admin user can bypass and update
        System.runAs(uAdmin) {
            mr.Clinical_Notes__c = 'Updated by Admin';
            update mr;
            
            Medical_Record__c updatedMr = [SELECT Clinical_Notes__c FROM Medical_Record__c WHERE Id = :mr.Id];
            System.assertEquals('Updated by Admin', updatedMr.Clinical_Notes__c);
        }

        // Test Scenario 5: User with HMS_Audit_Logger permission set can bypass and update
        System.runAs(new User(Id = UserInfo.getUserId())) {
            PermissionSet auditLoggerPS = [SELECT Id FROM PermissionSet WHERE Name = 'HMS_Audit_Logger' LIMIT 1];
            insert new PermissionSetAssignment(AssigneeId = uOther.Id, PermissionSetId = auditLoggerPS.Id);
        }

        System.runAs(uOther) {
            mr.Clinical_Notes__c = 'Updated by other doctor with HMS_Audit_Logger';
            update mr;

            Medical_Record__c updatedMr = [SELECT Clinical_Notes__c FROM Medical_Record__c WHERE Id = :mr.Id];
            System.assertEquals('Updated by other doctor with HMS_Audit_Logger', updatedMr.Clinical_Notes__c);
        }

        // Test Scenario 6: Medical record with null doctor is blocked by handler
        System.runAs(uDoc) {
            Medical_Record__c nullDoctorAttempt = new Medical_Record__c(
                Id                = mr.Id,
                Patient__c        = mr.Patient__c,
                Doctor__c         = null,
                Clinical_Notes__c = 'Attempt to clear doctor'
            );
            HMS_MedicalRecordAuditHandler.handleBeforeUpdate(
                new List<Medical_Record__c>{ nullDoctorAttempt },
                new Map<Id, Medical_Record__c>{ mr.Id => mr }
            );
            System.assertEquals(true, nullDoctorAttempt.hasErrors(),
                'Handler should block updates that remove the assigned doctor');
        }
    }
}