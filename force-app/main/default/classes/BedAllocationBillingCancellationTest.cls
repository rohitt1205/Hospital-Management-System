@isTest
private class BedAllocationBillingCancellationTest {
    @isTest
    static void cancelledAllocationRemovesChargeAndRecalculatesInvoice() {
        Patient__c patient = new Patient__c(
            Name = 'Cancelled Bed Billing Patient',
            Patient_Category__c = 'Normal'
        );
        insert patient;

        Invoice__c invoice = new Invoice__c(
            Patient__c = patient.Id,
            Patient_Category__c = 'Normal',
            Payment_Status__c = 'Unpaid',
            Status__c = 'Unpaid'
        );
        insert invoice;

        Bed_Allocation__c allocation = new Bed_Allocation__c(
            Patient__c = patient.Id,
            Start_Date_Time__c = System.now(),
            Status__c = 'Cancelled'
        );
        insert allocation;

        String sourceId = String.valueOf(allocation.Id);
        insert new Invoice_Line_Item__c(
            Invoice__c = invoice.Id,
            Charge_Type__c = 'Accommodation',
            Description__c = 'Cancelled accommodation',
            Service__c = 'Cancelled accommodation',
            Quantity__c = 1,
            Unit_Price__c = 200,
            Line_Total__c = 200,
            Line_Amount__c = 200,
            Unit_Rate__c = 200,
            Source_Record_Id__c = sourceId
        );
        InvoiceBillingService.calculateInvoiceTotals(new Set<Id>{ invoice.Id });

        Bed_Allocation__c oldAllocation = allocation.clone(true, true, false, false);
        oldAllocation.Status__c = 'Occupied';
        Map<Id, Bed_Allocation__c> oldMap = new Map<Id, Bed_Allocation__c>{ allocation.Id => oldAllocation };

        Test.startTest();
        InvoiceBillingService.handleBedAllocationsAfterSave(
            new List<Bed_Allocation__c>{ allocation },
            oldMap
        );
        Test.stopTest();

        Integer remainingCharges = [
            SELECT COUNT()
            FROM Invoice_Line_Item__c
            WHERE Invoice__c = :invoice.Id
            AND Source_Record_Id__c = :sourceId
            AND Charge_Type__c IN ('Accommodation', 'Bed')
        ];
        System.assertEquals(0, remainingCharges, 'Cancelled allocation charges must be deleted.');

        invoice = [
            SELECT Gross_Amount__c, Net_Payable__c
            FROM Invoice__c
            WHERE Id = :invoice.Id
        ];
        System.assertEquals(0, invoice.Gross_Amount__c);
        System.assertEquals(0, invoice.Net_Payable__c);
    }
}