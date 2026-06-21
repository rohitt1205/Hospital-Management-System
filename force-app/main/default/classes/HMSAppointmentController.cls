/**
 * Apex controller for the Patient Portal appointment booking modal.
 * Exposes departments, doctors per department, and creates new Appointment__c records.
 *
 * Marked without sharing so portal users can query lookup data (Doctor, Department)
 * even when those records are owned by internal staff.
 */
public without sharing class HMSAppointmentController {

    /** Returns all active departments for the department picker. */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getDepartments() {
        List<Map<String, String>> result = new List<Map<String, String>>();
        for (Department__c d : [
            SELECT Id, Name
            FROM Department__c
            WHERE Active__c = true
            ORDER BY Name
            LIMIT 100
        ]) {
            result.add(new Map<String, String>{ 'id' => d.Id, 'name' => d.Name });
        }
        return result;
    }

    /** Returns active doctors for the selected department. */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getDoctorsByDepartment(Id departmentId) {
        List<Map<String, String>> result = new List<Map<String, String>>();
        for (Doctor__c d : [
            SELECT Id, Name, Specialization__c
            FROM Doctor__c
            WHERE Department__c = :departmentId
            AND   Active__c     = true
            ORDER BY Name
            LIMIT 100
        ]) {
            result.add(new Map<String, String>{
                'id'             => d.Id,
                'name'           => d.Name,
                'specialization' => d.Specialization__c != null ? d.Specialization__c : ''
            });
        }
        return result;
    }

    /**
     * Creates a new Appointment__c on behalf of the patient.
     * appointmentDate is a 'YYYY-MM-DD' string from the date input.
     */
    @AuraEnabled
    public static Id bookAppointment(
        Id     patientId,
        Id     departmentId,
        Id     doctorId,
        String appointmentType,
        String appointmentDate,
        String appointmentTime,
        String symptoms
    ) {
        if (patientId == null)    throw new AuraHandledException('Patient record not found.');
        if (departmentId == null) throw new AuraHandledException('Please select a department.');
        if (doctorId == null)     throw new AuraHandledException('Please select a doctor.');
        if (String.isBlank(appointmentDate)) throw new AuraHandledException('Please choose a date.');
        if (String.isBlank(appointmentTime)) throw new AuraHandledException('Please choose a time slot.');

        Date apptDate = Date.valueOf(appointmentDate);
        if (apptDate < Date.today()) {
            throw new AuraHandledException('Appointment date cannot be in the past.');
        }

        Appointment__c appt = new Appointment__c(
            Patient__c          = patientId,
            Department__c       = departmentId,
            Doctor__c           = doctorId,
            Appointment_Type__c = appointmentType,
            Appointment_Date__c = apptDate,
            Appointment_Time__c = appointmentTime,
            Symptoms__c         = symptoms,
            Status__c           = 'Requested',
            Source__c           = 'Patient Portal'
        );
        try {
            insert appt;
        } catch (DmlException de) {
            throw new AuraHandledException('Could not save appointment: ' + de.getDmlMessage(0));
        }
        return appt.Id;
    }
}