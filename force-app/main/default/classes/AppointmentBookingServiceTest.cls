@IsTest
private class AppointmentBookingServiceTest {

    private static Date bookingDate() {
        return Date.today().addDays(1);
    }

    private static void setCalloutMock() {
        Test.setMock(HttpCalloutMock.class, new WhatsAppCalloutMock());
    }

    @TestSetup
    static void setupData() {
        Department__c cardiology = new Department__c(Name = 'Cardiology', Is_Medical_Department__c = true);
        Department__c general = new Department__c(Name = 'General Medicine', Is_Medical_Department__c = true);
        Department__c orthopedics = new Department__c(Name = 'Orthopedics', Is_Medical_Department__c = true);
        insert new List<Department__c>{ cardiology, general, orthopedics };

        Doctor__c availableDoctor = buildDoctor(
            'Dr Ava Available',
            cardiology.Id,
            'Available',
            true,
            '08:00 - 08:30;09:00 - 09:30;10:00 - 10:30'
        );
        Doctor__c leaveDoctor = buildDoctor(
            'Dr Leo Leave',
            general.Id,
            'On Leave',
            true,
            '08:00 - 08:30;09:00 - 09:30'
        );
        Doctor__c bulkDoctor = buildDoctor(
            'Dr Bulk Two',
            general.Id,
            'Available',
            true,
            '11:00 - 11:30;14:00 - 14:30'
        );
        Doctor__c orthoDoctor = buildDoctor(
            'Dr Ortho Morning',
            orthopedics.Id,
            'Available',
            true,
            '08:00 - 08:30;09:00 - 09:30;10:00 - 10:30'
        );
        insert new List<Doctor__c>{ availableDoctor, leaveDoctor, bulkDoctor, orthoDoctor };

        insert new Doctor_Availability__c(
            Doctor__c = availableDoctor.Id,
            Day_of_Week__c = dayNameFromDate(bookingDate()),
            Start_Time__c = '08:00',
            End_Time__c = '10:00',
            Slot_Capacity__c = 1,
            Active__c = true
        );
        insert new Doctor_Availability__c(
            Doctor__c = bulkDoctor.Id,
            Day_of_Week__c = dayNameFromDate(bookingDate()),
            Start_Time__c = '11:00',
            End_Time__c = '12:00',
            Slot_Capacity__c = 2,
            Active__c = true
        );
        insert new Doctor_Availability__c(
            Doctor__c = bulkDoctor.Id,
            Day_of_Week__c = dayNameFromDate(bookingDate().addDays(1)),
            Start_Time__c = '14:00',
            End_Time__c = '15:00',
            Slot_Capacity__c = 1,
            Active__c = true
        );
        insert new Doctor_Availability__c(
            Doctor__c = orthoDoctor.Id,
            Day_of_Week__c = dayNameFromDate(bookingDate()),
            Start_Time__c = '08:00',
            End_Time__c = '12:00',
            Slot_Capacity__c = 1,
            Active__c = true
        );
        insert new Doctor_Availability__c(
            Doctor__c = orthoDoctor.Id,
            Day_of_Week__c = dayNameFromDate(bookingDate().addDays(2)),
            Start_Time__c = '08:00',
            End_Time__c = '12:00',
            Slot_Capacity__c = 1,
            Active__c = true
        );

        Patient__c ownerPatient = new Patient__c(
            Name = 'Owner Patient',
            Status__c = 'Active',
            Portal_User__c = UserInfo.getUserId(),
            Phone__c = '9380653724'
        );
        Patient__c otherPatient = new Patient__c(
            Name = 'Other Patient',
            Status__c = 'Active',
            Phone__c = '9000000001'
        );
        insert new List<Patient__c>{ ownerPatient, otherPatient };
    }

    @IsTest
    static void testBookOpdAppointment() {
        setCalloutMock();
        Patient__c patient = [SELECT Id FROM Patient__c WHERE Name = 'Owner Patient' LIMIT 1];
        Doctor__c doctor = [SELECT Id FROM Doctor__c WHERE Name = 'Dr Ava Available' LIMIT 1];
        Date targetDate = bookingDate();

        Test.startTest();
        AppointmentBookingService.BookingResult result = AppointmentBookingService.bookAppointment(
            patient.Id,
            doctor.Id,
            targetDate,
            '08:00',
            'OPD',
            'Routine checkup',
            '08:00 - 08:30'
        );
        Test.stopTest();

        System.assertNotEquals(null, result.confirmationNumber);
        System.assert(result.confirmationNumber.startsWith('APT-'));
        System.assertEquals('Requested', result.status);
        System.assert(result.message.contains('submitted'), 'Success message should describe a submitted request.');

        Appointment__c appt = [
            SELECT Appointment_Type__c, Source__c, Status__c
            FROM Appointment__c
            WHERE Id = :result.appointmentId
        ];
        System.assertEquals('OPD', appt.Appointment_Type__c);
        System.assertEquals('Agent', appt.Source__c);
        System.assertEquals('Requested', appt.Status__c);
    }

