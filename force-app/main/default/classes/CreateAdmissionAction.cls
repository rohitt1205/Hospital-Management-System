public with sharing class CreateAdmissionAction {
    private static final Set<String> BLOOD_GROUPS = new Set<String>{
        'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'
    };

    private static final Set<String> ADMISSION_TYPES = new Set<String>{
        'Emergency', 'Planned', 'Walk In', 'Doctor Override'
    };

    public class Request {
        @InvocableVariable(
            label='Patient Record ID'
            description='Validated Patient__c Salesforce ID returned by Find Patient or Get Appointment Details.'
            required=true
        )
        public Id patientId;

        @InvocableVariable(
            label='Blood Group'
            description='Optional. Leave blank to use the blood group stored on the validated patient record.'
        )
        public String bloodGroup;

        @InvocableVariable(
            label='Admission Type'
            description='Emergency, Planned, Walk In, or Doctor Override.'
            required=true
        )
        public String admissionType;

        @InvocableVariable(label='Symptoms')
        public String symptoms;

        @InvocableVariable(
            label='Department'
            description='Department Salesforce ID returned by another action, or department name.'
            required=true
        )
        public String departmentId;

        @InvocableVariable(
            label='Doctor'
            description='Doctor Salesforce ID returned by another action, or doctor name. Optional for Emergency admission.'
        )
        public String doctorId;

        @InvocableVariable(
            label='Appointment Record ID'
            description='Optional Appointment__c Salesforce ID returned by Get Appointment Details.'
        )
        public Id appointmentId;
    }

    public class Response {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(
            label='Admission Record URL'
            description='Absolute clickable URL for the newly created admission record.'
        )
        public String recordUrl;

        @InvocableVariable(label='Admission Number')
        public String admissionNumber;

        @InvocableVariable(label='Admission Record ID')
        public Id admissionId;

        @InvocableVariable(
            label='Result Message'
            description='Success or error message. On success it includes the clickable admission record URL.'
        )
        public String message;
    }

    @InvocableMethod(
        label='Create Admission'
        description='Creates an admission after validating the patient, department, doctor, and appointment.'
    )
    public static List<Response> createAdmission(List<Request> requests) {
        List<Response> responses = new List<Response>();

        for (Request requestValue : requests) {
            Response responseValue = new Response();
            responseValue.success = false;

            try {
                validateRequest(requestValue);

                Patient__c patient = [
                    SELECT Id, Name, Blood_Group__c
                    FROM Patient__c
                    WHERE Id = :requestValue.patientId
                    LIMIT 1
                ];

                String resolvedBloodGroup = String.isBlank(requestValue.bloodGroup)
                    ? patient.Blood_Group__c
                    : requestValue.bloodGroup.trim();
                if (!String.isBlank(resolvedBloodGroup) &&
                    !BLOOD_GROUPS.contains(resolvedBloodGroup)) {
                    throw new AdmissionActionException(
                        'The patient record contains an invalid blood group.'
                    );
                }

                Department__c department = resolveDepartment(
                    requestValue.departmentId
                );
                if (department == null) {
                    throw new AdmissionActionException(
                        'The selected department was not found.'
                    );
                }

            Doctor__c doctor;

if (requestValue.admissionType == 'Emergency') {

    List<Doctor__c> availableDoctors = [
        SELECT Id, Name
        FROM Doctor__c
        WHERE Department__c = :department.Id
        AND Availability_Status__c = 'Available'
        ORDER BY Name
        LIMIT 1
    ];

    if (availableDoctors.isEmpty()) {
        throw new AdmissionActionException(
            'No available doctor found in department ' +
            department.Name
        );
    }

    doctor = availableDoctors[0];

} else {

    doctor = resolveDoctor(
        requestValue.doctorId,
        department.Id
    );

    if (doctor == null) {
        throw new AdmissionActionException(
            'An available doctor is required for a non-emergency admission.'
        );
    }
}
                if (requestValue.appointmentId != null) {
                    validateAppointment(
                        requestValue.appointmentId,
                        patient.Id,
                        department.Id
                    );
                }

                Admission__c admission = new Admission__c(
                    Patient__c = patient.Id,
                    Blood_Group__c = resolvedBloodGroup,
                    Admission_Type__c = requestValue.admissionType.trim(),
                    Symptoms__c = requestValue.symptoms,
                    Department__c = department.Id,
                    Doctor__c = doctor == null ? null : doctor.Id,
                    Appointment__c = requestValue.appointmentId,
                    Admission_Date_Time__c = System.now(),
                    Status__c = 'Draft',
                    Approval_Status__c = 'Pending Approval',
                    Priority__c = priorityFor(requestValue.admissionType)
                );

                insert admission;

                admission = [
                    SELECT Id, Name
                    FROM Admission__c
                    WHERE Id = :admission.Id
                ];

                String recordUrl =
                    URL.getOrgDomainUrl().toExternalForm() +
                    '/lightning/r/Admission__c/' +
                    admission.Id +
                    '/view';

                responseValue.success = true;
                responseValue.admissionId = admission.Id;
                responseValue.admissionNumber = admission.Name;
                responseValue.recordUrl = recordUrl;
                responseValue.message =
    'Admission ' + admission.Name +
    ' was created successfully for ' + patient.Name +
    '. Room and Ward will be allotted shortly. ' +
    'Admission Record: ' + recordUrl;
            } catch (Exception exceptionValue) {
                responseValue.message = exceptionValue.getMessage();
            }

            responses.add(responseValue);
        }

        return responses;
    }

    private static void validateRequest(Request requestValue) {
        if (requestValue == null) {
            throw new AdmissionActionException(
                'Admission information was not provided.'
            );
        }
        if (requestValue.patientId == null) {
            throw new AdmissionActionException(
                'A validated patient is required.'
            );
        }
        if (String.isBlank(requestValue.departmentId)) {
            throw new AdmissionActionException(
                'A department is required.'
            );
        }
        if (!String.isBlank(requestValue.bloodGroup) &&
            !BLOOD_GROUPS.contains(requestValue.bloodGroup.trim())) {
            throw new AdmissionActionException(
                'Select a valid blood group.'
            );
        }
        if (String.isBlank(requestValue.admissionType) ||
            !ADMISSION_TYPES.contains(requestValue.admissionType.trim())) {
            throw new AdmissionActionException(
                'Select Emergency, Planned, Walk In, or Doctor Override.'
            );
        }
    }

    private static Department__c resolveDepartment(String value) {
        String departmentValue = value.trim();
        try {
            Id departmentRecordId = Id.valueOf(departmentValue);
            List<Department__c> byId = [
                SELECT Id, Name
                FROM Department__c
                WHERE Id = :departmentRecordId
                LIMIT 1
            ];
            return byId.isEmpty() ? null : byId[0];
        } catch (Exception ignored) {
            List<Department__c> exactMatches = [
                SELECT Id, Name
                FROM Department__c
                WHERE Name = :departmentValue
                LIMIT 1
            ];
            if (!exactMatches.isEmpty()) {
                return exactMatches[0];
            }

            String departmentPattern = '%' + departmentValue + '%';
            List<Department__c> partialMatches = [
                SELECT Id, Name
                FROM Department__c
                WHERE Name LIKE :departmentPattern
                ORDER BY Name
                LIMIT 2
            ];
            return partialMatches.size() == 1 ? partialMatches[0] : null;
        }
    }

    private static Doctor__c resolveDoctor(
        String value,
        Id departmentId
    ) {
        if (String.isBlank(value)) {
            return null;
        }

        String doctorValue = value.trim();
        try {
            Id doctorRecordId = Id.valueOf(doctorValue);
            List<Doctor__c> byId = [
                SELECT Id, Name, Department__c, Availability_Status__c
                FROM Doctor__c
                WHERE Id = :doctorRecordId
                AND Department__c = :departmentId
                AND Availability_Status__c = 'Available'
                LIMIT 1
            ];
            return byId.isEmpty() ? null : byId[0];
        } catch (Exception ignored) {
            List<Doctor__c> exactMatches = [
                SELECT Id, Name, Department__c, Availability_Status__c
                FROM Doctor__c
                WHERE Department__c = :departmentId
                AND Availability_Status__c = 'Available'
                AND Name = :doctorValue
                LIMIT 1
            ];
            if (!exactMatches.isEmpty()) {
                return exactMatches[0];
            }

            String doctorPattern = '%' + doctorValue + '%';
            List<Doctor__c> partialMatches = [
                SELECT Id, Name, Department__c, Availability_Status__c
                FROM Doctor__c
                WHERE Department__c = :departmentId
                AND Availability_Status__c = 'Available'
                AND Name LIKE :doctorPattern
                ORDER BY Name
                LIMIT 2
            ];
            return partialMatches.size() == 1 ? partialMatches[0] : null;
        }
    }

    private static void validateAppointment(
        Id appointmentId,
        Id patientId,
        Id departmentId
    ) {
        List<Appointment__c> appointments = [
            SELECT Id, Patient__c, Department__c, Status__c
            FROM Appointment__c
            WHERE Id = :appointmentId
            LIMIT 1
        ];

        if (appointments.isEmpty()) {
            throw new AdmissionActionException(
                'The selected appointment was not found.'
            );
        }

        Appointment__c appointment = appointments[0];
        if (appointment.Patient__c != patientId) {
            throw new AdmissionActionException(
                'The appointment belongs to a different patient.'
            );
        }
        if (appointment.Department__c != departmentId) {
            throw new AdmissionActionException(
                'The appointment belongs to a different department.'
            );
        }
        if (new Set<String>{'Cancelled', 'Rejected', 'No Show'}
            .contains(appointment.Status__c)) {
            throw new AdmissionActionException(
                'This appointment cannot be used for admission.'
            );
        }
    }

    private static String priorityFor(String admissionType) {
        if (admissionType == 'Emergency') {
            return 'Critical';
        }
        if (admissionType == 'Doctor Override') {
            return 'High';
        }
        return 'Normal';
    }

    public class AdmissionActionException extends Exception {
    }
}