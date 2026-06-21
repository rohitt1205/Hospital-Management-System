public without sharing class AppointmentBookingInvocableListUpcoming {
    public class Request {
        @InvocableVariable(
            label='Portal User Id'
            description='Salesforce User Id of the logged-in Experience Cloud patient. Leave blank to use the current session user.'
        )
        public String portalUserId;
    }

    public class Response {
        @InvocableVariable(label='Success' description='True when the query completed without error.')
        public Boolean isSuccess;

        @InvocableVariable(
            label='Appointments Text'
            description='Human-readable numbered list of upcoming appointments with confirmation number, date, time, doctor, department, type, and status.'
        )
        public String appointmentsText;

        @InvocableVariable(label='Appointment Count' description='Number of upcoming appointments found.')
        public Integer appointmentCount;

        @InvocableVariable(label='Error Message' description='Patient-friendly error when the query fails.')
        public String errorMessage;
    }

    @InvocableMethod(
        label='List My Appointments'
        description='Returns the logged-in patient upcoming appointments. Call immediately when the patient asks to see or view their appointments.'
        category='Appointment Management'
    )
    public static List<Response> listUpcoming(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request req : requests) {
            Response res = new Response();
            res.isSuccess = false;
            res.appointmentCount = 0;
            try {
                Id patientId = AppointmentBookingInvocable.resolvePatientId(req.portalUserId);
                List<AppointmentBookingService.AppointmentSummary> appointments =
                    AppointmentBookingService.listUpcomingAppointments(patientId);
                res.isSuccess = true;
                res.appointmentCount = appointments.size();
                res.appointmentsText = AppointmentBookingService.formatAppointmentsForConversation(appointments);
            } catch (Exception ex) {
                res.errorMessage = ex.getMessage();
                res.appointmentsText = ex.getMessage();
            }
            responses.add(res);
        }
        return responses;
    }
}