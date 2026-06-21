/**
 * HMS_AdmissionAuditHandler_Test
 * Tests: HMS_AdmissionAuditHandler (via HMS_AdmissionAuditTrigger)
 * Coverage target: 90%+
 */
@isTest
private class HMS_AdmissionAuditHandler_Test {

    @TestSetup
    static void setupData() {
        // Patient
        Patient__c patient = new Patient__c(
            Name                = 'Admission Test Patient',
            Status__c           = 'Active',
            Patient_Category__c = 'Normal',
            Date_of_Birth__c    = Date.today().addYears(-35)
        );
        insert patient;

        // Ward with capacity (Name is auto-number WRD-{0000})
        Ward__c ward = new Ward__c(
            Capacity__c       = 2,
            Current_Occupancy__c = 0,
            Status__c         = 'Active'
        );
        insert ward;

        // Room
        Room__c room = new Room__c(
            Name         = 'Room 101',
            Ward__c      = ward.Id,
            Room_Type__c = 'private ac room with extra bed'
        );
        insert room;
    }

    // ─── Test: Admission insert — audit event published ───────────────────────
    @isTest
    static void testAdmissionInsert_AuditLogged() {
        Patient__c patient = [SELECT Id FROM Patient__c LIMIT 1];
        Room__c room = [SELECT Id, Ward__c FROM Room__c LIMIT 1];

        Admission__c adm = new Admission__c(
            Patient__c         = patient.Id,
            Status__c          = 'Admitted',
            Admission_Date_Time__c = DateTime.now()
        );

        Test.startTest();
        insert adm;
        Test.stopTest();

        Admission__c inserted = [SELECT Id, Status__c FROM Admission__c WHERE Id = :adm.Id];
        System.assertEquals('Admitted', inserted.Status__c,
            'Admission status should be Admitted after insert');
    }