    @IsTest
    static void testBookAnyDoctorMorningPreference() {
        setCalloutMock();
        Patient__c patient = [SELECT Id FROM Patient__c WHERE Name = 'Owner Patient' LIMIT 1];
        Date targetDate = bookingDate();

        Test.startTest();
        AppointmentBookingService.BookingResult result = AppointmentBookingService.bookAppointment(
            patient.Id,
            null,
            targetDate,
            'morning',
            'OPD',
            'Joint pain',
            null,
            'Orthopedics',
            'any doctor'
        );
        Test.stopTest();

        System.assertNotEquals(null, result.appointmentId, 'A real appointment record must be created.');
        System.assertNotEquals(null, result.confirmationNumber);
        System.assertEquals('Requested', result.status);
        System.assert(result.message.contains('submitted'));
        System.assert(result.message.contains('Orthopedics'));

        Appointment__c appt = [
            SELECT Status__c, Source__c, Doctor__r.Name, Department__r.Name, Appointment_Time__c
            FROM Appointment__c
            WHERE Id = :result.appointmentId
        ];
        System.assertEquals('Requested', appt.Status__c);
        System.assertEquals('Agent', appt.Source__c);
        System.assertEquals('Orthopedics', appt.Department__r.Name);
        System.assertEquals('Dr Ortho Morning', appt.Doctor__r.Name);
        System.assert(Integer.valueOf(appt.Appointment_Time__c.split(':')[0]) < 12, 'Morning slot should be before noon.');
    }

    @IsTest
    static void testInvocableBookAnyDoctorMorningReturnsErrorWhenMissingDepartment() {
        Patient__c patient = [SELECT Id FROM Patient__c WHERE Name = 'Owner Patient' LIMIT 1];
        Date targetDate = bookingDate();

        AppointmentBookingInvocableBook.Request bookReq = new AppointmentBookingInvocableBook.Request();
        bookReq.appointmentDate = String.valueOf(targetDate);
        bookReq.appointmentTime = 'morning';
        bookReq.appointmentType = 'OPD';
        bookReq.doctorName = 'any doctor';

        Test.startTest();
        List<AppointmentBookingInvocableBook.Response> responses =
            AppointmentBookingInvocableBook.book(
                new List<AppointmentBookingInvocableBook.Request>{ bookReq }
            );
        Test.stopTest();

        System.assertEquals(false, responses[0].isSuccess);
        System.assertNotEquals(null, responses[0].errorMessage);
        System.assert(responses[0].errorMessage.contains('department'));
    }

    @IsTest
    static void testFindSlotsFiltersMorningPreference() {
        Patient__c patient = [SELECT Id FROM Patient__c WHERE Name = 'Owner Patient' LIMIT 1];
        Date targetDate = bookingDate();

        Test.startTest();
        List<AppointmentBookingService.SlotInfo> morningSlots = AppointmentBookingService.findAvailableSlots(
            patient.Id,
            targetDate,
            'OPD',
            'Orthopedics',
            null,
            null,
            'morning'
        );
        Test.stopTest();

        System.assert(morningSlots.size() > 0);
        for (AppointmentBookingService.SlotInfo slot : morningSlots) {
            System.assert(Integer.valueOf(slot.appointmentTime.split(':')[0]) < 12);
        }
    }

    @IsTest
    static void testBookTeleconsultationAppointment() {
        setCalloutMock();
        Patient__c patient = [SELECT Id FROM Patient__c WHERE Name = 'Owner Patient' LIMIT 1];
        Doctor__c doctor = [SELECT Id FROM Doctor__c WHERE Name = 'Dr Ava Available' LIMIT 1];

        Test.startTest();
        AppointmentBookingService.BookingResult result = AppointmentBookingService.bookAppointment(
            patient.Id,
            doctor.Id,
            bookingDate(),
            '09:00',
            'teleconsultation',
            'Follow-up cough',
            '09:00 - 09:30'
        );
        Test.stopTest();

        System.assert(result.message.contains('video link') || result.message.contains('video'), 'Teleconsultation should mention separate video link.');
        Appointment__c appt = [
            SELECT Appointment_Type__c FROM Appointment__c WHERE Id = :result.appointmentId
        ];
        System.assertEquals('Teleconsultation', appt.Appointment_Type__c);
    }

    @IsTest
    static void testRequestBookingAllowsDuplicateSlotRequests() {
        setCalloutMock();
        Patient__c patient = [SELECT Id FROM Patient__c WHERE Name = 'Owner Patient' LIMIT 1];
        Doctor__c doctor = [SELECT Id, Department__c FROM Doctor__c WHERE Name = 'Dr Ava Available' LIMIT 1];
        Date targetDate = bookingDate();

        insert new Appointment__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = doctor.Department__c,
            Appointment_Date__c = targetDate,
            Appointment_Date_Time__c = Datetime.newInstance(targetDate, Time.newInstance(8, 0, 0, 0)),
            Appointment_Time__c = '08:00',
            Status__c = 'Confirmed',
            Source__c = 'Reception'
        );

