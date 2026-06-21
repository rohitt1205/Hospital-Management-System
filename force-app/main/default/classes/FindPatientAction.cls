public with sharing class FindPatientAction {
    public class Request {
        @InvocableVariable(
            label='Patient ID'
            description='Hospital patient identifier such as PAT-001. This is not a Salesforce record ID.'
            required=true
        )
        public String patientId;
    }

    public class Response {
        @InvocableVariable(label='Patient Found')
        public Boolean patientFound;

        @InvocableVariable(
            label='Patient Record ID'
            description='Internal Patient__c ID. Pass it to Create Admission and do not show it to the user.'
        )
        public Id patientRecordId;

        @InvocableVariable(label='Patient Name')
        public String patientName;
    }

    @InvocableMethod(
        label='Find Patient'
        description='Validates a patient using the hospital Patient ID and returns details needed for admission.'
    )
    public static List<Response> findPatient(List<Request> requests) {
        List<Response> responses = new List<Response>();

        for (Request requestValue : requests) {
            Response responseValue = new Response();
            responseValue.patientFound = false;

            if (requestValue == null || String.isBlank(requestValue.patientId)) {
                responses.add(responseValue);
                continue;
            }

            String hospitalPatientId = requestValue.patientId.trim();
            List<Patient__c> patients = [
                SELECT Id, Name
                FROM Patient__c
                WHERE Patient_ID__c = :hospitalPatientId
                LIMIT 1
            ];

            if (!patients.isEmpty()) {
                responseValue.patientFound = true;
                responseValue.patientRecordId = patients[0].Id;
                responseValue.patientName = patients[0].Name;
            }

            responses.add(responseValue);
        }

        return responses;
    }
}