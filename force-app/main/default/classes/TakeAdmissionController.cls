public without sharing class TakeAdmissionController {
    @AuraEnabled
    public static Id createAdmission(Id appointmentId) {
        if (appointmentId == null) {
            throw new AuraHandledException('Appointment is required.');
        }

        Appointment__c appointment = [
            SELECT Id, Name, Patient__c, Doctor__c, Department__c
            FROM Appointment__c
            WHERE Id = :appointmentId
            LIMIT 1
        ];

        List<Admission__c> existing = [
            SELECT Id
            FROM Admission__c
            WHERE Appointment__c = :appointmentId
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0].Id;
        }

        Admission__c admission = new Admission__c(
            Appointment__c = appointment.Id,
            Doctor__c = appointment.Doctor__c,
            Department__c = appointment.Department__c,
            Admission_Type__c = 'Planned',
            Admission_Date_Time__c = System.now(),
            Status__c = 'Draft'
        );

        insert admission;
        return admission.Id;
    }
}