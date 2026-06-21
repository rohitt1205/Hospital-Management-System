/**
 * Core appointment booking service for Agentforce patient self-service.
 *
 * Data model assumptions documented inline:
 * - Patient identity is resolved via Patient__c.Portal_User__c → User (Experience Cloud).
 * - Appointment confirmation token is Appointment__c.Name (auto-number APT-{00000}).
 * - Appointment_Type__c was added to Appointment__c because no appointment-type picklist
 *   existed in source metadata; supported values: OPD, Follow-Up, Teleconsultation,
 *   Emergency Consultation.
 * - Doctor availability comes from Doctor_Availability__c (day, start/end, Slot_Capacity__c)
 *   with fallback to Doctor__c.Available_Slots_Config__c and day checkboxes.
 * - Doctors marked Availability_Status__c = On Leave or Off Duty are excluded for the date.
 * - Reschedule updates the existing Appointment__c record (no cancel-and-rebook pattern in org).
 */
public without sharing class AppointmentBookingService {

    private static final Set<String> CANCELLABLE_STATUSES = new Set<String>{
        'Requested', 'Confirmed'
    };
    private static final Set<String> EXCLUDED_BOOKING_STATUSES = new Set<String>{
        'Cancelled', 'No Show'
    };
    private static final Set<String> UNAVAILABLE_DOCTOR_STATUSES = new Set<String>{
        'On Leave', 'Off Duty'
    };
    private static final Integer DEFAULT_SLOT_MINUTES = 30;
    private static final Integer DEFAULT_SLOT_CAPACITY = 1;
    private static final Integer MAX_BOOKING_DAYS_AHEAD = 365;
    private static final Integer MORNING_START_MINUTES = 6 * 60;
    private static final Integer MORNING_END_MINUTES = 12 * 60;
    private static final Integer AFTERNOON_START_MINUTES = 12 * 60;
    private static final Integer AFTERNOON_END_MINUTES = 17 * 60;
    private static final Integer EVENING_START_MINUTES = 17 * 60;
    private static final Integer EVENING_END_MINUTES = 22 * 60;

    private static final Map<String, String> SYMPTOM_TO_DEPARTMENT = new Map<String, String>{
        'heart' => 'Cardiology',
        'cardiac' => 'Cardiology',
        'chest pain' => 'Cardiology',
        'brain' => 'Neurology',
        'headache' => 'Neurology',
        'seizure' => 'Neurology',
        'bone' => 'Orthopedics',
        'joint' => 'Orthopedics',
        'fracture' => 'Orthopedics',
        'child' => 'General Medicine',
        'pediatric' => 'General Medicine',
        'pregnancy' => 'General Medicine',
        'gynec' => 'General Medicine',
        'cancer' => 'Oncology',
        'oncology' => 'Oncology',
        'emergency' => 'Emergency',
        'x-ray' => 'Radiology',
        'scan' => 'Radiology',
        'lab' => 'Labs',
        'blood test' => 'Labs'
    };

    private static final Map<String, String> SPECIALIZATION_TO_DEPARTMENT = new Map<String, String>{
        'General Physician' => 'General Medicine',
        'Cardiologist' => 'Cardiology',
        'Neurologist' => 'Neurology',
        'Oncologist' => 'Oncology',
        'Orthopedic Surgeon' => 'Orthopedics',
        'Pediatrician' => 'General Medicine',
        'Gynecologist' => 'General Medicine',
        'Emergency Physician' => 'Emergency',
        'Radiologist' => 'Radiology',
        'Pathologist' => 'Labs',
        'Anesthesiologist' => 'Emergency'
    };

    public class SlotInfo {
        public Id doctorId;
        public String doctorName;
        public Id departmentId;
        public String departmentName;
        public Date appointmentDate;
        public String slotLabel;
        public String appointmentTime;
        public Datetime appointmentDateTime;
        public String appointmentType;
        public String appointmentTypeLabel;
        public Integer remainingCapacity;
    }

    public class BookingResult {
        public Id appointmentId;
        public String confirmationNumber;
        public String doctorName;
        public String departmentName;
        public Datetime appointmentDateTime;
        public String appointmentTypeLabel;
        public String status;
        public String message;
    }

    public class AppointmentSummary {
        public Id appointmentId;
        public String confirmationNumber;
        public Datetime appointmentDateTime;
        public String doctorName;
        public String departmentName;
        public String appointmentTypeLabel;
        public String status;
        public String humanReadable;
    }

    // ─── Public API ───────────────────────────────────────────────────────────

    public static List<SlotInfo> findAvailableSlots(
        Id patientId,
        Date appointmentDate,
        String appointmentTypeInput,
        String departmentNameInput,
        String doctorNameInput,
        String symptomOrSpecialtyInput
    ) {
        return findAvailableSlots(
            patientId,
            appointmentDate,
            appointmentTypeInput,
            departmentNameInput,
            doctorNameInput,
            symptomOrSpecialtyInput,
            null
        );
    }

    public static List<SlotInfo> findAvailableSlots(
        Id patientId,
        Date appointmentDate,
        String appointmentTypeInput,
        String departmentNameInput,
        String doctorNameInput,
        String symptomOrSpecialtyInput,
        String timeOfDayPreference
    ) {
        validatePatientExists(patientId);
        Date targetDate = validateAppointmentDate(appointmentDate);
        String appointmentType = resolveAppointmentType(appointmentTypeInput);

        Id departmentId = resolveDepartmentId(departmentNameInput, symptomOrSpecialtyInput);
        List<Doctor__c> doctors = queryEligibleDoctors(departmentId, doctorNameInput, targetDate);
        if (doctors.isEmpty()) {
            throw new AppointmentBookingException(
                'No doctors are available for the requested department or specialty on that date. ' +
                'Please try another date or ask to speak with a receptionist.'
            );
        }

        Map<Id, Doctor__c> doctorMap = new Map<Id, Doctor__c>(doctors);
        String dayOfWeek = dayNameFromDate(targetDate);
        Map<Id, List<Doctor_Availability__c>> availabilityByDoctor = loadAvailabilityByDoctor(
            doctorMap.keySet(),
            dayOfWeek
        );
        Map<String, Integer> bookedByDoctorSlot = loadBookedCountsByDoctorSlot(doctorMap.keySet(), targetDate);
        Map<Id, Integer> bookedDailyByDoctor = loadDailyBookedCounts(doctorMap.keySet(), targetDate);

        List<SlotInfo> openSlots = new List<SlotInfo>();
        for (Doctor__c doctor : doctors) {
            Integer dailyMax = doctor.Max_Daily_Appointments__c == null
                ? null
                : Integer.valueOf(doctor.Max_Daily_Appointments__c);
            Integer dailyBooked = bookedDailyByDoctor.containsKey(doctor.Id)
                ? bookedDailyByDoctor.get(doctor.Id)
                : 0;
            if (dailyMax != null && dailyBooked >= dailyMax) {
                continue;
            }

            List<SlotDefinition> slotDefs = buildSlotDefinitions(
                doctor,
                availabilityByDoctor.get(doctor.Id),
                dayOfWeek
            );
            for (SlotDefinition slotDef : slotDefs) {
                String slotKey = slotKeyFor(doctor.Id, slotDef.timeValue);
                Integer booked = bookedByDoctorSlot.containsKey(slotKey)
                    ? bookedByDoctorSlot.get(slotKey)
                    : 0;
                Integer capacity = slotDef.capacity == null ? DEFAULT_SLOT_CAPACITY : slotDef.capacity;
                Integer remaining = capacity - booked;
                if (remaining <= 0) {
                    continue;
                }

                SlotInfo info = new SlotInfo();
                info.doctorId = doctor.Id;
                info.doctorName = doctor.Name;
                info.departmentId = doctor.Department__c;
                info.departmentName = doctor.Department__r == null ? null : doctor.Department__r.Name;
                info.appointmentDate = targetDate;
                info.slotLabel = slotDef.label;
                info.appointmentTime = slotDef.timeValue;
                info.appointmentDateTime = combineDateAndTime(targetDate, slotDef.timeValue);
                info.appointmentType = appointmentType;
                info.appointmentTypeLabel = appointmentTypeLabel(appointmentType);
                info.remainingCapacity = remaining;
                openSlots.add(info);
            }
        }

        openSlots.sort(new SlotInfoComparator());
        return filterSlotsByTimeOfDay(openSlots, timeOfDayPreference);
    }

    public static BookingResult bookAppointment(
        Id patientId,
        Id doctorId,
        Date appointmentDate,
        String appointmentTime,
        String appointmentTypeInput,
        String symptoms,
        String slotLabel
    ) {
        return bookAppointment(
            patientId,
            doctorId,
            appointmentDate,
            appointmentTime,
            appointmentTypeInput,
            symptoms,
            slotLabel,
            null,
            null
        );
    }

    public static BookingResult bookAppointment(
        Id patientId,
        Id doctorId,
        Date appointmentDate,
        String appointmentTime,
        String appointmentTypeInput,
        String symptoms,
        String slotLabel,
        String departmentNameInput,
        String doctorNameInput
    ) {
        validatePatientExists(patientId);
        Date targetDate = validateAppointmentDate(appointmentDate);
        String appointmentType = resolveAppointmentType(appointmentTypeInput);

        SlotInfo resolvedSlot = resolveAppointmentRequestSlot(
            doctorId,
            targetDate,
            appointmentTime,
            departmentNameInput,
            doctorNameInput
        );
        Id resolvedDoctorId = resolvedSlot.doctorId;
        String normalizedTime = resolvedSlot.appointmentTime;
        String resolvedSlotLabel = String.isBlank(slotLabel) ? resolvedSlot.slotLabel : slotLabel;

        Doctor__c doctor = queryDoctorForRequest(resolvedDoctorId);

        Appointment__c appointment = new Appointment__c(
            Patient__c = patientId,
            Doctor__c = resolvedDoctorId,
            Department__c = doctor.Department__c,
            Appointment_Date_Time__c = combineDateAndTime(targetDate, normalizedTime),
            Appointment_Date__c = targetDate,
            Appointment_Time__c = normalizedTime,
            Selected_Slot__c = String.isBlank(resolvedSlotLabel)
                ? buildSlotLabel(normalizedTime)
                : resolvedSlotLabel,
            Appointment_Type__c = appointmentType,
            Status__c = 'Requested',
            Source__c = 'Agent',
            Priority__c = 'Normal',
            Symptoms__c = symptoms
        );

        try {
            Database.insert(appointment, AccessLevel.SYSTEM_MODE);
        } catch (DmlException ex) {
            String dmlMessage = ex.getNumDml() > 0 ? ex.getDmlMessage(0) : ex.getMessage();
            if (dmlMessage != null && dmlMessage.contains('FIELD_CUSTOM_VALIDATION_EXCEPTION')) {
                if (dmlMessage.contains('30 days') || dmlMessage.contains('365 days')) {
                    throw new AppointmentBookingException(
                        'That appointment date is too far in the future. Please choose a date within the next year.'
                    );
                }
            }
            if (dmlMessage != null && dmlMessage.contains('FLOW_TRIGGER')) {
                throw new AppointmentBookingException(
                    'We could not save your appointment request because a required patient phone number is missing on your profile. Please contact reception to update your details.'
                );
            }
            throw new AppointmentBookingException(
                'We could not save your appointment: ' + dmlMessage
            );
        }

        // Build the response from in-memory data — do not re-query the appointment here.
        // Agent/bot users often lack read FLS on lookup fields after insert; re-query throws
        // and surfaces as a generic "system access" error in the assistant.
        String confirmationNumber = appointment.Name;
        if (String.isBlank(confirmationNumber)) {
            confirmationNumber = loadAppointmentName(appointment.Id);
        }
        String departmentName = resolveDepartmentName(doctor.Department__c);

        BookingResult result = new BookingResult();
        result.appointmentId = appointment.Id;
        result.confirmationNumber = confirmationNumber;
        result.doctorName = doctor.Name;
        result.departmentName = departmentName;
        result.appointmentDateTime = appointment.Appointment_Date_Time__c;
        result.appointmentTypeLabel = appointmentTypeLabel(appointmentType);
        result.status = appointment.Status__c;
        result.message = buildBookingMessage(
            appointmentType,
            confirmationNumber,
            doctor.Name,
            departmentName,
            targetDate,
            normalizedTime
        );
        return result;
    }

    public static List<AppointmentSummary> listUpcomingAppointments(Id patientId) {
        validatePatientExists(patientId);
        Datetime now = Datetime.now();
        Date today = Date.today();
        List<AppointmentSummary> summaries = new List<AppointmentSummary>();
        for (Appointment__c appt : [
            SELECT Id, Name, Appointment_Date_Time__c, Appointment_Date__c, Appointment_Time__c,
                   Status__c, Appointment_Type__c, Doctor__r.Name, Department__r.Name
            FROM Appointment__c
            WHERE Patient__c = :patientId
              AND Status__c NOT IN ('Cancelled', 'Completed', 'No Show')
              AND (
                  Appointment_Date_Time__c >= :now
                  OR (Appointment_Date_Time__c = null AND Appointment_Date__c >= :today)
              )
            ORDER BY Appointment_Date__c ASC, Appointment_Time__c ASC
            LIMIT 100
        ]) {
            Datetime effectiveDateTime = resolveAppointmentDateTime(
                appt.Appointment_Date__c,
                appt.Appointment_Time__c,
                appt.Appointment_Date_Time__c
            );
            if (effectiveDateTime != null && effectiveDateTime < now) {
                continue;
            }
            summaries.add(toSummary(appt));
        }
        summaries.sort(new AppointmentSummaryComparator());
        return summaries;
    }

    /**
     * Builds a single datetime from Appointment__c date/time fields when DateTime is blank
     * (e.g. Patient Portal bookings that only set Appointment_Date__c + Appointment_Time__c).
     */
    public static Datetime resolveAppointmentDateTime(
        Date appointmentDate,
        String appointmentTime,
        Datetime appointmentDateTime
    ) {
        if (appointmentDateTime != null) {
            return appointmentDateTime;
        }
        if (appointmentDate == null || String.isBlank(appointmentTime)) {
            return null;
        }
        try {
            return combineDateAndTime(appointmentDate, appointmentTime);
        } catch (Exception ex) {
            return Datetime.newInstance(appointmentDate, Time.newInstance(0, 0, 0, 0));
        }
    }

    public static AppointmentSummary cancelAppointment(Id patientId, Id appointmentId) {
        Appointment__c appt = loadOwnedAppointment(patientId, appointmentId);
        validateCancellable(appt);
        appt.Status__c = 'Cancelled';
        try {
            update appt;
        } catch (DmlException ex) {
            throw new AppointmentBookingException(
                'Your appointment could not be cancelled right now. Please try again or ask for a staff member.'
            );
        }
        appt = reloadAppointment(appt.Id);
        return toSummary(appt);
    }

    public static AppointmentSummary rescheduleAppointment(
        Id patientId,
        Id appointmentId,
        Id newDoctorId,
        Date newAppointmentDate,
        String newAppointmentTime,
        String slotLabel
    ) {
        Appointment__c appt = loadOwnedAppointment(patientId, appointmentId);
        validateCancellable(appt);

        Date targetDate = validateAppointmentDate(newAppointmentDate);
        String normalizedTime = normalizeTimeValue(newAppointmentTime);
        Id doctorId = newDoctorId != null ? newDoctorId : appt.Doctor__c;

        Doctor__c doctor = queryDoctorForBooking(doctorId, targetDate);
        validateSlotStillAvailable(doctor, targetDate, normalizedTime, appt.Id);

        appt.Doctor__c = doctorId;
        appt.Department__c = doctor.Department__c;
        appt.Appointment_Date__c = targetDate;
        appt.Appointment_Date_Time__c = combineDateAndTime(targetDate, normalizedTime);
        appt.Appointment_Time__c = normalizedTime;
        appt.Selected_Slot__c = String.isBlank(slotLabel) ? buildSlotLabel(normalizedTime) : slotLabel;
        appt.Status__c = 'Confirmed';

        try {
            update appt;
        } catch (DmlException ex) {
            throw new AppointmentBookingException(
                'We could not reschedule your appointment. The new slot may no longer be available.'
            );
        }
        return toSummary(reloadAppointment(appt.Id));
    }

    // ─── Patient resolution ───────────────────────────────────────────────────

    public static Id resolvePatientIdForUser(Id userId) {
        if (userId == null) {
            userId = UserInfo.getUserId();
        }
        Patient__c patient = PatientPortalLinkService.resolve(userId, UserInfo.getUserEmail());
        if (patient == null) {
            throw new AppointmentBookingException(
                'We could not find a patient profile linked to your account. Please contact the hospital reception.'
            );
        }
        ensurePatientPhoneForBooking(patient.Id);
        return patient.Id;
    }

    /**
     * When the invocable runs as the Agentforce bot user and portalUserId is blank,
     * use the demo patient from Portal_Patient_Registry (Conversation Preview / testing).
     */
    public static Id resolvePatientIdForServiceAgentFallback() {
        List<Portal_Patient_Registry__mdt> rows = [
            SELECT Patient_Record_Name__c
            FROM Portal_Patient_Registry__mdt
            WHERE Active__c = true
              AND Patient_Record_Name__c != null
            ORDER BY DeveloperName ASC
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            return null;
        }
        List<Patient__c> patients = [
            SELECT Id
            FROM Patient__c
            WHERE Name = :rows[0].Patient_Record_Name__c
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (patients.isEmpty()) {
            return null;
        }
        ensurePatientPhoneForBooking(patients[0].Id);
        return patients[0].Id;
    }

    public static List<String> listDoctorNamesForDepartment(String departmentNameInput, Date appointmentDate) {
        Id departmentId = resolveDepartmentId(departmentNameInput, null);
        if (departmentId == null) {
            throw new AppointmentBookingException(
                'We could not find that department. Please choose from Cardiology, General Medicine, Orthopedics, Neurology, Oncology, Emergency, Radiology, or Labs.'
            );
        }
        Date targetDate = appointmentDate != null ? validateAppointmentDate(appointmentDate) : Date.today();
        List<Doctor__c> doctors = queryEligibleDoctors(departmentId, null, targetDate);
        List<String> names = new List<String>();
        for (Doctor__c doctor : doctors) {
            names.add(doctor.Name);
        }
        return names;
    }

    public static String formatDoctorsForDepartment(String departmentNameInput, Date appointmentDate) {
        List<String> names = listDoctorNamesForDepartment(departmentNameInput, appointmentDate);
        if (names.isEmpty()) {
            return 'No doctors are currently listed for that department on the requested date. You can still book with any available doctor and one will be assigned.';
        }
        List<String> lines = new List<String>();
        Integer index = 1;
        for (String name : names) {
            lines.add(index + '. ' + name);
            index++;
        }
        return 'Doctors in ' + departmentNameInput.trim() + ':\n' + String.join(lines, '\n') +
            '\nYou may pick a doctor by name, or say "any doctor" to auto-assign.';
    }

    /**
     * Org WhatsApp notification flow requires Patient__c.Phone__c on insert.
     * Back-fill from the running user's phone when missing.
     */
    private static void ensurePatientPhoneForBooking(Id patientId) {
        List<Patient__c> patients = [
            SELECT Id, Phone__c
            FROM Patient__c
            WHERE Id = :patientId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (patients.isEmpty() || String.isNotBlank(patients[0].Phone__c)) {
            return;
        }
        List<User> users = [
            SELECT Phone, MobilePhone
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        if (users.isEmpty()) {
            return;
        }
        String phone = String.isNotBlank(users[0].MobilePhone)
            ? users[0].MobilePhone
            : users[0].Phone;
        if (String.isBlank(phone)) {
            return;
        }
        Patient__c updatePatient = new Patient__c(Id = patientId, Phone__c = phone);
        try {
            Database.update(updatePatient, AccessLevel.SYSTEM_MODE);
        } catch (Exception ignored) {
            // Continue; insert may still fail with a clear FLOW_TRIGGER message.
        }
    }

    public static String resolveAppointmentType(String input) {
        if (String.isBlank(input)) {
            return 'OPD';
        }
        String normalized = input.trim().toLowerCase();
        if (normalized.contains('tele') || normalized.contains('video') || normalized.contains('virtual')) {
            return 'Teleconsultation';
        }
        if (normalized.contains('follow')) {
            return 'Follow-Up';
        }
        if (normalized.contains('emergency') || normalized.contains('urgent')) {
            return 'Emergency Consultation';
        }
        if (normalized.contains('opd') || normalized.contains('outpatient') || normalized.contains('general')) {
            return 'OPD';
        }
        for (Schema.PicklistEntry entry : Appointment__c.Appointment_Type__c.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getValue().equalsIgnoreCase(input.trim())) {
                return entry.getValue();
            }
            if (entry.isActive() && entry.getLabel().equalsIgnoreCase(input.trim())) {
                return entry.getValue();
            }
        }
        throw new AppointmentBookingException(
            'Please specify a valid appointment type: OPD, Follow-Up, Teleconsultation, or Emergency Consultation.'
        );
    }

    public static String formatSlotsForConversation(List<SlotInfo> slots) {
        if (slots == null || slots.isEmpty()) {
            return 'No open appointment slots were found for the requested date.';
        }
        List<String> lines = new List<String>();
        Integer index = 1;
        for (SlotInfo slot : slots) {
            lines.add(
                index + '. ' + formatDate(slot.appointmentDate) + ' at ' + slot.slotLabel +
                ' with Dr. ' + slot.doctorName +
                ' (' + nullSafe(slot.departmentName) + ', ' + slot.appointmentTypeLabel + ')' +
                ' [doctorId=' + String.valueOf(slot.doctorId) +
                ', appointmentTime=' + slot.appointmentTime + ']'
            );
            index++;
            if (index > 20) {
                lines.add('...and more slots are available. Ask for a specific doctor or time to narrow results.');
                break;
            }
        }
        return String.join(lines, '\n');
    }

    public static String formatAppointmentsForConversation(List<AppointmentSummary> appointments) {
        if (appointments == null || appointments.isEmpty()) {
            return 'You have no upcoming appointments scheduled.';
        }
        List<String> lines = new List<String>();
        Integer index = 1;
        for (AppointmentSummary summary : appointments) {
            lines.add(index + '. ' + summary.humanReadable);
            index++;
        }
        return String.join(lines, '\n');
    }

    // ─── Internal helpers ─────────────────────────────────────────────────────

    private class SlotDefinition {
        public String label;
        public String timeValue;
        public Integer capacity;
    }

    private class SlotInfoComparator implements Comparator<SlotInfo> {
        public Integer compare(SlotInfo a, SlotInfo b) {
            if (a.appointmentDateTime == b.appointmentDateTime) {
                return a.doctorName.compareTo(b.doctorName);
            }
            if (a.appointmentDateTime == null) {
                return -1;
            }
            if (b.appointmentDateTime == null) {
                return 1;
            }
            return a.appointmentDateTime < b.appointmentDateTime ? -1 : 1;
        }
    }

    private class AppointmentSummaryComparator implements Comparator<AppointmentSummary> {
        public Integer compare(AppointmentSummary a, AppointmentSummary b) {
            if (a.appointmentDateTime == b.appointmentDateTime) {
                return nullSafe(a.confirmationNumber).compareTo(nullSafe(b.confirmationNumber));
            }
            if (a.appointmentDateTime == null) {
                return -1;
            }
            if (b.appointmentDateTime == null) {
                return 1;
            }
            return a.appointmentDateTime < b.appointmentDateTime ? -1 : 1;
        }
    }

    private static void validatePatientExists(Id patientId) {
        if (patientId == null) {
            throw new AppointmentBookingException('A patient profile is required to manage appointments.');
        }
        if ([SELECT COUNT() FROM Patient__c WHERE Id = :patientId WITH SYSTEM_MODE] == 0) {
            throw new AppointmentBookingException('The patient profile could not be found.');
        }
    }

    private static Date validateAppointmentDate(Date appointmentDate) {
        if (appointmentDate == null) {
            throw new AppointmentBookingException('Please provide an appointment date.');
        }
        if (appointmentDate < Date.today()) {
            throw new AppointmentBookingException('Appointment date cannot be in the past.');
        }
        if (appointmentDate > Date.today().addDays(MAX_BOOKING_DAYS_AHEAD)) {
            throw new AppointmentBookingException(
                'Appointments can only be booked up to ' + MAX_BOOKING_DAYS_AHEAD + ' days in advance.'
            );
        }
        return appointmentDate;
    }

    private static Id resolveDepartmentId(String departmentNameInput, String symptomOrSpecialtyInput) {
        if (!String.isBlank(departmentNameInput)) {
            List<Department__c> departments = [
                SELECT Id
                FROM Department__c
                WHERE Name LIKE :('%' + String.escapeSingleQuotes(departmentNameInput.trim()) + '%')
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (!departments.isEmpty()) {
                return departments[0].Id;
            }
        }
        if (!String.isBlank(symptomOrSpecialtyInput)) {
            String symptomHintText = symptomOrSpecialtyInput.trim().toLowerCase();
            for (String keyword : SYMPTOM_TO_DEPARTMENT.keySet()) {
                if (symptomHintText.contains(keyword)) {
                    String deptName = SYMPTOM_TO_DEPARTMENT.get(keyword);
                    List<Department__c> departments = [
                        SELECT Id FROM Department__c WHERE Name = :deptName WITH SYSTEM_MODE LIMIT 1
                    ];
                    if (!departments.isEmpty()) {
                        return departments[0].Id;
                    }
                }
            }
            for (String specialization : SPECIALIZATION_TO_DEPARTMENT.keySet()) {
                if (symptomHintText.contains(specialization.toLowerCase())) {
                    String deptName = SPECIALIZATION_TO_DEPARTMENT.get(specialization);
                    List<Department__c> departments = [
                        SELECT Id FROM Department__c WHERE Name = :deptName WITH SYSTEM_MODE LIMIT 1
                    ];
                    if (!departments.isEmpty()) {
                        return departments[0].Id;
                    }
                }
            }
        }
        return null;
    }

    private static List<Doctor__c> queryEligibleDoctors(Id departmentId, String doctorNameInput, Date targetDate) {
        String dayOfWeek = dayNameFromDate(targetDate);
        String doctorLike = isAnyDoctorPreference(doctorNameInput)
            ? null
            : (String.isBlank(doctorNameInput)
                ? null
                : '%' + String.escapeSingleQuotes(doctorNameInput.trim()) + '%');

        List<Doctor__c> doctors;
        if (departmentId != null && doctorLike != null) {
            doctors = [
                SELECT Id, Name, Department__c, Department__r.Name, Availability_Status__c,
                    Max_Daily_Appointments__c, Available_Slots_Config__c, Consultation_Duration__c,
                    Start_Time__c, End_Time__c, Monday__c, Tuesday__c, Wednesday__c, Thursday__c,
                    Friday__c, Saturday__c, Sunday__c, Available_Days__c, Active__c
                FROM Doctor__c
                WHERE Active__c = true
                  AND Department__c = :departmentId
                  AND Name LIKE :doctorLike
                WITH SYSTEM_MODE
            ];
        } else if (departmentId != null) {
            doctors = [
                SELECT Id, Name, Department__c, Department__r.Name, Availability_Status__c,
                    Max_Daily_Appointments__c, Available_Slots_Config__c, Consultation_Duration__c,
                    Start_Time__c, End_Time__c, Monday__c, Tuesday__c, Wednesday__c, Thursday__c,
                    Friday__c, Saturday__c, Sunday__c, Available_Days__c, Active__c
                FROM Doctor__c
                WHERE Active__c = true
                  AND Department__c = :departmentId
                WITH SYSTEM_MODE
            ];
        } else if (doctorLike != null) {
            doctors = [
                SELECT Id, Name, Department__c, Department__r.Name, Availability_Status__c,
                    Max_Daily_Appointments__c, Available_Slots_Config__c, Consultation_Duration__c,
                    Start_Time__c, End_Time__c, Monday__c, Tuesday__c, Wednesday__c, Thursday__c,
                    Friday__c, Saturday__c, Sunday__c, Available_Days__c, Active__c
                FROM Doctor__c
                WHERE Active__c = true
                  AND Name LIKE :doctorLike
                WITH SYSTEM_MODE
            ];
        } else {
            doctors = [
                SELECT Id, Name, Department__c, Department__r.Name, Availability_Status__c,
                    Max_Daily_Appointments__c, Available_Slots_Config__c, Consultation_Duration__c,
                    Start_Time__c, End_Time__c, Monday__c, Tuesday__c, Wednesday__c, Thursday__c,
                    Friday__c, Saturday__c, Sunday__c, Available_Days__c, Active__c
                FROM Doctor__c
                WHERE Active__c = true
                WITH SYSTEM_MODE
            ];
        }

        List<Doctor__c> eligible = new List<Doctor__c>();
        for (Doctor__c doctor : doctors) {
            if (UNAVAILABLE_DOCTOR_STATUSES.contains(doctor.Availability_Status__c)) {
                continue;
            }
            if (!isDoctorAvailableOnDay(doctor, dayOfWeek)) {
                continue;
            }
            eligible.add(doctor);
        }
        return eligible;
    }

    private static List<Doctor__c> queryDoctorsForRequestAssignment(Id departmentId, String doctorNameInput) {
        String doctorLike = isAnyDoctorPreference(doctorNameInput)
            ? null
            : (String.isBlank(doctorNameInput)
                ? null
                : '%' + String.escapeSingleQuotes(doctorNameInput.trim()) + '%');

        if (doctorLike != null) {
            return [
                SELECT Id, Name, Department__c
                FROM Doctor__c
                WHERE Active__c = true
                  AND Department__c = :departmentId
                  AND Name LIKE :doctorLike
                WITH SYSTEM_MODE
                ORDER BY Name
            ];
        }
        return [
            SELECT Id, Name, Department__c
            FROM Doctor__c
            WHERE Active__c = true
              AND Department__c = :departmentId
            WITH SYSTEM_MODE
            ORDER BY Name
        ];
    }

    private static Doctor__c queryDoctorForRequest(Id doctorId) {
        if (doctorId == null) {
            throw new AppointmentBookingException('Please select a doctor for the appointment.');
        }
        List<Doctor__c> doctors = [
            SELECT Id, Name, Department__c, Active__c
            FROM Doctor__c
            WHERE Id = :doctorId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (doctors.isEmpty()) {
            throw new AppointmentBookingException('The selected doctor could not be found.');
        }
        if (doctors[0].Active__c != true) {
            throw new AppointmentBookingException('The selected doctor is not currently accepting appointments.');
        }
        return doctors[0];
    }

    private static String resolveConcreteAppointmentTime(String appointmentTimeInput) {
        if (isTimeOfDayPreference(appointmentTimeInput)) {
            String normalized = appointmentTimeInput.trim().toLowerCase();
            if (normalized.contains('morning')) {
                return '09:00';
            }
            if (normalized.contains('afternoon')) {
                return '14:00';
            }
            if (normalized.contains('evening')) {
                return '17:00';
            }
            return '09:00';
        }
        return normalizeTimeValue(appointmentTimeInput);
    }

    private static String buildRequestSlotLabel(String appointmentTimeInput, String concreteTime) {
        if (isTimeOfDayPreference(appointmentTimeInput)) {
            return describeTimeOfDayPreference(appointmentTimeInput) + ' (requested)';
        }
        return buildSlotLabel(concreteTime);
    }

    private static String loadAppointmentName(Id appointmentId) {
        List<Appointment__c> rows = [
            SELECT Name
            FROM Appointment__c
            WHERE Id = :appointmentId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return rows.isEmpty() ? '' : rows[0].Name;
    }

    private static String resolveDepartmentName(Id departmentId) {
        if (departmentId == null) {
            return '';
        }
        List<Department__c> rows = [
            SELECT Name
            FROM Department__c
            WHERE Id = :departmentId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return rows.isEmpty() ? '' : rows[0].Name;
    }

    private static Doctor__c queryDoctorForBooking(Id doctorId, Date targetDate) {
        if (doctorId == null) {
            throw new AppointmentBookingException('Please select a doctor for the appointment.');
        }
        List<Doctor__c> doctors = [
            SELECT Id, Name, Department__c, Availability_Status__c, Max_Daily_Appointments__c,
                   Active__c, Monday__c, Tuesday__c, Wednesday__c, Thursday__c,
                   Friday__c, Saturday__c, Sunday__c, Available_Days__c,
                   Available_Slots_Config__c, Consultation_Duration__c, Start_Time__c, End_Time__c
            FROM Doctor__c
            WHERE Id = :doctorId
            LIMIT 1
        ];
        if (doctors.isEmpty()) {
            throw new AppointmentBookingException('The selected doctor could not be found.');
        }
        Doctor__c doctor = doctors[0];
        if (doctor.Active__c != true) {
            throw new AppointmentBookingException('The selected doctor is not currently accepting appointments.');
        }
        if (UNAVAILABLE_DOCTOR_STATUSES.contains(doctor.Availability_Status__c)) {
            throw new AppointmentBookingException(
                'The selected doctor is not available on that date due to ' + doctor.Availability_Status__c + '.'
            );
        }
        if (!isDoctorAvailableOnDay(doctor, dayNameFromDate(targetDate))) {
            throw new AppointmentBookingException('The selected doctor does not work on that day of the week.');
        }
        return doctor;
    }

    private static Map<Id, List<Doctor_Availability__c>> loadAvailabilityByDoctor(Set<Id> doctorIds, String dayOfWeek) {
        Map<Id, List<Doctor_Availability__c>> result = new Map<Id, List<Doctor_Availability__c>>();
        for (Doctor_Availability__c availability : [
            SELECT Id, Doctor__c, Day_of_Week__c, Start_Time__c, End_Time__c, Slot_Capacity__c, Active__c
            FROM Doctor_Availability__c
            WHERE Doctor__c IN :doctorIds
              AND Active__c = true
              AND Day_of_Week__c = :dayOfWeek
        ]) {
            if (!result.containsKey(availability.Doctor__c)) {
                result.put(availability.Doctor__c, new List<Doctor_Availability__c>());
            }
            result.get(availability.Doctor__c).add(availability);
        }
        return result;
    }

    private static Map<String, Integer> loadBookedCountsByDoctorSlot(Set<Id> doctorIds, Date targetDate) {
        Map<String, Integer> counts = new Map<String, Integer>();
        for (AggregateResult ar : [
            SELECT Doctor__c doctorId, Appointment_Time__c apptTime, COUNT(Id) total
            FROM Appointment__c
            WHERE Doctor__c IN :doctorIds
              AND Appointment_Date__c = :targetDate
              AND Status__c NOT IN :EXCLUDED_BOOKING_STATUSES
            GROUP BY Doctor__c, Appointment_Time__c
        ]) {
            counts.put(
                slotKeyFor((Id) ar.get('doctorId'), (String) ar.get('apptTime')),
                (Integer) ar.get('total')
            );
        }
        return counts;
    }

    private static Map<Id, Integer> loadDailyBookedCounts(Set<Id> doctorIds, Date targetDate) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Doctor__c doctorId, COUNT(Id) total
            FROM Appointment__c
            WHERE Doctor__c IN :doctorIds
              AND Appointment_Date__c = :targetDate
              AND Status__c NOT IN :EXCLUDED_BOOKING_STATUSES
            GROUP BY Doctor__c
        ]) {
            counts.put((Id) ar.get('doctorId'), (Integer) ar.get('total'));
        }
        return counts;
    }

    private static List<SlotDefinition> buildSlotDefinitions(
        Doctor__c doctor,
        List<Doctor_Availability__c> availabilityRecords,
        String dayOfWeek
    ) {
        List<SlotDefinition> slots = new List<SlotDefinition>();
        Set<String> dedupe = new Set<String>();

        if (availabilityRecords != null && !availabilityRecords.isEmpty()) {
            for (Doctor_Availability__c availability : availabilityRecords) {
                Integer capacity = availability.Slot_Capacity__c == null
                    ? DEFAULT_SLOT_CAPACITY
                    : Integer.valueOf(availability.Slot_Capacity__c);
                for (SlotDefinition slot : generateSlotsFromTextTimeRange(
                    availability.Start_Time__c,
                    availability.End_Time__c,
                    doctor.Consultation_Duration__c,
                    capacity
                )) {
                    if (!dedupe.contains(slot.timeValue)) {
                        dedupe.add(slot.timeValue);
                        slots.add(slot);
                    }
                }
            }
            return slots;
        }

        if (!String.isBlank(doctor.Available_Slots_Config__c)) {
            for (String configured : doctor.Available_Slots_Config__c.split(';')) {
                SlotDefinition slot = slotFromConfigLabel(configured.trim());
                if (slot != null && !dedupe.contains(slot.timeValue)) {
                    dedupe.add(slot.timeValue);
                    slots.add(slot);
                }
            }
            if (!slots.isEmpty()) {
                return slots;
            }
        }

        for (SlotDefinition slot : generateSlotsFromTimeRange(
            doctor.Start_Time__c,
            doctor.End_Time__c,
            doctor.Consultation_Duration__c,
            DEFAULT_SLOT_CAPACITY
        )) {
            if (!dedupe.contains(slot.timeValue)) {
                dedupe.add(slot.timeValue);
                slots.add(slot);
            }
        }
        return slots;
    }

    private static List<SlotDefinition> generateSlotsFromTextTimeRange(
        String startTimeText,
        String endTimeText,
        Decimal durationMinutes,
        Integer capacity
    ) {
        if (String.isBlank(startTimeText) || String.isBlank(endTimeText)) {
            return new List<SlotDefinition>();
        }
        return generateSlotsFromTimeRange(
            parseTimeText(startTimeText),
            parseTimeText(endTimeText),
            durationMinutes,
            capacity
        );
    }

    private static Time parseTimeText(String timeText) {
        String normalized = normalizeTimeValue(timeText);
        List<String> parts = normalized.split(':');
        Integer hour = Integer.valueOf(parts[0]);
        Integer minute = parts.size() > 1 ? Integer.valueOf(parts[1]) : 0;
        return Time.newInstance(hour, minute, 0, 0);
    }

    private static List<SlotDefinition> generateSlotsFromTimeRange(
        Time startTime,
        Time endTime,
        Decimal durationMinutes,
        Integer capacity
    ) {
        List<SlotDefinition> slots = new List<SlotDefinition>();
        if (startTime == null || endTime == null || startTime >= endTime) {
            return slots;
        }
        Integer step = durationMinutes == null || durationMinutes <= 0
            ? DEFAULT_SLOT_MINUTES
            : Integer.valueOf(durationMinutes);
        Integer cursor = startTime.hour() * 60 + startTime.minute();
        Integer endMinutes = endTime.hour() * 60 + endTime.minute();
        while (cursor + step <= endMinutes) {
            Integer next = cursor + step;
            String startLabel = minutesToTimeLabel(cursor);
            String endLabel = minutesToTimeLabel(next);
            SlotDefinition slot = new SlotDefinition();
            slot.timeValue = startLabel;
            slot.label = startLabel + ' - ' + endLabel;
            slot.capacity = capacity;
            slots.add(slot);
            cursor = next;
        }
        return slots;
    }

    private static SlotDefinition slotFromConfigLabel(String configuredLabel) {
        if (String.isBlank(configuredLabel)) {
            return null;
        }
        List<String> parts = configuredLabel.split(' - ');
        if (parts.isEmpty()) {
            return null;
        }
        SlotDefinition slot = new SlotDefinition();
        slot.timeValue = normalizeTimeValue(parts[0].trim());
        slot.label = configuredLabel;
        slot.capacity = DEFAULT_SLOT_CAPACITY;
        return slot;
    }

    private static void validateSlotStillAvailable(Doctor__c doctor, Date targetDate, String normalizedTime) {
        validateSlotStillAvailable(doctor, targetDate, normalizedTime, null);
    }

    private static void validateSlotStillAvailable(
        Doctor__c doctor,
        Date targetDate,
        String normalizedTime,
        Id excludeAppointmentId
    ) {
        String dayOfWeek = dayNameFromDate(targetDate);
        Map<Id, List<Doctor_Availability__c>> availabilityByDoctor = loadAvailabilityByDoctor(
            new Set<Id>{ doctor.Id },
            dayOfWeek
        );
        List<SlotDefinition> slotDefs = buildSlotDefinitions(
            doctor,
            availabilityByDoctor.get(doctor.Id),
            dayOfWeek
        );
        Boolean slotExists = false;
        Integer slotCapacity = DEFAULT_SLOT_CAPACITY;
        for (SlotDefinition slotDef : slotDefs) {
            if (slotDef.timeValue == normalizedTime) {
                slotExists = true;
                slotCapacity = slotDef.capacity == null ? DEFAULT_SLOT_CAPACITY : slotDef.capacity;
                break;
            }
        }
        if (!slotExists) {
            throw new AppointmentBookingException('The selected time is not an available slot for this doctor.');
        }

        Id doctorId = doctor.Id;
        String lockQuery =
            'SELECT Id FROM Appointment__c WHERE Doctor__c = :doctorId' +
            ' AND Appointment_Date__c = :targetDate' +
            ' AND Appointment_Time__c = :normalizedTime' +
            ' AND Status__c NOT IN :EXCLUDED_BOOKING_STATUSES';
        if (excludeAppointmentId != null) {
            lockQuery += ' AND Id != :excludeAppointmentId';
        }
        lockQuery += ' FOR UPDATE';
        List<Appointment__c> locked = Database.query(lockQuery);
        if (locked.size() >= slotCapacity) {
            throw new AppointmentBookingException(
                'Sorry, that slot was just booked by another patient. Please choose a different time.'
            );
        }

        if (doctor.Max_Daily_Appointments__c != null) {
            String dailyQuery =
                'SELECT COUNT() FROM Appointment__c WHERE Doctor__c = :doctorId' +
                ' AND Appointment_Date__c = :targetDate' +
                ' AND Status__c NOT IN :EXCLUDED_BOOKING_STATUSES';
            if (excludeAppointmentId != null) {
                dailyQuery += ' AND Id != :excludeAppointmentId';
            }
            Integer dailyCount = Database.countQuery(dailyQuery);
            if (dailyCount >= Integer.valueOf(doctor.Max_Daily_Appointments__c)) {
                throw new AppointmentBookingException(
                    'This doctor has reached the maximum number of appointments for that day.'
                );
            }
        }
    }

    private static Appointment__c loadOwnedAppointment(Id patientId, Id appointmentId) {
        if (appointmentId == null) {
            throw new AppointmentBookingException('Please specify which appointment to manage.');
        }
        List<Appointment__c> appointments = [
            SELECT Id, Patient__c, Doctor__c, Department__c, Status__c, Appointment_Date_Time__c,
                   Appointment_Date__c, Appointment_Time__c, Name, Appointment_Type__c,
                   Doctor__r.Name, Department__r.Name
            FROM Appointment__c
            WHERE Id = :appointmentId
            LIMIT 1
        ];
        if (appointments.isEmpty()) {
            throw new AppointmentBookingException('The appointment could not be found.');
        }
        Appointment__c appt = appointments[0];
        if (appt.Patient__c != patientId) {
            throw new AppointmentBookingException('You can only manage your own appointments.');
        }
        return appt;
    }

    private static void validateCancellable(Appointment__c appt) {
        if (appt.Appointment_Date_Time__c != null && appt.Appointment_Date_Time__c < Datetime.now()) {
            throw new AppointmentBookingException('Past appointments cannot be changed through self-service.');
        }
        if (!CANCELLABLE_STATUSES.contains(appt.Status__c)) {
            throw new AppointmentBookingException(
                'This appointment cannot be changed because its status is ' + appt.Status__c + '.'
            );
        }
    }

    private static Appointment__c reloadAppointment(Id appointmentId) {
        return [
            SELECT Id, Name, Appointment_Date_Time__c, Appointment_Date__c, Appointment_Time__c,
                   Status__c, Appointment_Type__c, Doctor__r.Name, Department__r.Name
            FROM Appointment__c
            WHERE Id = :appointmentId
            LIMIT 1
        ];
    }

    private static AppointmentSummary toSummary(Appointment__c appt) {
        AppointmentSummary summary = new AppointmentSummary();
        summary.appointmentId = appt.Id;
        summary.confirmationNumber = appt.Name;
        summary.appointmentDateTime = resolveAppointmentDateTime(
            appt.Appointment_Date__c,
            appt.Appointment_Time__c,
            appt.Appointment_Date_Time__c
        );
        summary.doctorName = appt.Doctor__r == null ? null : appt.Doctor__r.Name;
        summary.departmentName = appt.Department__r == null ? null : appt.Department__r.Name;
        summary.appointmentTypeLabel = appointmentTypeLabel(appt.Appointment_Type__c);
        summary.status = appt.Status__c;
        String whenLabel = summary.appointmentDateTime != null
            ? formatDateTime(summary.appointmentDateTime)
            : (appt.Appointment_Date__c != null ? formatDate(appt.Appointment_Date__c) : 'Date TBD');
        summary.humanReadable = summary.confirmationNumber + ': ' +
            whenLabel +
            ' with Dr. ' + nullSafe(summary.doctorName) +
            ' (' + nullSafe(summary.departmentName) + ', ' +
            nullSafe(summary.appointmentTypeLabel) + ') — Status: ' + nullSafe(summary.status);
        return summary;
    }

    /**
     * Resolves doctor and time for a patient appointment request without requiring open slots.
     * Auto-assigns the first active doctor in the department when doctorId is blank.
     */
    public static SlotInfo resolveAppointmentRequestSlot(
        Id doctorId,
        Date targetDate,
        String appointmentTimeInput,
        String departmentNameInput,
        String doctorNameInput
    ) {
        if (String.isBlank(appointmentTimeInput)) {
            throw new AppointmentBookingException('Please provide an appointment time or time-of-day preference.');
        }

        Id resolvedDoctorId = doctorId;
        if (resolvedDoctorId == null) {
            Id departmentId = resolveDepartmentId(departmentNameInput, null);
            if (departmentId == null) {
                throw new AppointmentBookingException(
                    'Please provide a department or specialty when you have no doctor preference.'
                );
            }
            List<Doctor__c> doctors = queryDoctorsForRequestAssignment(departmentId, doctorNameInput);
            if (doctors.isEmpty()) {
                throw new AppointmentBookingException(
                    'No doctor was found in that department. Please check the department name or contact reception.'
                );
            }
            resolvedDoctorId = doctors[0].Id;
        }

        String concreteTime = resolveConcreteAppointmentTime(appointmentTimeInput);
        SlotInfo info = new SlotInfo();
        info.doctorId = resolvedDoctorId;
        info.appointmentTime = concreteTime;
        info.slotLabel = buildRequestSlotLabel(appointmentTimeInput, concreteTime);
        return info;
    }

    public static SlotInfo resolveBookableSlot(
        Id patientId,
        Id doctorId,
        Date targetDate,
        String appointmentTimeInput,
        String appointmentType,
        String departmentNameInput,
        String doctorNameInput
    ) {
        if (String.isBlank(appointmentTimeInput)) {
            throw new AppointmentBookingException('Please provide an appointment time or time-of-day preference.');
        }

        String trimmedTime = appointmentTimeInput.trim();
        if (doctorId != null && !isTimeOfDayPreference(trimmedTime)) {
            normalizeTimeValue(trimmedTime);
            SlotInfo explicit = new SlotInfo();
            explicit.doctorId = doctorId;
            explicit.appointmentTime = normalizeTimeValue(trimmedTime);
            return explicit;
        }

        List<SlotInfo> candidates = findAvailableSlots(
            patientId,
            targetDate,
            appointmentType,
            departmentNameInput,
            doctorNameInput,
            null,
            isTimeOfDayPreference(trimmedTime) ? trimmedTime : null
        );

        if (doctorId != null) {
            List<SlotInfo> doctorSlots = new List<SlotInfo>();
            for (SlotInfo slot : candidates) {
                if (slot.doctorId == doctorId) {
                    doctorSlots.add(slot);
                }
            }
            candidates = doctorSlots;
        }

        if (candidates.isEmpty()) {
            String preferenceLabel = isTimeOfDayPreference(trimmedTime)
                ? ' in the ' + trimmedTime.toLowerCase()
                : '';
            throw new AppointmentBookingException(
                'No open appointment slots were found' + preferenceLabel +
                ' for the requested date and department. Please try another day or time.'
            );
        }

        if (!isTimeOfDayPreference(trimmedTime)) {
            String normalizedTime = normalizeTimeValue(trimmedTime);
            for (SlotInfo slot : candidates) {
                if (slot.appointmentTime == normalizedTime) {
                    return slot;
                }
            }
            throw new AppointmentBookingException(
                'The selected time is no longer available. Please choose another slot from the available list.'
            );
        }

        return candidates[0];
    }

    public static List<SlotInfo> filterSlotsByTimeOfDay(List<SlotInfo> slots, String timeOfDayPreference) {
        if (slots == null || slots.isEmpty() || String.isBlank(timeOfDayPreference)) {
            return slots == null ? new List<SlotInfo>() : slots;
        }
        if (!isTimeOfDayPreference(timeOfDayPreference)) {
            return slots;
        }

        Integer startMinutes;
        Integer endMinutes;
        String normalizedPreference = timeOfDayPreference.trim().toLowerCase();
        if (normalizedPreference.contains('morning')) {
            startMinutes = MORNING_START_MINUTES;
            endMinutes = MORNING_END_MINUTES;
        } else if (normalizedPreference.contains('afternoon')) {
            startMinutes = AFTERNOON_START_MINUTES;
            endMinutes = AFTERNOON_END_MINUTES;
        } else if (normalizedPreference.contains('evening')) {
            startMinutes = EVENING_START_MINUTES;
            endMinutes = EVENING_END_MINUTES;
        } else {
            return slots;
        }

        List<SlotInfo> filtered = new List<SlotInfo>();
        for (SlotInfo slot : slots) {
            Integer slotMinutes = timeStringToMinutes(slot.appointmentTime);
            if (slotMinutes >= startMinutes && slotMinutes < endMinutes) {
                filtered.add(slot);
            }
        }
        return filtered;
    }

    public static Boolean isTimeOfDayPreference(String value) {
        if (String.isBlank(value)) {
            return false;
        }
        String normalized = value.trim().toLowerCase();
        return normalized.contains('morning')
            || normalized.contains('afternoon')
            || normalized.contains('evening');
    }

    public static String describeTimeOfDayPreference(String value) {
        if (String.isBlank(value)) {
            return '';
        }
        String normalized = value.trim().toLowerCase();
        if (normalized.contains('morning')) {
            return 'the morning';
        }
        if (normalized.contains('afternoon')) {
            return 'the afternoon';
        }
        if (normalized.contains('evening')) {
            return 'the evening';
        }
        return value;
    }

    private static Integer timeStringToMinutes(String timeValue) {
        String normalized = normalizeTimeValue(timeValue);
        List<String> parts = normalized.split(':');
        return Integer.valueOf(parts[0]) * 60 + Integer.valueOf(parts[1]);
    }

    private static String buildBookingMessage(
        String appointmentType,
        String confirmationNumber,
        String doctorName,
        String departmentName,
        Date appointmentDate,
        String appointmentTime
    ) {
        String timeDescription = isTimeOfDayPreference(appointmentTime)
            ? describeTimeOfDayPreference(appointmentTime)
            : 'at ' + appointmentTime;
        String doctorDescription = String.isBlank(doctorName)
            ? 'any available doctor'
            : 'Dr. ' + doctorName;
        String base = 'Your appointment request for ' + nullSafe(departmentName) +
            ' with ' + doctorDescription +
            ' on ' + formatDate(appointmentDate) + ' ' + timeDescription +
            ' has been submitted for doctor approval. Reference number: ' + confirmationNumber +
            '. You will receive a WhatsApp message once the doctor approves your appointment.';
        if (appointmentType == 'Teleconsultation') {
            return base + ' A secure video link will be sent separately if your request is approved.';
        }
        return base;
    }

    private static String appointmentTypeLabel(String apiValue) {
        if (String.isBlank(apiValue)) {
            return 'OPD';
        }
        for (Schema.PicklistEntry entry : Appointment__c.Appointment_Type__c.getDescribe().getPicklistValues()) {
            if (entry.getValue() == apiValue) {
                return entry.getLabel();
            }
        }
        return apiValue;
    }

    private static Boolean isDoctorAvailableOnDay(Doctor__c doctor, String dayOfWeek) {
        if (!String.isBlank(doctor.Available_Days__c) &&
            doctor.Available_Days__c.contains(dayOfWeek)) {
            return true;
        }
        if (dayOfWeek == 'Monday' && doctor.Monday__c == true) return true;
        if (dayOfWeek == 'Tuesday' && doctor.Tuesday__c == true) return true;
        if (dayOfWeek == 'Wednesday' && doctor.Wednesday__c == true) return true;
        if (dayOfWeek == 'Thursday' && doctor.Thursday__c == true) return true;
        if (dayOfWeek == 'Friday' && doctor.Friday__c == true) return true;
        if (dayOfWeek == 'Saturday' && doctor.Saturday__c == true) return true;
        if (dayOfWeek == 'Sunday' && doctor.Sunday__c == true) return true;
        return false;
    }

    private static String dayNameFromDate(Date targetDate) {
        Datetime dt = Datetime.newInstance(targetDate, Time.newInstance(12, 0, 0, 0));
        return dt.format('EEEE');
    }

    private static Datetime combineDateAndTime(Date targetDate, String timeValue) {
        List<String> parts = normalizeTimeValue(timeValue).split(':');
        Integer hour = Integer.valueOf(parts[0]);
        Integer minute = parts.size() > 1 ? Integer.valueOf(parts[1]) : 0;
        return Datetime.newInstance(targetDate, Time.newInstance(hour, minute, 0, 0));
    }

    public static Boolean isAnyDoctorPreference(String value) {
        if (String.isBlank(value)) {
            return true;
        }
        String normalized = value.trim().toLowerCase();
        return normalized.contains('any doctor')
            || normalized.contains('any available')
            || normalized.contains('no preference')
            || normalized.contains('no doctor')
            || normalized.equals('any')
            || normalized.equals('none');
    }

    private static String normalizeTimeValue(String timeValue) {
        if (String.isBlank(timeValue)) {
            throw new AppointmentBookingException('Please provide an appointment time.');
        }
        String trimmed = timeValue.trim();
        if (isTimeOfDayPreference(trimmed)) {
            return trimmed;
        }
        String normalizedClock = parseFlexibleClockTime(trimmed);
        if (normalizedClock != null) {
            return normalizedClock;
        }
        throw new AppointmentBookingException(
            'Could not understand the time "' + trimmed +
            '". Please use a format like 10:00, 10am, or morning.'
        );
    }

    /**
     * Accepts common patient/agent inputs: 10am, 10:30 AM, 4pm, 16:00, 10.
     * Returns HH:MM in 24-hour form, or null when the value is not a clock time.
     */
    private static String parseFlexibleClockTime(String timeValue) {
        if (String.isBlank(timeValue)) {
            return null;
        }
        String compact = timeValue.trim().toLowerCase().replace(' ', '');
        Boolean hasAm = compact.endsWith('am');
        Boolean hasPm = compact.endsWith('pm');
        if (hasAm || hasPm) {
            compact = compact.substring(0, compact.length() - 2);
        }

        Integer hour;
        Integer minute = 0;
        try {
            if (compact.contains(':')) {
                List<String> parts = compact.split(':');
                hour = Integer.valueOf(parts[0]);
                minute = Integer.valueOf(parts.size() > 1 ? parts[1].left(2) : '0');
            } else {
                hour = Integer.valueOf(compact);
            }
        } catch (Exception ex) {
            return null;
        }

        if (minute < 0 || minute > 59) {
            return null;
        }
        if (hasPm && hour >= 1 && hour <= 11) {
            hour += 12;
        } else if (hasAm && hour == 12) {
            hour = 0;
        } else if (!hasAm && !hasPm && (hour < 0 || hour > 23)) {
            return null;
        } else if ((hasAm || hasPm) && (hour < 1 || hour > 12)) {
            return null;
        }

        return String.valueOf(hour).leftPad(2, '0') + ':' + String.valueOf(minute).leftPad(2, '0');
    }

    private static String buildSlotLabel(String timeValue) {
        List<String> parts = timeValue.split(':');
        Integer hour = Integer.valueOf(parts[0]);
        Integer minute = Integer.valueOf(parts[1]);
        Integer endTotal = hour * 60 + minute + DEFAULT_SLOT_MINUTES;
        return timeValue + ' - ' + minutesToTimeLabel(endTotal);
    }

    private static String minutesToTimeLabel(Integer totalMinutes) {
        Integer hour = totalMinutes / 60;
        Integer minute = Math.mod(totalMinutes, 60);
        return String.valueOf(hour).leftPad(2, '0') + ':' + String.valueOf(minute).leftPad(2, '0');
    }

    private static String slotKeyFor(Id doctorId, String timeValue) {
        return String.valueOf(doctorId) + '|' + normalizeTimeValue(timeValue);
    }

    private static String formatDate(Date value) {
        return value == null ? '' : value.format();
    }

    private static String formatDateTime(Datetime value) {
        return value == null ? '' : value.format('dd MMM yyyy, hh:mm a');
    }

    private static String nullSafe(String value) {
        return value == null ? 'N/A' : value;
    }
}