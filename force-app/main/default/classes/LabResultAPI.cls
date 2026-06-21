@RestResource(urlMapping='/labresults/*')
global with sharing class LabResultAPI {

    global class LabResultRequest {
        public String patientId;
        public String admissionNumber;
        public String labTestName;
        public String resultSummary;
        public String status;
    }

    global class LabResultResponse {
        public Boolean success;
        public String message;
        public String labResultNumber;
    }

    @HttpPost
    global static LabResultResponse receiveLabResult() {

        LabResultResponse response =
            new LabResultResponse();

        try {

            String requestBody =
                RestContext.request.requestBody.toString();

            LabResultRequest req =
                (LabResultRequest)JSON.deserialize(
                    requestBody,
                    LabResultRequest.class
                );

            List<Patient__c> patients =
[
    SELECT Id
    FROM Patient__c
    WHERE Patient_ID__c = :req.patientId
    LIMIT 1
];

if (patients.isEmpty()) {

    response.success = false;
    response.message =
        'Patient not found: ' +
        req.patientId;

    return response;
}

Patient__c patient = patients[0];

            List<Admission__c> admissions =
[
    SELECT Id, Doctor__c
    FROM Admission__c
    WHERE Name = :req.admissionNumber
    LIMIT 1
];

if (admissions.isEmpty()) {

    response.success = false;
    response.message =
        'Admission not found: ' +
        req.admissionNumber;

    return response;
}

Admission__c admission = admissions[0];

            List<Lab_Test__c> labTests =
[
    SELECT Id
    FROM Lab_Test__c
    WHERE Name = :req.labTestName
    LIMIT 1
];

if (labTests.isEmpty()) {

    response.success = false;

    response.message =
        'Lab Test not found: ' +
        req.labTestName;

    return response;
}

Lab_Test__c labTest = labTests[0];
         Set<String> validStatuses =
    new Set<String>{
        'Ordered',
        'Sample Collected',
        'Completed',
        'Cancelled'
    };

if (!validStatuses.contains(req.status)) {

    response.success = false;

    response.message =
        'Invalid status: ' +
        req.status;

    return response;
}

            Lab_Result__c result =
                new Lab_Result__c();

            result.Patient__c =
                patient.Id;

            result.Admission__c =
                admission.Id;

            result.Lab_Test__c =
                labTest.Id;

            result.Doctor__c =
                admission.Doctor__c;

            result.Result_Summary__c =
                req.resultSummary;

            result.Status__c =
                req.status;

            insert result;

            result =
                [
                    SELECT Name
                    FROM Lab_Result__c
                    WHERE Id = :result.Id
                ];

            response.success = true;
            response.labResultNumber =
                result.Name;

            response.message =
                'Lab Result Created Successfully';
        }
        catch(Exception e) {

            response.success = false;

            response.message =
                e.getMessage();
        }

        return response;
    }
}