public with sharing class AppointmentBookingInvocableFindSlots {
    public class Request {
        @InvocableVariable(
            label='Portal User Id'
            description='Salesforce User Id of the logged-in Experience Cloud patient. Leave blank to use the current session user. Never pass another patients user Id.'
        )
        public String portalUserId;

        @InvocableVariable(
            label='Appointment Date'
            description='Required. Date to search for open slots in YYYY-MM-DD format (e.g. 2026-06-20). Must be today or within the next 30 days.'
            required=true
        )
        public String appointmentDate;

        @InvocableVariable(
            label='Appointment Type'
            description='Natural language or picklist value for appointment type: OPD, Follow-Up, Teleconsultation, or Emergency Consultation. Examples: "teleconsultation", "video visit", "follow up", "general OPD". Defaults to OPD when omitted.'
        )
        public String appointmentType;

        @InvocableVariable(
            label='Department Name'
            description='Optional department name filter such as Cardiology, General Medicine, or Orthopedics. Use when the patient names a department.'
        )
        public String departmentName;

        @InvocableVariable(
            label='Doctor Name'
            description='Optional partial doctor name filter. Use when the patient requests a specific doctor.'
        )
        public String doctorName;

        @InvocableVariable(
            label='Symptom Or Specialty Hint'
            description='Optional symptom area or medical specialty hint (e.g. "chest pain", "child fever", "orthopedic") used to infer the best department when department is not specified.'
        )
        public String symptomOrSpecialtyHint;

        @InvocableVariable(
            label='Time Of Day Preference'
            description='Optional filter: morning, afternoon, or evening. Use when the patient names a part of day instead of an exact time.'
        )
        public String timeOfDayPreference;
    }

    public class Response {
        @InvocableVariable(
            label='Success'
            description='True when open slots were returned without error.'
        )
        public Boolean isSuccess;

        @InvocableVariable(
            label='Available Slots Text'
            description='Human-readable numbered list of open slots with date, time window, doctor, department, and appointment type. Read this aloud to the patient.'
        )
        public String availableSlotsText;

        @InvocableVariable(
            label='Slot Count'
            description='Number of open slots returned.'
        )
        public Integer slotCount;

        @InvocableVariable(
            label='Resolved Appointment Type'
            description='The appointment type picklist value applied to the search (OPD, Follow-Up, Teleconsultation, or Emergency Consultation).'
        )
        public String resolvedAppointmentType;

        @InvocableVariable(
            label='Error Message'
            description='Patient-friendly explanation when the action fails or no doctors are available.'
        )
        public String errorMessage;
    }

    @InvocableMethod(
        label='Find Available Appointment Slots'
        description='Returns real open appointment slots for a patient on a given date, filtered by department, doctor, symptoms, and appointment type. Excludes doctors on leave and fully booked slots.'
        category='Appointment Management'
    )
    public static List<Response> findSlots(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request req : requests) {
            Response res = new Response();
            res.isSuccess = false;
            res.slotCount = 0;
            try {
                Id patientId = AppointmentBookingInvocable.resolvePatientId(req.portalUserId);
                Date targetDate = AppointmentBookingInvocable.parseDate(req.appointmentDate);
                String resolvedType = AppointmentBookingService.resolveAppointmentType(req.appointmentType);
                List<AppointmentBookingService.SlotInfo> slots = AppointmentBookingService.findAvailableSlots(
                    patientId,
                    targetDate,
                    resolvedType,
                    req.departmentName,
                    AppointmentBookingInvocable.normalizeDoctorNameInput(req.doctorName),
                    req.symptomOrSpecialtyHint,
                    req.timeOfDayPreference
                );
                if (slots.isEmpty()) {
                    throw new AppointmentBookingException(
                        'No open appointment slots were found for the requested date' +
                        (String.isBlank(req.timeOfDayPreference) ? '.' : ' in the ' + req.timeOfDayPreference.trim().toLowerCase() + '.') +
                        ' Please try another day or time.'
                    );
                }
                res.isSuccess = true;
                res.slotCount = slots.size();
                res.resolvedAppointmentType = resolvedType;
                res.availableSlotsText = AppointmentBookingService.formatSlotsForConversation(slots);
            } catch (Exception ex) {
                res.errorMessage = ex.getMessage();
                res.availableSlotsText = ex.getMessage();
            }
            responses.add(res);
        }
        return responses;
    }
}