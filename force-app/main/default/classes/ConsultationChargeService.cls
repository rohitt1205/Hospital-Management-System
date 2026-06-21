public with sharing class ConsultationChargeService {
    public static Set<Id> createCharges(Set<Id> appointmentIds) {
        if (appointmentIds == null || appointmentIds.isEmpty()) {
            return new Set<Id>();
        }

        List<Appointment__c> appointments = [
            SELECT Id, Patient__c, Doctor__c, Doctor__r.Name, Doctor__r.Consultation_Fee__c
            FROM Appointment__c
            WHERE Id IN :appointmentIds
            AND Status__c = 'Completed'
            AND Patient__c != null
            AND Doctor__c != null
        ];

        Map<Id, Id> sourceToPatient = new Map<Id, Id>();
        for (Appointment__c appointment : appointments) {
            sourceToPatient.put(appointment.Id, appointment.Patient__c);
        }

        Map<Id, Invoice__c> invoiceByAppointment = InvoiceService.getOrCreateForPatients(sourceToPatient);
        Map<Id, BillingCharge> chargeByAppointment = new Map<Id, BillingCharge>();

        for (Appointment__c appointment : appointments) {
            Decimal rate = appointment.Doctor__r == null ? 0 : BillingUtil.zeroIfNull(appointment.Doctor__r.Consultation_Fee__c);
            if (rate <= 0) {
                continue;
            }

            chargeByAppointment.put(
                appointment.Id,
                new BillingCharge(
                    BillingUtil.CONSULTATION,
                    appointment.Id,
                    'Doctor Consultation - ' + appointment.Doctor__r.Name,
                    1,
                    rate
                )
            );
        }

        Set<Id> invoiceIds = InvoiceLineItemService.upsertCharges(invoiceByAppointment, chargeByAppointment);
        InvoiceService.updateTotals(invoiceIds);
        return invoiceIds;
    }
}