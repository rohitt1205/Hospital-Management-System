public with sharing class BillingCalculatorService {
    public static void recalculate(Set<Id> invoiceIds) {
        if (invoiceIds == null || invoiceIds.isEmpty()) {
            return;
        }

        Map<Id, Invoice__c> invoices = new Map<Id, Invoice__c>([
            SELECT Id, Insurance_Covered_Amount__c, Discount_Amount__c
            FROM Invoice__c
            WHERE Id IN :invoiceIds
        ]);

        Map<Id, Decimal> grossByInvoice = new Map<Id, Decimal>();
        Map<Id, Decimal> nonBillableByInvoice = new Map<Id, Decimal>();

        for (Invoice_Line_Item__c item : [
            SELECT Invoice__c, Amount__c, Line_Amount__c, Non_Billable__c
            FROM Invoice_Line_Item__c
            WHERE Invoice__c IN :invoiceIds
        ]) {
            Decimal amount = item.Line_Amount__c != null ? item.Line_Amount__c : BillingUtil.zeroIfNull(item.Amount__c);
            grossByInvoice.put(item.Invoice__c, BillingUtil.zeroIfNull(grossByInvoice.get(item.Invoice__c)) + amount);
            if (item.Non_Billable__c == true) {
                nonBillableByInvoice.put(item.Invoice__c, BillingUtil.zeroIfNull(nonBillableByInvoice.get(item.Invoice__c)) + amount);
            }
        }

        List<Invoice__c> updates = new List<Invoice__c>();
        for (Invoice__c invoice : invoices.values()) {
            Decimal gross = BillingUtil.zeroIfNull(grossByInvoice.get(invoice.Id));
            Decimal insurance = BillingUtil.zeroIfNull(invoice.Insurance_Covered_Amount__c);
            Decimal discount = BillingUtil.zeroIfNull(invoice.Discount_Amount__c);
            Decimal nonBillable = BillingUtil.zeroIfNull(nonBillableByInvoice.get(invoice.Id));
            Decimal netPayable = gross - insurance - discount - nonBillable;
            if (netPayable < 0) {
                netPayable = 0;
            }

            updates.add(new Invoice__c(
                Id = invoice.Id,
                Gross_Amount__c = gross,
                Non_Billable_Deduction__c = nonBillable,
                Total_Amount__c = netPayable,
                Net_Payable__c = netPayable
            ));
        }

        if (!updates.isEmpty()) {
            update updates;
        }
    }
}