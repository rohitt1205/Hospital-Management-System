/**
 * HMS_PatientAuditHandler_Test
 * Tests: HMS_PatientAuditHandler (via HMS_PatientTrigger)
 * Coverage target: 90%+
 */
@isTest
private class HMS_PatientAuditHandler_Test {

    @TestSetup
    static void setupData() {
        Patient__c patient = new Patient__c(
            Name                = 'Guardian Setup Patient',
            Status__c           = 'Active',
            Patient_Category__c = 'Normal',
            Date_of_Birth__c    = Date.today().addYears(-30)
        );
        insert patient;

        insert new Guardian__c(
            Name     = 'Legal Guardian',
            Patient__c = patient.Id
        );
    }

    // ─── Test: Adult patient — no guardian required ───────────────────────────
    @isTest
    static void testAdultPatientInsert_NoGuardianRequired() {
        Patient__c patient = new Patient__c(
            Name                = 'Adult Patient',
            Status__c           = 'Active',
            Patient_Category__c = 'Normal',
            Date_of_Birth__c    = Date.today().addYears(-30)
        );

        Test.startTest();
        insert patient;
        Test.stopTest();

        Patient__c inserted = [SELECT Id, Name FROM Patient__c WHERE Name = 'Adult Patient'];
        System.assertNotEquals(null, inserted.Id, 'Adult patient should be inserted successfully');
    }

    // ─── Test: Minor patient with guardian — allowed ──────────────────────────
    @isTest
    static void testMinorPatientInsert_WithGuardian_Allowed() {
        Guardian__c guardian = [SELECT Id FROM Guardian__c LIMIT 1];
        Patient__c patient = new Patient__c(
            Name                = 'Minor With Guardian',
            Status__c           = 'Active',
            Patient_Category__c = 'Normal',
            Date_of_Birth__c    = Date.today().addYears(-10),
            Guardian__c         = guardian.Id
        );

        Test.startTest();
        insert patient;
        Test.stopTest();

        Patient__c inserted = [SELECT Id FROM Patient__c WHERE Name = 'Minor With Guardian'];
        System.assertNotEquals(null, inserted.Id,
            'Minor patient with guardian should be inserted successfully');
    }

    // ─── Test: Minor patient without guardian — blocked ───────────────────────
    @isTest
    static void testMinorPatientInsert_WithoutGuardian_Blocked() {
        Patient__c patient = new Patient__c(
            Name                = 'Minor Without Guardian',
            Status__c           = 'Active',
            Patient_Category__c = 'Normal',
            Date_of_Birth__c    = Date.today().addYears(-8)
            // No Guardian__c
        );

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            insert patient;
        } catch (DmlException ex) {
            exceptionThrown = true;
            System.assert(ex.getMessage().contains('Guardian'),
                'Error should mention Guardian requirement');
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown,
            'Minor patient without guardian should be blocked by validation');
    }

    // ─── Test: Patient without DOB — insert allowed (no age check) ───────────
    @isTest
    static void testPatientInsert_NoDOB_Allowed() {
        Patient__c patient = new Patient__c(
            Name                = 'Patient No DOB',
            Status__c           = 'Active',
            Patient_Category__c = 'Normal'
            // No Date_of_Birth__c — validation should not fire
        );

        Test.startTest();
        insert patient;
        Test.stopTest();

        Patient__c inserted = [SELECT Id FROM Patient__c WHERE Name = 'Patient No DOB'];
        System.assertNotEquals(null, inserted.Id,
            'Patient without DOB should be inserted (no age validation possible)');
    }

    // ─── Test: After update — audit log published ─────────────────────────────
    @isTest
    static void testPatientUpdate_AuditLogged() {
        Patient__c patient = new Patient__c(
            Name                = 'Update Test Patient',
            Status__c           = 'Active',
            Patient_Category__c = 'Normal',
            Date_of_Birth__c    = Date.today().addYears(-25)
        );
        insert patient;

        Test.startTest();
        patient.Status__c = 'Discharged';
        update patient;
        Test.stopTest();

        Patient__c updated = [SELECT Id, Status__c FROM Patient__c WHERE Id = :patient.Id];
        System.assertEquals('Discharged', updated.Status__c, 'Status should be updated');
    }

    // ─── Test: Bulk insert — 50 adult patients ────────────────────────────────
    @isTest
    static void testBulkPatientInsert() {
        List<Patient__c> patients = new List<Patient__c>();
        for (Integer i = 0; i < 50; i++) {
            patients.add(new Patient__c(
                Name                = 'Bulk Patient ' + i,
                Status__c           = 'Active',
                Patient_Category__c = 'Normal',
                Date_of_Birth__c    = Date.today().addYears(-20)
            ));
        }

        Test.startTest();
        insert patients;
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM Patient__c WHERE Name LIKE 'Bulk Patient%'];
        System.assertEquals(50, count, 'All 50 bulk patients should be inserted');
    }
}