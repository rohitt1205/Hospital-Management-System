public without sharing class AppointmentAutomationHandler {
    public static void beforeSave(List<Appointment__c> appointments) {
        beforeSave(appointments, null);
    }

    public static void beforeSave(List<Appointment__c> appointments, Map<Id, Appointment__c> oldMap) {
        Set<Id> doctorIds = new Set<Id>();
        for (Appointment__c appointment : appointments) {
            if (appointment.Doctor__c != null) {
                doctorIds.add(appointment.Doctor__c);
            }
        }
        if (doctorIds.isEmpty()) {
            return;
        }

        Map<Id, Doctor__c> doctors = new Map<Id, Doctor__c>([
            SELECT Id, Department__c
            FROM Doctor__c
            WHERE Id IN :doctorIds
            WITH SYSTEM_MODE
        ]);

        for (Appointment__c appointment : appointments) {
            Doctor__c doctor = doctors.get(appointment.Doctor__c);
            Appointment__c oldAppointment = oldMap != null ? oldMap.get(appointment.Id) : null;
            Boolean schedulingChanged = oldAppointment == null || schedulingFieldsChanged(appointment, oldAppointment);

            if (schedulingChanged
                && appointment.Appointment_Date_Time__c == null
                && appointment.Appointment_Date__c != null
                && String.isNotBlank(appointment.Appointment_Time__c)) {
                appointment.Appointment_Date_Time__c = AppointmentBookingService.resolveAppointmentDateTime(
                    appointment.Appointment_Date__c,
                    appointment.Appointment_Time__c,
                    null
                );
            }
            // Agent bookings set date, time, and datetime together — do not re-derive from
            // the running user's timezone (Einstein bot users are often US/Pacific).
            // On status-only updates (for example admin approval), leave scheduling fields alone.
            if (schedulingChanged
                && appointment.Source__c != 'Agent'
                && appointment.Appointment_Date_Time__c != null
                && (oldAppointment == null
                    || appointment.Appointment_Date_Time__c != oldAppointment.Appointment_Date_Time__c)) {
                appointment.Appointment_Date__c = appointment.Appointment_Date_Time__c.date();
                String hour = appointment.Appointment_Date_Time__c.format('HH');
                Integer minute = Integer.valueOf(appointment.Appointment_Date_Time__c.format('mm'));
                appointment.Appointment_Time__c = hour + ':' + (minute < 30 ? '00' : '30');
            }
            if (doctor == null || doctor.Department__c == null) {
                continue;
            }
            appointment.Department__c = doctor.Department__c;
        }
    }

    private static Boolean schedulingFieldsChanged(Appointment__c appointment, Appointment__c oldAppointment) {
        return appointment.Appointment_Date__c != oldAppointment.Appointment_Date__c
            || appointment.Appointment_Time__c != oldAppointment.Appointment_Time__c
            || appointment.Appointment_Date_Time__c != oldAppointment.Appointment_Date_Time__c;
    }
}