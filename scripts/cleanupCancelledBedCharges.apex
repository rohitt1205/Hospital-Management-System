Set<String> cancelledAllocationIds = new Set<String>();
for (Bed_Allocation__c allocation : [
    SELECT Id
    FROM Bed_Allocation__c
    WHERE Status__c = 'Cancelled'
]) {
    cancelledAllocationIds.add(String.valueOf(allocation.Id));
}

List<Invoice_Line_Item__c> staleCharges = cancelledAllocationIds.isEmpty()
    ? new List<Invoice_Line_Item__c>()
    : [
        SELECT Id, Invoice__c
        FROM Invoice_Line_Item__c
        WHERE Source_Record_Id__c IN :cancelledAllocationIds
        AND Charge_Type__c IN ('Accommodation', 'Bed')
    ];

Set<Id> affectedInvoiceIds = new Set<Id>();
for (Invoice_Line_Item__c charge : staleCharges) {
    if (charge.Invoice__c != null) {
        affectedInvoiceIds.add(charge.Invoice__c);
    }
}

if (!staleCharges.isEmpty()) {
    delete staleCharges;
}
if (!affectedInvoiceIds.isEmpty()) {
    InvoiceBillingService.calculateInvoiceTotals(affectedInvoiceIds);
}

System.debug(LoggingLevel.ERROR,
    'Cancelled bed charge cleanup: deleted=' + staleCharges.size()
    + ', invoicesRecalculated=' + affectedInvoiceIds.size());