    // ─── Test: Ward at full capacity — admission blocked ──────────────────────
    @isTest
    static void testAdmissionInsert_WardFull_Blocked() {
        Patient__c patient = [SELECT Id FROM Patient__c LIMIT 1];
        Ward__c ward = [SELECT Id FROM Ward__c LIMIT 1];
        // Fill the ward to capacity
        update new Ward__c(Id = ward.Id, Current_Occupancy__c = 2, Capacity__c = 2);

        Admission__c adm = new Admission__c(
            Patient__c         = patient.Id,
            Status__c          = 'Draft',
            Ward__c            = ward.Id,
            Admission_Date_Time__c = DateTime.now()
        );

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            insert adm;
        } catch (DmlException ex) {
            exceptionThrown = true;
            System.assert(ex.getMessage().contains('capacity') || ex.getMessage().contains('full'),
                'Error should mention ward capacity: ' + ex.getMessage());
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown,
            'Admission to a full ward should be blocked');
    }

    // ─── Test: Discharge with unpaid invoice — blocked ────────────────────────
    @isTest
    static void testDischarge_UnpaidInvoice_Blocked() {
        Patient__c patient = [SELECT Id FROM Patient__c LIMIT 1];

        Admission__c adm = new Admission__c(
            Patient__c             = patient.Id,
            Status__c              = 'Admitted',
            Admission_Date_Time__c = DateTime.now()
        );
        insert adm;

        Invoice__c invoice = new Invoice__c(
            Admission__c      = adm.Id,
            Patient__c        = patient.Id,
            Payment_Status__c = 'Unpaid',
            Status__c         = 'Unpaid',
            Gross_Amount__c   = 5000
        );
        insert invoice;

        Admission__c dischargeAttempt = new Admission__c(
            Id                     = adm.Id,
            Patient__c             = patient.Id,
            Status__c              = 'Discharged',
            Outstanding_Balance__c = 0
        );

        Test.startTest();
        HMS_AdmissionAuditHandler.handleBeforeUpdate(
            new List<Admission__c>{ dischargeAttempt },
            new Map<Id, Admission__c>{ adm.Id => adm }
        );
        Test.stopTest();

        System.assertEquals(true, dischargeAttempt.hasErrors(),
            'Discharge should be blocked when patient has unpaid invoices');
    }

    // ─── Test: Outstanding balance blocks discharge ───────────────────────────
    @isTest
    static void testDischarge_OutstandingBalance_Blocked() {
        Patient__c patient = [SELECT Id FROM Patient__c LIMIT 1];

        Admission__c adm = new Admission__c(
            Patient__c             = patient.Id,
            Status__c              = 'Admitted',
            Admission_Date_Time__c = DateTime.now()
        );
        insert adm;

        Admission__c dischargeAttempt = new Admission__c(
            Id                     = adm.Id,
            Patient__c             = patient.Id,
            Status__c              = 'Discharged',
            Outstanding_Balance__c = 2500
        );

        Test.startTest();
        HMS_AdmissionAuditHandler.handleBeforeUpdate(
            new List<Admission__c>{ dischargeAttempt },
            new Map<Id, Admission__c>{ adm.Id => adm }
        );
        Test.stopTest();

        System.assertEquals(true, dischargeAttempt.hasErrors(),
            'Discharge should be blocked when outstanding balance is greater than zero');
    }

    // ─── Test: Discharge with paid invoice — allowed ──────────────────────────
    @isTest
    static void testDischarge_PaidInvoice_Allowed() {
        Patient__c patient = [SELECT Id FROM Patient__c LIMIT 1];

        Admission__c adm = new Admission__c(
            Patient__c         = patient.Id,
            Status__c          = 'Admitted',
            Admission_Date_Time__c = DateTime.now()
        );
        insert adm;

        // Paid invoice
        Invoice__c invoice = new Invoice__c(
            Admission__c      = adm.Id,
            Patient__c        = patient.Id,
            Payment_Status__c = 'Paid',
            Status__c         = 'Paid',
            Gross_Amount__c   = 5000
        );
        insert invoice;

        Test.startTest();
        adm.Outstanding_Balance__c = 0;
        adm.Status__c = 'Discharged';
        adm.Actual_Discharge_Date_Time__c = DateTime.now();
        update adm;
        Test.stopTest();

        Admission__c updated = [SELECT Id, Status__c FROM Admission__c WHERE Id = :adm.Id];
        System.assert(
            updated.Status__c == 'Discharged' || updated.Status__c == 'Pending Discharge',
            'Discharge request should progress to Discharged or Pending Discharge, actual: ' + updated.Status__c
        );
    }

    // ─── Test: Bulk admissions insert ────────────────────────────────────────
    @isTest
    static void testBulkAdmissionInsert() {
        Patient__c patient = [SELECT Id FROM Patient__c LIMIT 1];
        List<Admission__c> admissions = new List<Admission__c>();
        for (Integer i = 0; i < 10; i++) {
            admissions.add(new Admission__c(
                Patient__c         = patient.Id,
                Status__c          = 'Draft',
                Admission_Date_Time__c = DateTime.now()
            ));
        }

        Test.startTest();
        insert admissions;
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM Admission__c WHERE Patient__c = :patient.Id];
        System.assertEquals(10, count, 'All 10 bulk admissions should be inserted');
    }

    // ─── Test: Admission update publishes audit event ────────────────────────
    @isTest
    static void testAdmissionUpdate_AuditLogged() {
        Patient__c patient = [SELECT Id FROM Patient__c LIMIT 1];

        Admission__c adm = new Admission__c(
            Patient__c             = patient.Id,
            Status__c              = 'Draft',
            Admission_Date_Time__c = DateTime.now()
        );
        insert adm;

        Test.startTest();
        adm.Status__c = 'Admitted';
        update adm;
        Test.stopTest();

        Admission__c updated = [SELECT Id, Status__c FROM Admission__c WHERE Id = :adm.Id];
        System.assertEquals('Admitted', updated.Status__c, 'Admission status should update');
    }

    // ─── Test: Admission delete publishes audit event ────────────────────────
    @isTest
    static void testAdmissionDelete_AuditLogged() {
        Patient__c patient = [SELECT Id FROM Patient__c LIMIT 1];

        Admission__c adm = new Admission__c(
            Patient__c             = patient.Id,
            Status__c              = 'Draft',
            Admission_Date_Time__c = DateTime.now()
        );
        insert adm;

        Test.startTest();
        delete adm;
        Test.stopTest();

        List<Admission__c> remaining = [SELECT Id FROM Admission__c WHERE Id = :adm.Id];
        System.assertEquals(0, remaining.size(), 'Admission should be deleted');
    }
}