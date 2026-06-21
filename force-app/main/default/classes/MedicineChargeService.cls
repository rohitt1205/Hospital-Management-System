public with sharing class MedicineChargeService {
    public static Set<Id> createCharges(Set<Id> prescriptionLineItemIds) {
        if (prescriptionLineItemIds == null || prescriptionLineItemIds.isEmpty()) {
            return new Set<Id>();
        }

        List<Prescription_Line_Item__c> prescriptionLines = [
            SELECT Id, Quantity__c, Medicine__c, Medicine__r.Name, Medicine__r.Unit_Price__c,
                   Prescription__c, Prescription__r.Patient__c,
                   Prescription__r.Medical_Record__r.Admission__c,
                   Prescription__r.Total_Medicine_Bill__c
            FROM Prescription_Line_Item__c
            WHERE Id IN :prescriptionLineItemIds
            AND Medicine__c != null
            AND Prescription__c != null
        ];

        Map<Id, Invoice__c> invoiceByLine = getInvoices(prescriptionLines);
        Map<Id, BillingCharge> chargeByLine = new Map<Id, BillingCharge>();

        for (Prescription_Line_Item__c line : prescriptionLines) {
            Decimal rate = line.Medicine__r == null ? 0 : BillingUtil.zeroIfNull(line.Medicine__r.Unit_Price__c);
            Decimal quantity = line.Quantity__c == null || line.Quantity__c <= 0 ? 1 : line.Quantity__c;

            if (line.Prescription__r != null && line.Prescription__r.Total_Medicine_Bill__c != null && line.Prescription__r.Total_Medicine_Bill__c > 0) {
                rate = line.Prescription__r.Total_Medicine_Bill__c;
                quantity = 1;
            }

            if (rate <= 0) {
                continue;
            }

            BillingCharge charge = new BillingCharge(BillingUtil.MEDICINE, line.Id, 'Medicine - ' + line.Medicine__r.Name, quantity, rate);
            charge.medicineId = line.Medicine__c;
            chargeByLine.put(line.Id, charge);
        }

        Set<Id> invoiceIds = InvoiceLineItemService.upsertCharges(invoiceByLine, chargeByLine);
        InvoiceService.updateTotals(invoiceIds);
        return invoiceIds;
    }

    private static Map<Id, Invoice__c> getInvoices(List<Prescription_Line_Item__c> lines) {
        Map<Id, Invoice__c> invoiceByLine = new Map<Id, Invoice__c>();
        Map<Id, List<Prescription_Line_Item__c>> linesByAdmission = new Map<Id, List<Prescription_Line_Item__c>>();
        Map<Id, Id> sourceToPatient = new Map<Id, Id>();

        for (Prescription_Line_Item__c line : lines) {
            Id admissionId = line.Prescription__r == null || line.Prescription__r.Medical_Record__r == null
                ? null
                : line.Prescription__r.Medical_Record__r.Admission__c;
            if (admissionId != null) {
                if (!linesByAdmission.containsKey(admissionId)) {
                    linesByAdmission.put(admissionId, new List<Prescription_Line_Item__c>());
                }
                linesByAdmission.get(admissionId).add(line);
            } else if (line.Prescription__r != null && line.Prescription__r.Patient__c != null) {
                sourceToPatient.put(line.Id, line.Prescription__r.Patient__c);
            }
        }

        if (!linesByAdmission.isEmpty()) {
            List<Admission__c> admissions = [
                SELECT Id, Patient__c, Patient__r.Patient_Category__c, Insurance_Covered_Amount__c
                FROM Admission__c
                WHERE Id IN :linesByAdmission.keySet()
            ];
            Map<Id, Invoice__c> invoiceByAdmission = InvoiceService.getOrCreateForAdmissions(admissions);
            for (Id admissionId : linesByAdmission.keySet()) {
                for (Prescription_Line_Item__c line : linesByAdmission.get(admissionId)) {
                    invoiceByLine.put(line.Id, invoiceByAdmission.get(admissionId));
                }
            }
        }

        invoiceByLine.putAll(InvoiceService.getOrCreateForPatients(sourceToPatient));
        return invoiceByLine;
    }
}