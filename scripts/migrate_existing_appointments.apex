List<Appointment__c> apptsToUpdate = [
    SELECT Id, Has_Admission__c, Appointment_Date__c, Appointment_Date_Time__c, Appointment_Time__c, Patient__c, Doctor__c, Department__c 
    FROM Appointment__c 
    WHERE Id IN (SELECT Appointment__c FROM Admission__c WHERE Appointment__c != null)
    AND Has_Admission__c = false
];

Map<Id, Admission__c> apptToAdmissionMap = new Map<Id, Admission__c>();
for (Admission__c adm : [
    SELECT Id, Appointment__c, Patient__c, Doctor__c, Department__c, Admission_Date_Time__c 
    FROM Admission__c 
    WHERE Appointment__c IN :apptsToUpdate
]) {
    apptToAdmissionMap.put(adm.Appointment__c, adm);
}

Integer successCount = 0;
for (Appointment__c appt : apptsToUpdate) {
    Admission__c adm = apptToAdmissionMap.get(appt.Id);
    
    appt.Has_Admission__c = true;
    
    if (appt.Appointment_Date__c == null) {
        if (appt.Appointment_Date_Time__c != null) {
            appt.Appointment_Date__c = appt.Appointment_Date_Time__c.dateGmt();
        } else if (adm != null && adm.Admission_Date_Time__c != null) {
            appt.Appointment_Date__c = adm.Admission_Date_Time__c.dateGmt();
        } else {
            appt.Appointment_Date__c = Date.today();
        }
    }
    
    if (appt.Appointment_Time__c == null) {
        appt.Appointment_Time__c = '10:00';
    }

    if (appt.Patient__c == null && adm != null) {
        appt.Patient__c = adm.Patient__c;
    }

    if (appt.Doctor__c == null && adm != null) {
        appt.Doctor__c = adm.Doctor__c;
    }

    if (appt.Department__c == null && adm != null) {
        appt.Department__c = adm.Department__c;
    }
    
    if (appt.Appointment_Date__c != null && appt.Appointment_Date__c < Date.today()) {
        appt.Appointment_Date__c = Date.today();
    }
    
    try {
        update appt;
        successCount++;
    } catch (Exception ex) {
        System.debug('Failed to update Appointment ' + appt.Id + ' (' + appt.Name + '): ' + ex.getMessage());
    }
}
System.debug('*** MIGRATION COMPLETED: successfully updated ' + successCount + ' out of ' + apptsToUpdate.size() + ' appointments. ***');
