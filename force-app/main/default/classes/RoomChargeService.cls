public with sharing class RoomChargeService {
    public static Set<Id> createCharges(Set<Id> admissionIds) {
        if (admissionIds == null || admissionIds.isEmpty()) {
            return new Set<Id>();
        }

        List<Admission__c> admissions = [
            SELECT Id, Patient__c, Patient__r.Patient_Category__c, Insurance_Covered_Amount__c,
                   Admission_Date_Time__c, Actual_Discharge_Date_Time__c, Discharge_Date__c,
                   Room__c, Room__r.Name, Room__r.Room_Type__c
            FROM Admission__c
            WHERE Id IN :admissionIds
            AND Room__c != null
        ];

        Map<Id, Invoice__c> invoiceByAdmission = InvoiceService.getOrCreateForAdmissions(admissions);
        Map<Id, BillingCharge> chargeByAdmission = new Map<Id, BillingCharge>();

        for (Admission__c admission : admissions) {
            Integer days = BillingUtil.lengthOfStayDays(
                admission.Admission_Date_Time__c,
                admission.Actual_Discharge_Date_Time__c == null ? admission.Discharge_Date__c : admission.Actual_Discharge_Date_Time__c
            );
            Decimal rate = dailyRate(admission.Room__r == null ? null : admission.Room__r.Room_Type__c);
            if (rate <= 0) {
                continue;
            }

            String description = 'Room Charge';
            if (admission.Room__r != null) {
                description += ' - ' + admission.Room__r.Name;
                if (!String.isBlank(admission.Room__r.Room_Type__c)) {
                    description += ' (' + admission.Room__r.Room_Type__c + ')';
                }
            }

            chargeByAdmission.put(
                admission.Id,
                new BillingCharge(BillingUtil.ROOM, admission.Room__c, description, days, rate)
            );
        }

        Set<Id> invoiceIds = InvoiceLineItemService.upsertCharges(invoiceByAdmission, chargeByAdmission);
        InvoiceService.updateTotals(invoiceIds);
        return invoiceIds;
    }

    private static Decimal dailyRate(String roomType) {
        if (roomType == 'Shared') return 1000;
        if (roomType == 'Semi Private') return 2500;
        if (roomType == 'Private') return 5000;
        if (roomType == 'ICU') return 12000;
        if (roomType == 'OPD Cabin') return 1500;
        return 0;
    }
}