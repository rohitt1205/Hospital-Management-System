public with sharing class GetAvailableDoctorAction {
    public class Request {
        @InvocableVariable(
            label='Department'
            description='Department Salesforce ID or department name such as Cardiology.'
            required=true
        )
        public String departmentId;
    }

    public class Response {
        @InvocableVariable(label='Doctor Found')
        public Boolean doctorFound;

        @InvocableVariable(label='Doctor Record ID')
        public Id doctorId;

        @InvocableVariable(label='Doctor Name')
        public String doctorName;
    }

    @InvocableMethod(
        label='Get Available Doctor'
        description='Finds an available doctor using a department Salesforce ID or department name.'
    )
    public static List<Response> getDoctor(List<Request> requests) {
        List<Response> responses = new List<Response>();

        for (Request requestValue : requests) {
            Response responseValue = new Response();
            responseValue.doctorFound = false;

            Department__c department = resolveDepartment(
                requestValue == null ? null : requestValue.departmentId
            );

            if (department != null) {
                List<Doctor__c> doctors = [
                    SELECT Id, Name
                    FROM Doctor__c
                    WHERE Department__c = :department.Id
                    AND Availability_Status__c = 'Available'
                    ORDER BY Name
                    LIMIT 1
                ];

                if (!doctors.isEmpty()) {
                    responseValue.doctorFound = true;
                    responseValue.doctorId = doctors[0].Id;
                    responseValue.doctorName = doctors[0].Name;
                }
            }

            responses.add(responseValue);
        }

        return responses;
    }

    private static Department__c resolveDepartment(String value) {
        if (String.isBlank(value)) {
            return null;
        }

        String departmentValue = value.trim();

        try {
            Id departmentRecordId = Id.valueOf(departmentValue);
            List<Department__c> matches = [
                SELECT Id, Name
                FROM Department__c
                WHERE Id = :departmentRecordId
                LIMIT 1
            ];
            return matches.isEmpty() ? null : matches[0];
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
}