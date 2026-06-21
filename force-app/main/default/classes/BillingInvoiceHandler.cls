public with sharing class BillingInvoiceHandler {
    public class InvoiceRequest {
        @InvocableVariable(label='Admission Record Id' required=true)
        public Id admissionId;
    }

    public class InvoiceResult {
        @InvocableVariable(label='Invoice Created Successfully')
        public Boolean isSuccess;

        @InvocableVariable(label='Invoice Record Id')
        public Id invoiceId;

        @InvocableVariable(label='Total Invoice Amount')
        public Decimal totalAmount;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    @InvocableMethod(
        label='Generate Discharge Invoice'
        description='Creates or updates discharge invoice charges for admissions.'
        category='Billing'
    )
    public static List<InvoiceResult> generateInvoice(List<InvoiceRequest> requests) {
        List<InvoiceResult> results = initializeResults(requests);
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        Set<Id> admissionIds = new Set<Id>();
        Map<Id, List<Integer>> indexesByAdmission = new Map<Id, List<Integer>>();

        for (Integer index = 0; index < requests.size(); index++) {
            if (requests[index] == null || requests[index].admissionId == null) {
                results[index].isSuccess = false;
                results[index].errorMessage = 'Admission Id is required.';
                continue;
            }

            Id admissionId = requests[index].admissionId;
            admissionIds.add(admissionId);
            if (!indexesByAdmission.containsKey(admissionId)) {
                indexesByAdmission.put(admissionId, new List<Integer>());
            }
            indexesByAdmission.get(admissionId).add(index);
        }

        if (admissionIds.isEmpty()) {
            return results;
        }

        try {
            InvoiceBillingService.createAdmissionCharges(admissionIds);
            InvoiceBillingService.createDischargeCharges(admissionIds);

            for (Invoice__c invoice : [
                SELECT Id, Admission__c, Net_Payable__c, Total_Amount__c
                FROM Invoice__c
                WHERE Admission__c IN :admissionIds
            ]) {
                if (!indexesByAdmission.containsKey(invoice.Admission__c)) {
                    continue;
                }
                for (Integer resultIndex : indexesByAdmission.get(invoice.Admission__c)) {
                    results[resultIndex].isSuccess = true;
                    results[resultIndex].invoiceId = invoice.Id;
                    results[resultIndex].totalAmount = invoice.Net_Payable__c == null
                        ? invoice.Total_Amount__c
                        : invoice.Net_Payable__c;
                }
            }
        } catch (Exception ex) {
            for (InvoiceResult result : results) {
                if (result.isSuccess == null) {
                    result.isSuccess = false;
                    result.errorMessage = ex.getMessage();
                }
            }
            System.debug(LoggingLevel.ERROR, 'BillingInvoiceHandler failed: ' + ex.getMessage());
        }

        return results;
    }

    private static List<InvoiceResult> initializeResults(List<InvoiceRequest> requests) {
        List<InvoiceResult> results = new List<InvoiceResult>();
        if (requests == null) {
            return results;
        }
        for (Integer index = 0; index < requests.size(); index++) {
            results.add(new InvoiceResult());
        }
        return results;
    }
}