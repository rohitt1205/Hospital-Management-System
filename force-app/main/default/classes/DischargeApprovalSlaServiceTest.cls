@IsTest
public class DischargeApprovalSlaServiceTest {
    @IsTest
    static void testDischargeEscalation() {
        Patient__c patient = new Patient__c(
            Name = 'SLA Patient',
            Patient_Category__c = 'Normal',
            Phone__c = '9876543210'
        );
        insert patient;

        Admission__c admission = new Admission__c(
            Patient__c = patient.Id,
            Status__c = 'Draft',
            Phone__c = '9876543210'
        );
        insert admission;

        // Pay invoices to allow transition to Discharged
        List<Invoice__c> invoices = [SELECT Id, Payment_Status__c FROM Invoice__c WHERE Admission__c = :admission.Id];
        for (Invoice__c inv : invoices) {
            inv.Payment_Status__c = 'Paid';
        }
        if (!invoices.isEmpty()) {
            update invoices;
        }

        // Transition admission to Discharged, Pending Approval
        admission.Status__c = 'Discharged';
        admission.Approval_Status__c = 'Pending Approval';
        update admission;

        // Set the discharge date to 10 minutes ago to simulate overdue
        Datetime testDate = System.now().addMinutes(-10);
        admission.Actual_Discharge_Date_Time__c = testDate;
        update admission;

        Test.startTest();
        Integer escalatedCount = DischargeApprovalSlaService.escalateOverdueDischarges();
        System.assertEquals(1, escalatedCount, 'One admission should be escalated');

        List<Task> createdTasks = [
            SELECT Id, Subject, WhatId 
            FROM Task 
            WHERE WhatId = :admission.Id 
            AND Subject LIKE 'Discharge approval pending:%'
        ];
        System.assertEquals(1, createdTasks.size(), 'An escalation task should have been created');
        
        Integer secondCount = DischargeApprovalSlaService.escalateOverdueDischarges();
        System.assertEquals(0, secondCount, 'Should not escalate again');

        Test.stopTest();
    }

    @IsTest
    static void testDischargeScheduler() {
        Test.startTest();
        DischargeApprovalSlaScheduler scheduler = new DischargeApprovalSlaScheduler();
        String cronStr = '0 0 * * * ?';
        System.schedule('Test Discharge SLA Scheduler', cronStr, scheduler);
        Test.stopTest();
        
        List<CronTrigger> jobs = [SELECT Id, CronJobDetail.Name FROM CronTrigger WHERE CronJobDetail.Name = 'Test Discharge SLA Scheduler'];
        System.assertEquals(1, jobs.size());
    }
}