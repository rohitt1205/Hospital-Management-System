public with sharing class SearchAdmissionAction {
    public class Request {
        @InvocableVariable(
            label='Admission Number or Patient Name'
            description='Admission number such as ADM-00059, or all or part of the patient name.'
            required=true
        )
        public String searchText;
    }

    public class Response {
        @InvocableVariable(label='Admission Found')
        public Boolean admissionFound;

        @InvocableVariable(label='Result Count')
        public Integer resultCount;

        @InvocableVariable(
            label='Admission Details'
            description='Patient-friendly admission details with clickable record URLs.'
        )
        public String admissionDetails;

        @InvocableVariable(
            label='Admission Record URL'
            description='Clickable record URL when exactly one admission is found.'
        )
        public String recordUrl;

        @InvocableVariable(label='Message')
        public String message;
    }

    @InvocableMethod(
        label='Search Admission'
        description='Searches admissions by admission number or patient name and returns admission details with clickable record links.'
    )
    public static List<Response> searchAdmissions(List<Request> requests) {
        List<Response> responses = new List<Response>();

        for (Request requestValue : requests) {
            Response responseValue = new Response();
            responseValue.admissionFound = false;
            responseValue.resultCount = 0;

            try {
                if (requestValue == null || String.isBlank(requestValue.searchText)) {
                    responseValue.message =
                        'Please provide an admission number or patient name.';
                    responses.add(responseValue);
                    continue;
                }

                String searchText = requestValue.searchText.trim();
                List<Admission__c> admissions;

                if (searchText.toUpperCase().startsWith('ADM-')) {
                    admissions = [
                        SELECT Id, Name, Admission_Date_Time__c,
                               Admission_Type__c, Status__c, Symptoms__c,
                               Patient__c, Patient__r.Name,
                               Department__c, Department__r.Name,
                               Doctor__c, Doctor__r.Name
                        FROM Admission__c
                        WHERE Name = :searchText
                        ORDER BY CreatedDate DESC
                        LIMIT 20
                    ];
                } else {
                    String patientPattern = '%' + searchText + '%';
                    admissions = [
                        SELECT Id, Name, Admission_Date_Time__c,
                               Admission_Type__c, Status__c, Symptoms__c,
                               Patient__c, Patient__r.Name,
                               Department__c, Department__r.Name,
                               Doctor__c, Doctor__r.Name
                        FROM Admission__c
                        WHERE Patient__r.Name LIKE :patientPattern
                        OR Patient_Name__c LIKE :patientPattern
                        ORDER BY CreatedDate DESC
                        LIMIT 20
                    ];
                }

                responseValue.resultCount = admissions.size();
                responseValue.admissionFound = !admissions.isEmpty();

                if (admissions.isEmpty()) {
                    responseValue.message =
                        'No admission was found for "' + searchText + '".';
                } else {
                    String baseUrl = URL.getOrgDomainUrl().toExternalForm();
                    List<String> detailLines = new List<String>();
                    Integer position = 1;

                    for (Admission__c admission : admissions) {
                        String url =
                            baseUrl +
                            '/lightning/r/Admission__c/' +
                            admission.Id +
                            '/view';
                        String patientName = admission.Patient__r == null
                            ? null
                            : admission.Patient__r.Name;
                        String departmentName = admission.Department__r == null
                            ? null
                            : admission.Department__r.Name;
                        String doctorName = admission.Doctor__r == null
                            ? null
                            : admission.Doctor__r.Name;

                        detailLines.add(
                            String.valueOf(position) + '. ' +
                            'Admission: ' + safeValue(admission.Name) +
                            ' | Patient: ' + safeValue(patientName) +
                            ' | Type: ' + safeValue(admission.Admission_Type__c) +
                            ' | Status: ' + safeValue(admission.Status__c) +
                            ' | Department: ' + safeValue(departmentName) +
                            ' | Doctor: ' + safeValue(doctorName) +
                            ' | Admission Date: ' +
                            safeValue(String.valueOf(admission.Admission_Date_Time__c)) +
                            ' | Open record: ' + url
                        );
                        position++;
                    }

                    responseValue.admissionDetails =
                        String.join(detailLines, '\n');
                    responseValue.message = admissions.size() == 1
                        ? 'One admission was found.'
                        : String.valueOf(admissions.size()) +
                            ' admissions were found. Ask the user to select one.';

                    if (admissions.size() == 1) {
                        responseValue.recordUrl =
                            baseUrl +
                            '/lightning/r/Admission__c/' +
                            admissions[0].Id +
                            '/view';
                    }
                }
            } catch (Exception exceptionValue) {
                responseValue.message =
                    'Unable to search admissions: ' +
                    exceptionValue.getMessage();
            }

            responses.add(responseValue);
        }

        return responses;
    }

    private static String safeValue(String value) {
        return String.isBlank(value) ? '-' : value;
    }
}