        Test.startTest();
        AppointmentBookingService.BookingResult result = AppointmentBookingService.bookAppointment(
            patient.Id,
            doctor.Id,
            targetDate,
            '08:00',
            'OPD',
            null,
            '08:00 - 08:30'
        );
        Test.stopTest();

        System.assertNotEquals(null, result.appointmentId);
        System.assertEquals('Requested', result.status);
    }

    @IsTest
    static void testDoctorOnLeaveExcludedFromSlots() {
        Patient__c patient = [SELECT Id FROM Patient__c WHERE Name = 'Owner Patient' LIMIT 1];
        Date targetDate = bookingDate();

        Test.startTest();
        List<AppointmentBookingService.SlotInfo> slots = AppointmentBookingService.findAvailableSlots(
            patient.Id,
            targetDate,
            'OPD',
            'General Medicine',
            null,
            null
        );
        Test.stopTest();

        for (AppointmentBookingService.SlotInfo slot : slots) {
            System.assertNotEquals('Dr Leo Leave', slot.doctorName);
        }
    }

    @IsTest
    static void testCancelByWrongPatientRejected() {
        setCalloutMock();
        Patient__c owner = [SELECT Id FROM Patient__c WHERE Name = 'Owner Patient' LIMIT 1];
        Patient__c other = [SELECT Id FROM Patient__c WHERE Name = 'Other Patient' LIMIT 1];
        Doctor__c doctor = [SELECT Id, Department__c FROM Doctor__c WHERE Name = 'Dr Ava Available' LIMIT 1];
        Date targetDate = bookingDate();

        Appointment__c appt = new Appointment__c(
            Patient__c = owner.Id,
            Doctor__c = doctor.Id,
            Department__c = doctor.Department__c,
            Appointment_Date__c = targetDate,
            Appointment_Date_Time__c = Datetime.newInstance(targetDate, Time.newInstance(10, 0, 0, 0)),
            Appointment_Time__c = '10:00',
            Status__c = 'Confirmed',
            Source__c = 'Agent'
        );
        insert appt;

        Boolean thrown = false;
        Test.startTest();
        try {
            AppointmentBookingService.cancelAppointment(other.Id, appt.Id);
        } catch (AppointmentBookingException ex) {
            thrown = true;
            System.assert(ex.getMessage().contains('own appointments'));
        }
        Test.stopTest();
        System.assertEquals(true, thrown);
    }

    @IsTest
    static void testCancelCompletedAppointmentRejected() {
        setCalloutMock();
        Patient__c patient = [SELECT Id FROM Patient__c WHERE Name = 'Owner Patient' LIMIT 1];
        Doctor__c doctor = [SELECT Id, Department__c FROM Doctor__c WHERE Name = 'Dr Ava Available' LIMIT 1];

        Appointment__c appt = new Appointment__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = doctor.Department__c,
            Appointment_Date__c = bookingDate(),
            Appointment_Date_Time__c = Datetime.newInstance(bookingDate(), Time.newInstance(10, 0, 0, 0)),
            Appointment_Time__c = '10:00',
            Status__c = 'Completed',
            Source__c = 'Agent'
        );
        insert appt;

        Boolean thrown = false;
        Test.startTest();
        try {
            AppointmentBookingService.cancelAppointment(patient.Id, appt.Id);
        } catch (AppointmentBookingException ex) {
            thrown = true;
            System.assert(ex.getMessage().contains('cannot be changed'));
        }
        Test.stopTest();
        System.assertEquals(true, thrown);
    }

    @IsTest
    static void testReschedulePastAppointmentRejected() {
        setCalloutMock();
        Patient__c patient = [SELECT Id FROM Patient__c WHERE Name = 'Owner Patient' LIMIT 1];
        Doctor__c doctor = [SELECT Id, Department__c FROM Doctor__c WHERE Name = 'Dr Ava Available' LIMIT 1];

        Appointment__c appt = new Appointment__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = doctor.Department__c,
            Appointment_Date__c = bookingDate(),
            Appointment_Date_Time__c = Datetime.newInstance(bookingDate(), Time.newInstance(10, 0, 0, 0)),
            Appointment_Time__c = '10:00',
            Status__c = 'Completed',
            Source__c = 'Agent'
        );
        insert appt;

        Boolean thrown = false;
        Test.startTest();
        try {
            AppointmentBookingService.rescheduleAppointment(
                patient.Id,
                appt.Id,
                doctor.Id,
                bookingDate(),
                '09:00',
                '09:00 - 09:30'
            );
        } catch (AppointmentBookingException ex) {
            thrown = true;
            System.assert(ex.getMessage().contains('cannot be changed'));
        }
        Test.stopTest();
        System.assertEquals(true, thrown);
    }

    @IsTest
    static void testBulkSlotQueryAcrossDoctorsAndDates() {
        Patient__c patient = [SELECT Id FROM Patient__c WHERE Name = 'Owner Patient' LIMIT 1];
        Date dayOne = bookingDate();
        Date dayTwo = bookingDate().addDays(1);

        Test.startTest();
        List<AppointmentBookingService.SlotInfo> dayOneSlots = AppointmentBookingService.findAvailableSlots(
            patient.Id, dayOne, 'Follow-Up', null, null, null
        );
        List<AppointmentBookingService.SlotInfo> dayTwoSlots = AppointmentBookingService.findAvailableSlots(
            patient.Id, dayTwo, 'OPD', 'General Medicine', null, null
        );
        Test.stopTest();

        System.assert(dayOneSlots.size() > 0, 'Expected slots on first date.');
        System.assert(dayTwoSlots.size() > 0, 'Expected slots on second date.');

        Set<String> doctorNames = new Set<String>();
        for (AppointmentBookingService.SlotInfo slot : dayOneSlots) {
            doctorNames.add(slot.doctorName);
        }
        System.assert(doctorNames.size() >= 2, 'Bulk query should span multiple doctors.');
    }

    @IsTest
    static void testListUpcomingAndCancelHappyPath() {
        setCalloutMock();
        Patient__c patient = [SELECT Id FROM Patient__c WHERE Name = 'Owner Patient' LIMIT 1];
        Doctor__c doctor = [SELECT Id FROM Doctor__c WHERE Name = 'Dr Bulk Two' LIMIT 1];
        Date targetDate = bookingDate();

        AppointmentBookingService.BookingResult booked = AppointmentBookingService.bookAppointment(
            patient.Id,
            doctor.Id,
            targetDate,
            '11:00',
            'Follow-Up',
            null,
            '11:00 - 11:30'
        );

        Test.startTest();
        List<AppointmentBookingService.AppointmentSummary> upcoming =
            AppointmentBookingService.listUpcomingAppointments(patient.Id);
        AppointmentBookingService.AppointmentSummary cancelled =
            AppointmentBookingService.cancelAppointment(patient.Id, booked.appointmentId);
        Test.stopTest();

        System.assert(upcoming.size() > 0);
        System.assertEquals('Cancelled', cancelled.status);
    }

    @IsTest
    static void testListUpcomingIncludesPortalStyleDateTimeFields() {
        setCalloutMock();
        Patient__c patient = [SELECT Id FROM Patient__c WHERE Name = 'Owner Patient' LIMIT 1];
        Doctor__c doctor = [SELECT Id, Department__c FROM Doctor__c WHERE Name = 'Dr Bulk Two' LIMIT 1];
        Date targetDate = bookingDate();

        insert new Appointment__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = doctor.Department__c,
            Appointment_Type__c = 'OPD',
            Appointment_Date__c = targetDate,
            Appointment_Time__c = '09:00',
            Status__c = 'Requested',
            Source__c = 'Patient Portal'
        );

        Test.startTest();
        List<AppointmentBookingService.AppointmentSummary> upcoming =
            AppointmentBookingService.listUpcomingAppointments(patient.Id);
        Test.stopTest();

        System.assert(
            upcoming.size() > 0,
            'Portal-style appointments without Appointment_Date_Time__c should still appear.'
        );
        Boolean foundPortalStyle = false;
        for (AppointmentBookingService.AppointmentSummary summary : upcoming) {
            if (summary.appointmentDateTime != null
                && summary.appointmentDateTime.date() == targetDate) {
                foundPortalStyle = true;
                break;
            }
        }
        System.assert(foundPortalStyle, 'Expected resolved datetime from date and time fields.');
    }

    @IsTest
    static void testFlexibleTimeParsingForAgentInput() {
        setCalloutMock();
        Patient__c patient = [SELECT Id FROM Patient__c WHERE Name = 'Owner Patient' LIMIT 1];
        Doctor__c doctor = [SELECT Id FROM Doctor__c WHERE Name = 'Dr Ava Available' LIMIT 1];
        Date targetDate = bookingDate();

        List<String> timeInputs = new List<String>{ '10am', '10:30 AM', '4pm', '16:00', '10' };
        for (String timeInput : timeInputs) {
            AppointmentBookingService.BookingResult result = AppointmentBookingService.bookAppointment(
                patient.Id,
                doctor.Id,
                targetDate,
                timeInput,
                'OPD',
                null,
                null
            );
            System.assertNotEquals(null, result.appointmentId, 'Booking should succeed for time: ' + timeInput);
        }
    }

    @IsTest
    static void testInvocableFindSlotsAndBook() {
        setCalloutMock();
        Doctor__c doctor = [SELECT Id FROM Doctor__c WHERE Name = 'Dr Ava Available' LIMIT 1];
        Date targetDate = bookingDate();

        AppointmentBookingInvocableFindSlots.Request findReq = new AppointmentBookingInvocableFindSlots.Request();
        findReq.appointmentDate = String.valueOf(targetDate);
        findReq.appointmentType = 'OPD';

        AppointmentBookingInvocableBook.Request bookReq = new AppointmentBookingInvocableBook.Request();
        bookReq.doctorId = String.valueOf(doctor.Id);
        bookReq.appointmentDate = String.valueOf(targetDate);
        bookReq.appointmentTime = '09:30';
        bookReq.appointmentType = 'OPD';

        Test.startTest();
        List<AppointmentBookingInvocableFindSlots.Response> findResponses =
            AppointmentBookingInvocableFindSlots.findSlots(
                new List<AppointmentBookingInvocableFindSlots.Request>{ findReq }
            );
        List<AppointmentBookingInvocableBook.Response> bookResponses =
            AppointmentBookingInvocableBook.book(
                new List<AppointmentBookingInvocableBook.Request>{ bookReq }
            );
        Test.stopTest();

        System.assertEquals(true, findResponses[0].isSuccess);
        System.assert(findResponses[0].slotCount > 0);
        System.assertEquals(true, bookResponses[0].isSuccess);
        System.assertNotEquals(null, bookResponses[0].confirmationNumber);
        System.assert(bookResponses[0].confirmationMessage.contains('submitted'));
        System.assertEquals('Requested', [
            SELECT Status__c FROM Appointment__c WHERE Name = :bookResponses[0].confirmationNumber LIMIT 1
        ].Status__c);
    }

    @IsTest
    static void testRescheduleHappyPath() {
        setCalloutMock();
        Patient__c patient = [SELECT Id FROM Patient__c WHERE Name = 'Owner Patient' LIMIT 1];
        Doctor__c doctor = [SELECT Id FROM Doctor__c WHERE Name = 'Dr Ava Available' LIMIT 1];
        Date targetDate = bookingDate();

        AppointmentBookingService.BookingResult booked = AppointmentBookingService.bookAppointment(
            patient.Id,
            doctor.Id,
            targetDate,
            '08:00',
            'Follow-Up',
            null,
            '08:00 - 08:30'
        );

        Test.startTest();
        AppointmentBookingService.AppointmentSummary rescheduled =
            AppointmentBookingService.rescheduleAppointment(
                patient.Id,
                booked.appointmentId,
                doctor.Id,
                targetDate,
                '09:00',
                '09:00 - 09:30'
            );
        Test.stopTest();

        System.assertEquals('Confirmed', rescheduled.status);
        System.assert(rescheduled.humanReadable.contains('09:00'));
    }

    @IsTest
    static void testResolveAppointmentTypeInvalid() {
        Boolean thrown = false;
        Test.startTest();
        try {
            AppointmentBookingService.resolveAppointmentType('invalid-type');
        } catch (AppointmentBookingException ex) {
            thrown = true;
            System.assert(ex.getMessage().contains('valid appointment type'));
        }
        Test.stopTest();
        System.assertEquals(true, thrown);
    }

    @IsTest
    static void testInvocableCancelAndList() {
        setCalloutMock();
        Patient__c patient = [SELECT Id FROM Patient__c WHERE Name = 'Owner Patient' LIMIT 1];
        Doctor__c doctor = [SELECT Id FROM Doctor__c WHERE Name = 'Dr Bulk Two' LIMIT 1];

        AppointmentBookingService.BookingResult booked = AppointmentBookingService.bookAppointment(
            patient.Id,
            doctor.Id,
            bookingDate(),
            '11:00',
            'OPD',
            null,
            '11:00 - 11:30'
        );

        AppointmentBookingInvocableListUpcoming.Request listReq =
            new AppointmentBookingInvocableListUpcoming.Request();

        AppointmentBookingInvocableCancel.Request cancelReq =
            new AppointmentBookingInvocableCancel.Request();
        cancelReq.appointmentId = String.valueOf(booked.appointmentId);

        Test.startTest();
        List<AppointmentBookingInvocableListUpcoming.Response> listResponses =
            AppointmentBookingInvocableListUpcoming.listUpcoming(
                new List<AppointmentBookingInvocableListUpcoming.Request>{ listReq }
            );
        List<AppointmentBookingInvocableCancel.Response> cancelResponses =
            AppointmentBookingInvocableCancel.cancel(
                new List<AppointmentBookingInvocableCancel.Request>{ cancelReq }
            );
        Test.stopTest();

        System.assertEquals(true, listResponses[0].isSuccess);
        System.assert(listResponses[0].appointmentCount > 0);
        System.assertEquals(true, cancelResponses[0].isSuccess);
    }

    @IsTest
    static void testNoDoctorsAvailableForDepartment() {
        Patient__c patient = [SELECT Id FROM Patient__c WHERE Name = 'Owner Patient' LIMIT 1];
        Department__c emptyDept = new Department__c(Name = 'Empty Department', Is_Medical_Department__c = true);
        insert emptyDept;

        Boolean thrown = false;
        Test.startTest();
        try {
            AppointmentBookingService.findAvailableSlots(
                patient.Id,
                bookingDate(),
                'OPD',
                'Empty Department',
                null,
                null
            );
        } catch (AppointmentBookingException ex) {
            thrown = true;
            System.assert(ex.getMessage().contains('No doctors are available'));
        }
        Test.stopTest();
        System.assertEquals(true, thrown);
    }

    @IsTest
    static void testMaxDailyAppointmentsExcludesDoctor() {
        setCalloutMock();
        Patient__c patient = [SELECT Id FROM Patient__c WHERE Name = 'Owner Patient' LIMIT 1];
        Doctor__c doctor = [SELECT Id, Department__c FROM Doctor__c WHERE Name = 'Dr Ava Available' LIMIT 1];
        doctor.Max_Daily_Appointments__c = 1;
        update doctor;

        insert new Appointment__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = doctor.Department__c,
            Appointment_Date__c = bookingDate(),
            Appointment_Date_Time__c = Datetime.newInstance(bookingDate(), Time.newInstance(8, 0, 0, 0)),
            Appointment_Time__c = '08:00',
            Status__c = 'Confirmed',
            Source__c = 'Agent'
        );

        Test.startTest();
        List<AppointmentBookingService.SlotInfo> slots = AppointmentBookingService.findAvailableSlots(
            patient.Id,
            bookingDate(),
            'OPD',
            'Cardiology',
            'Dr Ava Available',
            null
        );
        Test.stopTest();

        System.assertEquals(0, slots.size(), 'Doctor at daily max should not expose further slots.');
    }

    @IsTest
    static void testSymptomHintResolvesDepartment() {
        Patient__c patient = [SELECT Id FROM Patient__c WHERE Name = 'Owner Patient' LIMIT 1];

        Test.startTest();
        List<AppointmentBookingService.SlotInfo> slots = AppointmentBookingService.findAvailableSlots(
            patient.Id,
            bookingDate(),
            'Emergency Consultation',
            null,
            null,
            'chest pain'
        );
        Test.stopTest();

        System.assert(slots.size() > 0);
        System.assertEquals('Cardiology', slots[0].departmentName);
    }

    @IsTest
    static void testFormattersAndPatientResolution() {
        System.assert(
            AppointmentBookingService.formatSlotsForConversation(new List<AppointmentBookingService.SlotInfo>())
                .contains('No open appointment slots')
        );
        System.assert(
            AppointmentBookingService.formatAppointmentsForConversation(
                new List<AppointmentBookingService.AppointmentSummary>()
            ).contains('no upcoming appointments')
        );

        Boolean thrown = false;
        Test.startTest();
        try {
            AppointmentBookingService.resolvePatientIdForUser(UserInfo.getUserId());
        } catch (AppointmentBookingException ex) {
            thrown = true;
        }
        Test.stopTest();
        System.assertEquals(false, thrown);
    }

    @IsTest
    static void testInvocableReschedule() {
        setCalloutMock();
        Patient__c patient = [SELECT Id FROM Patient__c WHERE Name = 'Owner Patient' LIMIT 1];
        Doctor__c doctor = [SELECT Id FROM Doctor__c WHERE Name = 'Dr Ava Available' LIMIT 1];
        Date targetDate = bookingDate();

        AppointmentBookingService.BookingResult booked = AppointmentBookingService.bookAppointment(
            patient.Id,
            doctor.Id,
            targetDate,
            '08:00',
            'OPD',
            null,
            '08:00 - 08:30'
        );

        AppointmentBookingInvocableReschedule.Request req = new AppointmentBookingInvocableReschedule.Request();
        req.appointmentId = String.valueOf(booked.appointmentId);
        req.newAppointmentDate = String.valueOf(targetDate);
        req.newAppointmentTime = '09:00';
        req.newSlotLabel = '09:00 - 09:30';

        Test.startTest();
        List<AppointmentBookingInvocableReschedule.Response> responses =
            AppointmentBookingInvocableReschedule.reschedule(
                new List<AppointmentBookingInvocableReschedule.Request>{ req }
            );
        Test.stopTest();

        System.assertEquals(true, responses[0].isSuccess);
        System.assertNotEquals(null, responses[0].confirmationNumber);
    }

    @IsTest
    static void testFindSlotsSkipsFullyBookedTimes() {
        setCalloutMock();
        Patient__c patient = [SELECT Id FROM Patient__c WHERE Name = 'Owner Patient' LIMIT 1];
        Doctor__c doctor = [SELECT Id FROM Doctor__c WHERE Name = 'Dr Ava Available' LIMIT 1];
        Date targetDate = bookingDate();

        AppointmentBookingService.bookAppointment(
            patient.Id,
            doctor.Id,
            targetDate,
            '08:00',
            'OPD',
            null,
            '08:00 - 08:30'
        );

        Test.startTest();
        List<AppointmentBookingService.SlotInfo> slots = AppointmentBookingService.findAvailableSlots(
            patient.Id,
            targetDate,
            'OPD',
            'Cardiology',
            'Dr Ava Available',
            null
        );
        Test.stopTest();

        System.assert(slots.size() > 0);
        for (AppointmentBookingService.SlotInfo slot : slots) {
            System.assertNotEquals('08:00', slot.appointmentTime);
        }
    }

    @IsTest
    static void testAppointmentDateValidationErrors() {
        Patient__c patient = [SELECT Id FROM Patient__c WHERE Name = 'Owner Patient' LIMIT 1];
        Boolean pastDateError = false;
        Boolean futureDateError = false;

        Test.startTest();
        try {
            AppointmentBookingService.findAvailableSlots(
                patient.Id,
                Date.today().addDays(-1),
                'OPD',
                null,
                null,
                null
            );
        } catch (AppointmentBookingException ex) {
            pastDateError = ex.getMessage().contains('past');
        }
        try {
            AppointmentBookingService.findAvailableSlots(
                patient.Id,
                Date.today().addDays(366),
                'OPD',
                null,
                null,
                null
            );
        } catch (AppointmentBookingException ex) {
            futureDateError = ex.getMessage().contains('365 days');
        }
        Test.stopTest();

        System.assertEquals(true, pastDateError);
        System.assertEquals(true, futureDateError);
    }

    @IsTest
    static void testDoctorWithNullDailyMaxStillShowsSlots() {
        Patient__c patient = [SELECT Id FROM Patient__c WHERE Name = 'Owner Patient' LIMIT 1];
        Doctor__c doctor = [SELECT Id FROM Doctor__c WHERE Name = 'Dr Bulk Two' LIMIT 1];
        doctor.Max_Daily_Appointments__c = null;
        update doctor;

        Test.startTest();
        List<AppointmentBookingService.SlotInfo> slots = AppointmentBookingService.findAvailableSlots(
            patient.Id,
            bookingDate(),
            'Emergency Consultation',
            'General Medicine',
            null,
            null
        );
        Test.stopTest();

        System.assert(slots.size() > 0);
    }

    @IsTest
    static void testBookEmergencyConsultationType() {
        setCalloutMock();
        Patient__c patient = [SELECT Id FROM Patient__c WHERE Name = 'Owner Patient' LIMIT 1];
        Doctor__c doctor = [SELECT Id FROM Doctor__c WHERE Name = 'Dr Bulk Two' LIMIT 1];

        Test.startTest();
        AppointmentBookingService.BookingResult result = AppointmentBookingService.bookAppointment(
            patient.Id,
            doctor.Id,
            bookingDate(),
            '11:00',
            'urgent emergency',
            'Severe pain',
            '11:00 - 11:30'
        );
        Test.stopTest();

        System.assertEquals('Emergency Consultation', [
            SELECT Appointment_Type__c FROM Appointment__c WHERE Id = :result.appointmentId
        ].Appointment_Type__c);
    }

    @IsTest
    static void testBookHandlesInsertFailureGracefully() {
        Patient__c patient = [SELECT Id FROM Patient__c WHERE Name = 'Owner Patient' LIMIT 1];
        Doctor__c doctor = [SELECT Id FROM Doctor__c WHERE Name = 'Dr Ava Available' LIMIT 1];
        doctor.Department__c = null;
        update doctor;

        Boolean thrown = false;
        Test.startTest();
        try {
            AppointmentBookingService.bookAppointment(
                patient.Id,
                doctor.Id,
                bookingDate(),
                '09:00',
                'OPD',
                null,
                '09:00 - 09:30'
            );
        } catch (AppointmentBookingException ex) {
            thrown = true;
            System.assert(
                ex.getMessage().contains('could not save') ||
                ex.getMessage().contains('could not complete your booking')
            );
        }
        Test.stopTest();
        System.assertEquals(true, thrown);
    }

    @IsTest
    static void testListDoctorNamesForDepartment() {
        Test.startTest();
        List<String> names = AppointmentBookingService.listDoctorNamesForDepartment(
            'Cardiology',
            bookingDate()
        );
        String formatted = AppointmentBookingService.formatDoctorsForDepartment(
            'Cardiology',
            bookingDate()
        );
        Test.stopTest();
        System.assert(!names.isEmpty(), 'Expected at least one cardiologist');
        System.assert(formatted.contains('Doctors in Cardiology'));
    }

    @IsTest
    static void testInvocableListDoctors() {
        AppointmentBookingInvocableListDoctors.Request req = new AppointmentBookingInvocableListDoctors.Request();
        req.departmentName = 'Cardiology';
        req.appointmentDate = String.valueOf(bookingDate());
        Test.startTest();
        List<AppointmentBookingInvocableListDoctors.Response> responses =
            AppointmentBookingInvocableListDoctors.listDoctors(
                new List<AppointmentBookingInvocableListDoctors.Request>{ req }
            );
        Test.stopTest();
        System.assertEquals(true, responses[0].isSuccess);
        System.assert(responses[0].doctorCount > 0);
    }

    @IsTest
    static void testInvocableResolvePatientIdFromPortalUser() {
        Patient__c patient = [SELECT Id FROM Patient__c WHERE Name = 'Owner Patient' LIMIT 1];
        Test.startTest();
        Id resolved = AppointmentBookingInvocable.resolvePatientId(String.valueOf(UserInfo.getUserId()));
        Test.stopTest();
        System.assertEquals(patient.Id, resolved);
    }

    @IsTest
    static void testInvocableParseHelpers() {
        Doctor__c doctor = [SELECT Id FROM Doctor__c WHERE Name = 'Dr Ava Available' LIMIT 1];
        Test.startTest();
        System.assertEquals(Date.newInstance(2026, 7, 27), AppointmentBookingInvocable.parseDate('2026-07-27'));
        System.assertEquals(
            Date.newInstance(2026, 12, 9),
            AppointmentBookingInvocable.parseDate('9th December 2026')
        );
        System.assertEquals(
            Date.newInstance(2026, 12, 9),
            AppointmentBookingInvocable.parseDate('December 9, 2026')
        );
        System.assertEquals(
            Date.newInstance(2026, 12, 9),
            AppointmentBookingInvocable.parseDate('09-12-2026')
        );
        System.assertEquals(null, AppointmentBookingInvocable.parseOptionalId('', 'doctor'));
        System.assertEquals(null, AppointmentBookingInvocable.normalizeDoctorNameInput('any doctor'));
        System.assertEquals(doctor.Id, AppointmentBookingInvocable.parseId(String.valueOf(doctor.Id), 'doctor'));
        Test.stopTest();
    }

    @IsTest
    static void testInvocableParseErrors() {
        Boolean dateError = false;
        Boolean idError = false;
        try {
            AppointmentBookingInvocable.parseDate('bad-date');
        } catch (AppointmentBookingException ex) {
            dateError = ex.getMessage().contains('Could not understand');
        }
        try {
            AppointmentBookingInvocable.parseId('not-an-id', 'doctor');
        } catch (AppointmentBookingException ex) {
            idError = ex.getMessage().contains('Invalid doctor');
        }
        System.assertEquals(true, dateError);
        System.assertEquals(true, idError);
    }

    @IsTest
    static void testInvocableBookDepartmentMorningReturnsAppointmentId() {
        setCalloutMock();
        Date targetDate = bookingDate();

        AppointmentBookingInvocableBook.Request bookReq = new AppointmentBookingInvocableBook.Request();
        bookReq.portalUserId = UserInfo.getUserId();
        bookReq.departmentName = 'Orthopedics';
        bookReq.appointmentDate = String.valueOf(targetDate);
        bookReq.appointmentTime = 'morning';

        Test.startTest();
        List<AppointmentBookingInvocableBook.Response> responses =
            AppointmentBookingInvocableBook.book(
                new List<AppointmentBookingInvocableBook.Request>{ bookReq }
            );
        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assert(
            responses[0].isSuccess == true,
            'Booking failed: ' + String.valueOf(responses[0].errorMessage)
        );
        System.assertNotEquals(null, responses[0].appointmentId);
        Appointment__c appt = [
            SELECT Name
            FROM Appointment__c
            WHERE Id = :responses[0].appointmentId
            LIMIT 1
        ];
        System.assert(appt.Name.startsWith('APT-'));
    }

    @IsTest
    static void testInvocableBookCompoundAgentInput() {
        setCalloutMock();
        Date targetDate = Date.newInstance(2026, 8, 3);

        AppointmentBookingInvocableBook.Request bookReq = new AppointmentBookingInvocableBook.Request();
        bookReq.portalUserId = UserInfo.getUserId();
        bookReq.appointmentDate = 'cardiology, 3rd August 2026, morning';
        bookReq.appointmentTime = 'morning';

        Test.startTest();
        List<AppointmentBookingInvocableBook.Response> responses =
            AppointmentBookingInvocableBook.book(
                new List<AppointmentBookingInvocableBook.Request>{ bookReq }
            );
        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assert(
            responses[0].isSuccess == true,
            'Compound booking failed: ' + String.valueOf(responses[0].errorMessage)
        );
        Appointment__c appt = [
            SELECT Appointment_Date__c, Appointment_Time__c, Department__r.Name
            FROM Appointment__c
            WHERE Id = :responses[0].appointmentId
            LIMIT 1
        ];
        System.assertEquals(targetDate, appt.Appointment_Date__c);
        System.assertEquals('09:00', appt.Appointment_Time__c);
        System.assertEquals('Cardiology', appt.Department__r.Name);
    }

    private static Doctor__c buildDoctor(
        String name,
        Id departmentId,
        String availabilityStatus,
        Boolean active,
        String slotConfig
    ) {
        Doctor__c doctor = new Doctor__c(
            Name = name,
            Department__c = departmentId,
            Availability_Status__c = availabilityStatus,
            Active__c = active,
            Available_Slots_Config__c = slotConfig,
            Start_Time__c = Time.newInstance(8, 0, 0, 0),
            End_Time__c = Time.newInstance(17, 0, 0, 0),
            Consultation_Duration__c = 30,
            Max_Daily_Appointments__c = 20,
            Monday__c = true,
            Tuesday__c = true,
            Wednesday__c = true,
            Thursday__c = true,
            Friday__c = true,
            Saturday__c = true,
            Sunday__c = true,
            Available_Days__c = 'Monday;Tuesday;Wednesday;Thursday;Friday;Saturday;Sunday'
        );
        return doctor;
    }

    private static String dayNameFromDate(Date targetDate) {
        return Datetime.newInstance(targetDate, Time.newInstance(12, 0, 0, 0)).format('EEEE');
    }
}