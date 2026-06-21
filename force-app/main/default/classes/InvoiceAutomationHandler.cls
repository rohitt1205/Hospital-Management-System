public without sharing class InvoiceAutomationHandler {
    public static void beforeSave(List<Invoice__c> invoices) {
        beforeSave(invoices, null, true, false);
    }

    public static void beforeSave(List<Invoice__c> invoices, Map<Id, Invoice__c> oldMap, Boolean isInsert, Boolean isUpdate) {
        Set<Id> policyIds = new Set<Id>();
        Set<Id> admissionIds = new Set<Id>();
        for (Invoice__c invoice : invoices) {
            if (isUpdate && oldMap != null && oldMap.containsKey(invoice.Id)) {
                if (invoice.isSet('Invoice_Date__c')) {
                    Date oldInvoiceDate = oldMap.get(invoice.Id).Invoice_Date__c;
                    if (oldInvoiceDate != invoice.Invoice_Date__c) {
                        invoice.Invoice_Date__c.addError('Invoice date is system generated and cannot be changed.');
                    }
                }
            }

            if (invoice.Insurance_Policy__c != null) {
                policyIds.add(invoice.Insurance_Policy__c);
            }
            if (invoice.Admission__c != null) {
                admissionIds.add(invoice.Admission__c);
            }
        }
        
        Map<Id, Admission__c> admissions = admissionIds.isEmpty()
            ? new Map<Id, Admission__c>()
            : new Map<Id, Admission__c>([
                SELECT Id, Patient__c, Insurance_Policy__c, Insurance_Verified__c, Patient__r.Patient_Category__c
                FROM Admission__c
                WHERE Id IN :admissionIds
                WITH SYSTEM_MODE
            ]);
            
        for (Invoice__c invoice : invoices) {
            if (isInsert) {
                invoice.Invoice_Date__c = Date.today();
                invoice.Payment_Status__c = 'Unpaid';
            }

            if (invoice.Admission__c != null) {
                Admission__c adm = admissions.get(invoice.Admission__c);
                if (adm != null) {
                    invoice.Patient__c = adm.Patient__c;
                    invoice.Insurance_Policy__c = adm.Insurance_Policy__c;
                    invoice.Insurance_Verified__c = adm.Insurance_Verified__c;
                    if (String.isBlank(invoice.Patient_Category__c) && adm.Patient__r != null) {
                        invoice.Patient_Category__c = normalizePatientCategory(adm.Patient__r.Patient_Category__c);
                    }
                    if (adm.Insurance_Policy__c != null) {
                        policyIds.add(adm.Insurance_Policy__c);
                    }
                }
            }

            invoice.Patient_Category__c = normalizePatientCategory(invoice.Patient_Category__c);
        }
        
        Map<Id, Insurance_Policy__c> policies = policyIds.isEmpty()
            ? new Map<Id, Insurance_Policy__c>()
            : new Map<Id, Insurance_Policy__c>([
                SELECT Id, Insurance_Company__r.Standard_Discount__c
                FROM Insurance_Policy__c
                WHERE Id IN :policyIds
                WITH SYSTEM_MODE
            ]);

        for (Invoice__c invoice : invoices) {
            Decimal gross = invoice.Gross_Amount__c == null ? 0 : invoice.Gross_Amount__c;
            
            Decimal insuranceDiscountPercent = 0;
            if (invoice.Insurance_Policy__c != null) {
                Insurance_Policy__c policy = policies.get(invoice.Insurance_Policy__c);
                if (policy != null && policy.Insurance_Company__r != null && policy.Insurance_Company__r.Standard_Discount__c != null) {
                    insuranceDiscountPercent = policy.Insurance_Company__r.Standard_Discount__c;
                }
            }
            Decimal insuranceCover = gross * insuranceDiscountPercent / 100;
            Decimal subsidyBase = gross - insuranceCover;
            if (subsidyBase < 0) {
                subsidyBase = 0;
            }
            Decimal discountPercent = patientDiscount(invoice.Patient_Category__c);
            Decimal categoryDiscount = subsidyBase * discountPercent / 100;
            
            invoice.Discount_Amount__c = categoryDiscount;
            invoice.Insurance_Covered_Amount__c = insuranceCover;
            
            Decimal nonBillable = invoice.Non_Billable_Deduction__c == null ? 0 : invoice.Non_Billable_Deduction__c;
            Decimal payable = gross - categoryDiscount - insuranceCover - nonBillable;
            if (payable < 0) {
                payable = 0;
            }
            invoice.Net_Payable__c = payable;
            invoice.Net_Amount__c = payable;
            invoice.Total_Amount__c = payable;
        }
    }

    private static Decimal patientDiscount(String category) {
        if (category == 'Hospital Employee') {
            return 20;
        }
        if (category == 'Civil Servant') {
            return 50;
        }
        if (category == 'Armed Professional') {
            return 40;
        }
        return 0;
    }

    private static String normalizePatientCategory(String category) {
        if (category == 'Hospital Employee' || category == 'Civil Servant' || category == 'Armed Professional') {
            return category;
        }
        return 'Normal';
    }
}