public without sharing class AppointmentAdmissionHandler {
    public static void handleAfterInsert(List<Appointment__c> newAppointments) {
        Set<Id> appointmentIds = new Set<Id>();
        for (Appointment__c appointment : newAppointments) {
            if (appointment.Doctor__c != null) {
                appointmentIds.add(appointment.Id);
            }
        }
        if (!appointmentIds.isEmpty()) {
            HMSNotificationService.enqueueDoctorAppointmentNotifications(appointmentIds);
        }
    }

    public static void handleAfterUpdate(Map<Id, Appointment__c> oldMap, List<Appointment__c> newAppointments) {
        // Admissions are now created only by the explicit Take Admission action.
    }
}