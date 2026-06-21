public with sharing class AppointmentBookingInvocableReschedule {
    public class Request {
        @InvocableVariable(
            label='Portal User Id'
            description='Salesforce User Id of the logged-in Experience Cloud patient. Leave blank to use the current session user.'
        )
        public String portalUserId;

        @InvocableVariable(
            label='Appointment Record Id'
            description='Required. Existing Appointment__c Id to reschedule. Must belong to the logged-in patient.'
            required=true
        )
        public String appointmentId;

        @InvocableVariable(
            label='New Doctor Record Id'
            description='Optional new Doctor__c Id. Leave blank to keep the same doctor when only changing date or time.'
        )
        public String newDoctorId;

        @InvocableVariable(
            label='New Appointment Date'
            description='Required. New date in YYYY-MM-DD format. Must be today or within 30 days.'
            required=true
        )
        public String newAppointmentDate;

        @InvocableVariable(
            label='New Appointment Time'
            description='Required. New slot start time such as 14:00. Must be an open slot from the find-slots action.'
            required=true
        )
        public String newAppointmentTime;

        @InvocableVariable(
            label='New Slot Label'
            description='Optional slot label such as 14:00 - 14:30 from find-slots results.'
        )
        public String newSlotLabel;
    }

    public class Response {
        @InvocableVariable(label='Success' description='True when the appointment was rescheduled.')
        public Boolean isSuccess;

        @InvocableVariable(label='Confirmation Number' description='Appointment APT number after reschedule.')
        public String confirmationNumber;

        @InvocableVariable(label='Result Message' description='Human-readable reschedule summary for the patient.')
        public String resultMessage;

        @InvocableVariable(label='Error Message' description='Patient-friendly error when reschedule fails validation.')
        public String errorMessage;
    }

    @InvocableMethod(
        label='Reschedule Appointment'
        description='Updates an existing upcoming appointment to a new validated slot for the logged-in patient. Re-validates availability before saving.'
        category='Appointment Management'
    )
    public static List<Response> reschedule(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request req : requests) {
            Response res = new Response();
            res.isSuccess = false;
            try {
                Id patientId = AppointmentBookingInvocable.resolvePatientId(req.portalUserId);
                Id appointmentId = AppointmentBookingInvocable.parseId(req.appointmentId, 'appointment');
                Id newDoctorId = AppointmentBookingInvocable.parseId(req.newDoctorId, 'doctor');
                Date newDate = AppointmentBookingInvocable.parseDate(req.newAppointmentDate);
                AppointmentBookingService.AppointmentSummary summary =
                    AppointmentBookingService.rescheduleAppointment(
                        patientId,
                        appointmentId,
                        newDoctorId,
                        newDate,
                        req.newAppointmentTime,
                        req.newSlotLabel
                    );
                res.isSuccess = true;
                res.confirmationNumber = summary.confirmationNumber;
                res.resultMessage = 'Appointment ' + summary.confirmationNumber + ' has been rescheduled to ' +
                    summary.humanReadable + '.';
            } catch (Exception ex) {
                res.errorMessage = ex.getMessage();
            }
            responses.add(res);
        }
        return responses;
    }
}