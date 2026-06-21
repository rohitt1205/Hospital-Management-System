public with sharing class InvoiceLineItemService {
    public static Set<Id> upsertCharges(Map<Id, Invoice__c> invoiceBySource, Map<Id, BillingCharge> chargeBySource) {
        Set<Id> invoiceIds = new Set<Id>();
        List<Invoice_Line_Item__c> requestedItems = new List<Invoice_Line_Item__c>();

        for (Id sourceId : chargeBySource.keySet()) {
            Invoice__c invoice = invoiceBySource.get(sourceId);
            BillingCharge charge = chargeBySource.get(sourceId);
            if (invoice == null || invoice.Id == null || charge == null || charge.sourceRecordId == null) {
                continue;
            }

            invoiceIds.add(invoice.Id);
            Decimal amount = charge.amount();
            requestedItems.add(new Invoice_Line_Item__c(
                Invoice__c = invoice.Id,
                Charge_Type__c = charge.chargeType,
                Source_Record_Id__c = String.valueOf(charge.sourceRecordId),
                Line_Item_Key__c = BillingUtil.lineItemKey(invoice.Id, charge.chargeType, charge.sourceRecordId),
                Description__c = charge.description,
                Service__c = charge.description,
                Quantity__c = charge.quantity,
                Unit_Rate__c = charge.unitRate,
                Amount__c = amount,
                Line_Amount__c = amount,
                Non_Billable__c = charge.nonBillable
            ));
        }

        if (requestedItems.isEmpty()) {
            return invoiceIds;
        }

        Map<String, Invoice_Line_Item__c> existingByKey = new Map<String, Invoice_Line_Item__c>();
        for (Invoice_Line_Item__c existing : [
            SELECT Id, Line_Item_Key__c, Invoice__c, Charge_Type__c, Source_Record_Id__c,
                   Description__c, Service__c, Quantity__c, Unit_Rate__c, Amount__c, Line_Amount__c,
                   Non_Billable__c
            FROM Invoice_Line_Item__c
            WHERE Invoice__c IN :invoiceIds
        ]) {
            String key = existing.Line_Item_Key__c;
            if (String.isBlank(key)) {
                key = String.valueOf(existing.Invoice__c) + '|' + existing.Charge_Type__c + '|' + existing.Source_Record_Id__c;
            }
            existingByKey.put(key, existing);
        }

        List<Invoice_Line_Item__c> inserts = new List<Invoice_Line_Item__c>();
        List<Invoice_Line_Item__c> updates = new List<Invoice_Line_Item__c>();

        for (Invoice_Line_Item__c requested : requestedItems) {
            Invoice_Line_Item__c existing = existingByKey.get(requested.Line_Item_Key__c);
            if (existing == null) {
                inserts.add(requested);
                continue;
            }

            updates.add(new Invoice_Line_Item__c(
                Id = existing.Id,
                Description__c = requested.Description__c,
                Service__c = requested.Service__c,
                Quantity__c = requested.Quantity__c,
                Unit_Rate__c = requested.Unit_Rate__c,
                Amount__c = requested.Amount__c,
                Line_Amount__c = requested.Line_Amount__c,
                Non_Billable__c = requested.Non_Billable__c,
                Line_Item_Key__c = String.isBlank(existing.Line_Item_Key__c) ? requested.Line_Item_Key__c : existing.Line_Item_Key__c
            ));
        }

        if (!inserts.isEmpty()) {
            insert inserts;
        }
        if (!updates.isEmpty()) {
            update updates;
        }

        return invoiceIds;
    }
}