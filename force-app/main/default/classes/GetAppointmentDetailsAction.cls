public with sharing class GetAppointmentDetailsAction {
    public class Request {
        @InvocableVariable(
            label='Appointment Number'
            description='Hospital appointment number such as APT-00001. This is not a Salesforce record ID.'
            required=true
        )
        public String appointmentNumber;
    }

    public class Response {
        @InvocableVariable(label='Appointment Found')
        public Boolean appointmentFound;

        @InvocableVariable(label='Appointment Record ID')
        public Id appointmentId;

        @InvocableVariable(label='Patient Record ID')
        public Id patientId;

        @InvocableVariable(label='Patient Name')
        public String patientName;

        @InvocableVariable(label='Department Record ID')
        public Id departmentId;

        @InvocableVariable(label='Department Name')
        public String departmentName;

        @InvocableVariable(label='Doctor Record ID')
        public Id doctorId;

        @InvocableVariable(label='Doctor Name')
        public String doctorName;

        @InvocableVariable(label='Symptoms')
        public String symptoms;
    }

    @InvocableMethod(
        label='Get Appointment Details'
        description='Retrieves appointment, patient, department, doctor, and symptom details for admission.'
    )
    public static List<Response> getAppointmentDetails(List<Request> requests) {
        List<Response> responses = new List<Response>();

        for (Request requestValue : requests) {
            Response responseValue = new Response();
            responseValue.appointmentFound = false;

            if (requestValue == null || String.isBlank(requestValue.appointmentNumber)) {
                responses.add(responseValue);
                continue;
            }

            String appointmentNumber = requestValue.appointmentNumber.trim();
            List<Appointment__c> appointments = [
                SELECT Id, Name, Status__c, Symptoms__c,
                       Patient__c, Patient__r.Name,
                       Department__c, Department__r.Name,
                       Doctor__c, Doctor__r.Name
                FROM Appointment__c
                WHERE Name = :appointmentNumber
                LIMIT 1
            ];

            if (!appointments.isEmpty()) {
                Appointment__c appointment = appointments[0];
                Set<String> invalidStatuses = new Set<String>{
                    'Cancelled', 'Rejected', 'No Show'
                };

                if (!invalidStatuses.contains(appointment.Status__c)) {
                    responseValue.appointmentFound = true;
                    responseValue.appointmentId = appointment.Id;
                    responseValue.patientId = appointment.Patient__c;
                    responseValue.patientName = appointment.Patient__r == null
                        ? null
                        : appointment.Patient__r.Name;
                    responseValue.departmentId = appointment.Department__c;
                    responseValue.departmentName = appointment.Department__r == null
                        ? null
                        : appointment.Department__r.Name;
                    responseValue.doctorId = appointment.Doctor__c;
                    responseValue.doctorName = appointment.Doctor__r == null
                        ? null
                        : appointment.Doctor__r.Name;
                    responseValue.symptoms = appointment.Symptoms__c;
                }
            }

            responses.add(responseValue);
        }

        return responses;
    }
}