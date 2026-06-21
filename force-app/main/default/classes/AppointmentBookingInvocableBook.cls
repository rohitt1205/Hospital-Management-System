public without sharing class AppointmentBookingInvocableBook {
    public class Request {
        @InvocableVariable(
            label='Portal User Id'
            description='Salesforce User Id of the logged-in Experience Cloud patient. Leave blank to use the current session user.'
        )
        public String portalUserId;

        @InvocableVariable(
            label='Doctor Record Id'
            description='Optional Salesforce Doctor__c record Id for the chosen slot. Leave blank when the patient has no doctor preference — the action will assign the first available doctor in the department for the requested date and time window.'
        )
        public String doctorId;

        @InvocableVariable(
            label='Appointment Date'
            description='Required. Booking date in YYYY-MM-DD format matching the slot the patient confirmed.'
            required=true
        )
        public String appointmentDate;

        @InvocableVariable(
            label='Appointment Time'
            description='Required. Exact slot start time (e.g. 10:00) OR a time-of-day preference: morning, afternoon, or evening. When a preference is used without a doctor Id, the action picks the first open slot in that window.'
            required=true
        )
        public String appointmentTime;

        @InvocableVariable(
            label='Appointment Type'
            description='Appointment type: OPD, Follow-Up, Teleconsultation, or Emergency Consultation. Must match what was discussed with the patient.'
        )
        public String appointmentType;

        @InvocableVariable(
            label='Department Name'
            description='Required when doctorId is blank. Department such as Orthopedics or Cardiology used to find an available doctor.'
        )
        public String departmentName;

        @InvocableVariable(
            label='Doctor Name'
            description='Optional partial doctor name filter. Leave blank or use "any doctor" when the patient has no doctor preference.'
        )
        public String doctorName;

        @InvocableVariable(
            label='Slot Label'
            description='Optional human-readable slot label such as 10:00 - 10:30 from the find-slots results.'
        )
        public String slotLabel;

        @InvocableVariable(
            label='Symptoms'
            description='Optional brief symptom description provided by the patient.'
        )
        public String symptoms;
    }

    public class Response {
        @InvocableVariable(label='Success' description='True only when an Appointment__c record was created.')
        public Boolean isSuccess;

        @InvocableVariable(
            label='Confirmation Number'
            description='Appointment auto-number token (APT-xxxxx). Never invent this value; only use what this action returns.'
        )
        public String confirmationNumber;

        @InvocableVariable(label='Appointment Record Id' description='Salesforce Id of the created Appointment__c record.')
        public String appointmentId;

        @InvocableVariable(
            label='Confirmation Message'
            description='Patient-friendly submitted-request message. Relay this text verbatim on success — never paraphrase or invent your own confirmation.'
        )
        public String confirmationMessage;

        @InvocableVariable(label='Assigned Doctor Name' description='Auto-assigned or selected doctor display name.')
        public String assignedDoctorName;

        @InvocableVariable(label='Assigned Department Name' description='Booked department display name.')
        public String assignedDepartmentName;

        @InvocableVariable(label='Appointment Date Time' description='Requested date and time.')
        public Datetime appointmentDateTime;

        @InvocableVariable(
            label='Error Message'
            description='Patient-friendly error when booking fails. Relay this text verbatim — do not replace with a generic apology.'
        )
        public String errorMessage;
    }

    @InvocableMethod(
        label='Create Appointment Record'
        description='Creates an Appointment__c record for the logged-in patient. Call as soon as department, date, and time are known — no confirmation step required.'
        category='Appointment Management'
    )
    public static List<Response> book(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request req : requests) {
            Response res = new Response();
            res.isSuccess = false;
            res.confirmationMessage = null;
            res.errorMessage = null;
            try {
                AppointmentBookingInvocable.normalizeBookingRequest(req);
                Id patientId = AppointmentBookingInvocable.resolvePatientId(req.portalUserId);
                Id doctorId = AppointmentBookingInvocable.parseOptionalId(req.doctorId, 'doctor');
                Date targetDate = AppointmentBookingInvocable.parseDate(req.appointmentDate);
                if (String.isBlank(req.appointmentTime)) {
                    throw new AppointmentBookingException('Please provide an appointment time or time-of-day preference.');
                }
                if (doctorId == null && String.isBlank(req.departmentName)) {
                    throw new AppointmentBookingException(
                        'Please provide a department when the patient has no doctor preference.'
                    );
                }
                String doctorNameInput = AppointmentBookingInvocable.normalizeDoctorNameInput(req.doctorName);
                String appointmentType = String.isBlank(req.appointmentType) ? 'OPD' : req.appointmentType;
                AppointmentBookingService.BookingResult result = AppointmentBookingService.bookAppointment(
                    patientId,
                    doctorId,
                    targetDate,
                    req.appointmentTime,
                    appointmentType,
                    req.symptoms,
                    req.slotLabel,
                    req.departmentName,
                    doctorNameInput
                );
                res.isSuccess = true;
                res.confirmationNumber = result.confirmationNumber;
                res.appointmentId = String.valueOf(result.appointmentId);
                res.confirmationMessage = result.message;
                res.assignedDoctorName = result.doctorName;
                res.assignedDepartmentName = result.departmentName;
                res.appointmentDateTime = result.appointmentDateTime;
            } catch (Exception ex) {
                res.isSuccess = false;
                res.errorMessage = String.isBlank(ex.getMessage())
                    ? 'An unexpected error occurred while booking your appointment (' + ex.getTypeName() + ').'
                    : ex.getMessage();
            }
            if (!res.isSuccess && String.isBlank(res.errorMessage)) {
                res.errorMessage = 'Booking failed. Please try again or contact reception.';
            }
            responses.add(res);
        }
        return responses;
    }
}