public without sharing class DoctorAutomationHandler {
    public static void beforeSave(List<Doctor__c> doctors, Boolean isInsert) {
        if (doctors == null || doctors.isEmpty()) {
            return;
        }

        Map<String, String> specializationToDepartment = new Map<String, String>{
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

        Set<String> departmentNames = new Set<String>(specializationToDepartment.values());
        Map<String, Id> departmentByName = new Map<String, Id>();
        for (Department__c department : [
            SELECT Id, Name
            FROM Department__c
            WHERE Name IN :departmentNames
        ]) {
            departmentByName.put(department.Name, department.Id);
        }

        for (Doctor__c doctor : doctors) {
            String departmentName = specializationToDepartment.get(doctor.Specialization__c);
            if (departmentName != null && departmentByName.containsKey(departmentName)) {
                doctor.Department__c = departmentByName.get(departmentName);
            }
            if (isInsert == true && String.isBlank(doctor.Email__c)) {
                DoctorEmailAssignmentService.assignRandomEmail(doctor);
            }
        }
    }
}