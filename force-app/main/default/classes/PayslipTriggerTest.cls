@isTest
private class PayslipTriggerTest {
    @isTest
    static void testPayslipCreationConstraint() {
        // Create Staff
        Staff__c staff = new Staff__c(Name = 'Test Staff');
        insert staff;
        
        // Create Draft Payroll
        Payroll__c pDraft = new Payroll__c(
            Staff__c = staff.Id,
            Payroll_Month__c = 'January',
            Payroll_Year__c = 2026,
            Status__c = 'Draft'
        );
        insert pDraft;
        
        // Create Approved Payroll
        Payroll__c pApproved = new Payroll__c(
            Staff__c = staff.Id,
            Payroll_Month__c = 'January',
            Payroll_Year__c = 2026,
            Status__c = 'Approved'
        );
        insert pApproved;
        
        // Create Payslip on Draft Payroll (should fail)
        Payslip__c ps1 = new Payslip__c(
            Payroll__c = pDraft.Id,
            Status__c = 'Generated'
        );
        
        // Create Payslip on Approved Payroll (should succeed)
        Payslip__c ps2 = new Payslip__c(
            Payroll__c = pApproved.Id,
            Status__c = 'Generated'
        );
        
        Test.startTest();
        try {
            insert ps1;
            System.assert(false, 'Should have failed with validation error for Draft payroll.');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('Cannot create or update a payslip for a payroll that is not Approved or Paid'));
        }
        
        // This should succeed
        insert ps2;
        System.assertNotEquals(null, ps2.Id);
        
        // Update Payslip on Approved Payroll (should succeed)
        ps2.Status__c = 'Shared';
        update ps2;
        
        // Change payroll status to Draft
        pApproved.Status__c = 'Draft';
        update pApproved;
        
        // Updating the payslip now should fail because the payroll is in Draft status
        ps2.Status__c = 'Cancelled';
        try {
            update ps2;
            System.assert(false, 'Should have failed to update payslip when parent payroll is Draft.');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('Cannot create or update a payslip for a payroll that is not Approved or Paid'));
        }
        
        Test.stopTest();
    }
}