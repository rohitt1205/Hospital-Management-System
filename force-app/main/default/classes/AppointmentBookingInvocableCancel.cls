public with sharing class AppointmentBookingInvocableCancel {
    public class Request {
        @InvocableVariable(
            label='Portal User Id'
            description='Salesforce User Id of the logged-in Experience Cloud patient. Leave blank to use the current session user.'
        )
        public String portalUserId;

        @InvocableVariable(
            label='Appointment Record Id'
            description='Required. Salesforce Appointment__c Id to cancel. Must belong to the logged-in patient and have status Requested or Confirmed.'
            required=true
        )
        public String appointmentId;
    }

    public class Response {
        @InvocableVariable(label='Success' description='True when the appointment was cancelled.')
        public Boolean isSuccess;

        @InvocableVariable(label='Confirmation Number' description='Cancelled appointment APT number.')
        public String confirmationNumber;

        @InvocableVariable(label='Result Message' description='Human-readable cancellation summary for the patient.')
        public String resultMessage;

        @InvocableVariable(label='Error Message' description='Patient-friendly error when cancellation is not allowed.')
        public String errorMessage;
    }

    @InvocableMethod(
        label='Cancel Appointment'
        description='Cancels an upcoming appointment for the logged-in patient. Validates ownership and cancellable status before updating.'
        category='Appointment Management'
    )
    public static List<Response> cancel(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request req : requests) {
            Response res = new Response();
            res.isSuccess = false;
            try {
                Id patientId = AppointmentBookingInvocable.resolvePatientId(req.portalUserId);
                Id appointmentId = AppointmentBookingInvocable.parseId(req.appointmentId, 'appointment');
                AppointmentBookingService.AppointmentSummary summary =
                    AppointmentBookingService.cancelAppointment(patientId, appointmentId);
                res.isSuccess = true;
                res.confirmationNumber = summary.confirmationNumber;
                res.resultMessage = 'Appointment ' + summary.confirmationNumber + ' has been cancelled.';
            } catch (Exception ex) {
                res.errorMessage = ex.getMessage();
            }
            responses.add(res);
        }
        return responses;
    }
}