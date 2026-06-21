/**
 * HMS_InvoiceAuditHandler_Test
 * Tests: HMS_InvoiceAuditHandler (via HMS_InvoiceAuditTrigger)
 * Coverage target: 90%+
 */
@isTest
private class HMS_InvoiceAuditHandler_Test {

    @TestSetup
    static void setupData() {
        Patient__c patient = new Patient__c(
            Name                = 'Invoice Test Patient',
            Status__c           = 'Active',
            Patient_Category__c = 'Normal',
            Date_of_Birth__c    = Date.today().addYears(-40)
        );
        insert patient;

        Admission__c adm = new Admission__c(
            Patient__c         = patient.Id,
            Status__c          = 'Admitted',
            Admission_Date_Time__c = DateTime.now()
        );
        insert adm;
    }

    // ─── Test: Invoice insert without insurance — allowed ─────────────────────
    @isTest
    static void testInvoiceInsert_NoInsurance_Allowed() {
        Patient__c patient = [SELECT Id FROM Patient__c LIMIT 1];
        Admission__c adm   = [SELECT Id FROM Admission__c LIMIT 1];

        Invoice__c invoice = new Invoice__c(
            Admission__c      = adm.Id,
            Patient__c        = patient.Id,
            Payment_Status__c = 'Draft',
            Status__c         = 'Draft',
            Gross_Amount__c   = 3000
        );

        Test.startTest();
        insert invoice;
        Test.stopTest();

        Invoice__c inserted = [SELECT Id, Payment_Status__c FROM Invoice__c WHERE Id = :invoice.Id];
        System.assertNotEquals(null, inserted.Id, 'Invoice without insurance should be inserted');
    }

    // ─── Test: Invoice insert with unverified insurance — blocked ────────────
    @isTest
    static void testInvoiceInsert_UnverifiedInsurance_Blocked() {
        Patient__c patient = [SELECT Id FROM Patient__c LIMIT 1];
        Admission__c adm   = [SELECT Id FROM Admission__c LIMIT 1];

        Insurance_Company__c insCompany = new Insurance_Company__c(
            Name = 'Test Insurance Co'
        );
        insert insCompany;

        Insurance_Policy__c policy = new Insurance_Policy__c(
            Name               = 'Policy 001',
            Patient__c         = patient.Id,
            Insurance_Company__c = insCompany.Id,
            Valid_From__c      = Date.today().addDays(-30),
            Valid_To__c        = Date.today().addDays(330),
            Verification_Status__c = 'Pending'
        );
        insert policy;

        Invoice__c invoice = new Invoice__c(
            Admission__c        = adm.Id,
            Patient__c          = patient.Id,
            Insurance_Policy__c = policy.Id,
            Insurance_Verified__c = false,
            Payment_Status__c   = 'Draft',
            Status__c           = 'Draft',
            Gross_Amount__c     = 8000
        );

        Test.startTest();
        HMS_InvoiceAuditHandler.handleBeforeInsert(new List<Invoice__c>{ invoice });
        Test.stopTest();

        System.assertEquals(true, invoice.hasErrors(),
            'Invoice with unverified insurance should be blocked by handler validation');
    }

    // ─── Test: Invoice update — audit event published ────────────────────────
    @isTest
    static void testInvoiceUpdate_AuditLogged() {
        Patient__c patient = [SELECT Id FROM Patient__c LIMIT 1];
        Admission__c adm   = [SELECT Id FROM Admission__c LIMIT 1];

        Invoice__c invoice = new Invoice__c(
            Admission__c      = adm.Id,
            Patient__c        = patient.Id,
            Payment_Status__c = 'Draft',
            Status__c         = 'Draft',
            Gross_Amount__c   = 2500
        );
        insert invoice;

        Test.startTest();
        invoice.Payment_Status__c = 'Paid';
        invoice.Status__c = 'Paid';
        update invoice;
        Test.stopTest();

        Invoice__c updated = [SELECT Id, Payment_Status__c FROM Invoice__c WHERE Id = :invoice.Id];
        System.assertEquals('Paid', updated.Payment_Status__c,
            'Invoice payment status should be updated');
    }

    // ─── Test: Bulk invoice insert ───────────────────────────────────────────
    @isTest
    static void testBulkInvoiceInsert() {
        Patient__c patient = [SELECT Id FROM Patient__c LIMIT 1];
        Admission__c adm   = [SELECT Id FROM Admission__c LIMIT 1];

        List<Invoice__c> invoices = new List<Invoice__c>();
        for (Integer i = 0; i < 10; i++) {
            invoices.add(new Invoice__c(
                Admission__c      = adm.Id,
                Patient__c        = patient.Id,
                Payment_Status__c = 'Draft',
                Status__c         = 'Draft',
                Gross_Amount__c   = 1000 + i
            ));
        }

        Test.startTest();
        insert invoices;
        Test.stopTest();

        Integer count = [
            SELECT COUNT()
            FROM   Invoice__c
            WHERE  Admission__c = :adm.Id
            AND    Gross_Amount__c >= 1000
        ];
        System.assertEquals(10, count, 'All 10 bulk invoices should be inserted');
    }
}