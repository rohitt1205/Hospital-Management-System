// Delete existing Patient Service records to start fresh
delete [SELECT Id FROM Patient_Service__c];

// Query Clinical Services
Map<String, Clinical_Service__c> serviceMap = new Map<String, Clinical_Service__c>();
for (Clinical_Service__c cs : [SELECT Id, Name, Standard_Rate__c FROM Clinical_Service__c]) {
    serviceMap.put(cs.Name, cs);
}

// Query Patients
List<Patient__c> patients = [SELECT Id, Name FROM Patient__c ORDER BY CreatedDate ASC LIMIT 3];
if (patients.isEmpty()) {
    System.debug('Error: No Patients found to seed Patient Services.');
    return;
}

// Query Doctors
List<Doctor__c> doctors = [SELECT Id, Name FROM Doctor__c ORDER BY CreatedDate ASC LIMIT 3];
if (doctors.isEmpty()) {
    System.debug('Error: No Doctors found to seed Patient Services.');
    return;
}

// Query Appointments and Admissions
List<Appointment__c> appointments = [SELECT Id, Name, Patient__c, Doctor__c FROM Appointment__c LIMIT 5];
List<Admission__c> admissions = [SELECT Id, Name, Patient__c, Doctor__c FROM Admission__c LIMIT 5];

List<Patient_Service__c> servicesToInsert = new List<Patient_Service__c>();

// 1. Rahul Sharma (Patient 0) - Dr. Ananya Rao (Doctor 0)
Patient__c pat1 = patients[0];
Doctor__c doc1 = doctors[0];
Appointment__c app1 = null;
for (Appointment__c app : appointments) {
    if (app.Patient__c == pat1.Id) { app1 = app; break; }
}
Admission__c adm1 = null;
for (Admission__c adm : admissions) {
    if (adm.Patient__c == pat1.Id) { adm1 = adm; break; }
}

if (serviceMap.containsKey('Cardiology Consultation')) {
    servicesToInsert.add(new Patient_Service__c(
        Patient__c = pat1.Id, Doctor__c = doc1.Id, Clinical_Service__c = serviceMap.get('Cardiology Consultation').Id,
        Appointment__c = (app1 != null) ? app1.Id : null, Admission__c = (adm1 != null) ? adm1.Id : null,
        Service_Date__c = Date.today().addDays(-2)
    ));
}
if (serviceMap.containsKey('ECG')) {
    servicesToInsert.add(new Patient_Service__c(
        Patient__c = pat1.Id, Doctor__c = doc1.Id, Clinical_Service__c = serviceMap.get('ECG').Id,
        Appointment__c = (app1 != null) ? app1.Id : null, Admission__c = (adm1 != null) ? adm1.Id : null,
        Service_Date__c = Date.today().addDays(-1)
    ));
}
if (serviceMap.containsKey('CBC')) {
    servicesToInsert.add(new Patient_Service__c(
        Patient__c = pat1.Id, Doctor__c = doc1.Id, Clinical_Service__c = serviceMap.get('CBC').Id,
        Appointment__c = (app1 != null) ? app1.Id : null, Admission__c = (adm1 != null) ? adm1.Id : null,
        Service_Date__c = Date.today()
    ));
}

// 2. Asha Menon (Patient 1) - Dr. Vikram Mehta (Doctor 1)
if (patients.size() > 1 && doctors.size() > 1) {
    Patient__c pat2 = patients[1];
    Doctor__c doc2 = doctors[1];
    Appointment__c app2 = null;
    for (Appointment__c app : appointments) {
        if (app.Patient__c == pat2.Id) { app2 = app; break; }
    }
    Admission__c adm2 = null;
    for (Admission__c adm : admissions) {
        if (adm.Patient__c == pat2.Id) { adm2 = adm; break; }
    }

    if (serviceMap.containsKey('CBC')) {
        servicesToInsert.add(new Patient_Service__c(
            Patient__c = pat2.Id, Doctor__c = doc2.Id, Clinical_Service__c = serviceMap.get('CBC').Id,
            Appointment__c = (app2 != null) ? app2.Id : null, Admission__c = (adm2 != null) ? adm2.Id : null,
            Service_Date__c = Date.today().addDays(-1)
        ));
    }
    if (serviceMap.containsKey('ECG')) {
        servicesToInsert.add(new Patient_Service__c(
            Patient__c = pat2.Id, Doctor__c = doc2.Id, Clinical_Service__c = serviceMap.get('ECG').Id,
            Appointment__c = (app2 != null) ? app2.Id : null, Admission__c = (adm2 != null) ? adm2.Id : null,
            Service_Date__c = Date.today()
        ));
    }
}

// 3. Col. Arjun Singh (Patient 2) - Dr. Nisha Kapoor (Doctor 2)
if (patients.size() > 2 && doctors.size() > 2) {
    Patient__c pat3 = patients[2];
    Doctor__c doc3 = doctors[2];
    Appointment__c app3 = null;
    for (Appointment__c app : appointments) {
        if (app.Patient__c == pat3.Id) { app3 = app; break; }
    }
    Admission__c adm3 = null;
    for (Admission__c adm : admissions) {
        if (adm.Patient__c == pat3.Id) { adm3 = adm; break; }
    }

    if (serviceMap.containsKey('Cardiology Consultation')) {
        servicesToInsert.add(new Patient_Service__c(
            Patient__c = pat3.Id, Doctor__c = doc3.Id, Clinical_Service__c = serviceMap.get('Cardiology Consultation').Id,
            Appointment__c = (app3 != null) ? app3.Id : null, Admission__c = (adm3 != null) ? adm3.Id : null,
            Service_Date__c = Date.today().addDays(-3)
        ));
    }
    if (serviceMap.containsKey('CBC')) {
        servicesToInsert.add(new Patient_Service__c(
            Patient__c = pat3.Id, Doctor__c = doc3.Id, Clinical_Service__c = serviceMap.get('CBC').Id,
            Appointment__c = (app3 != null) ? app3.Id : null, Admission__c = (adm3 != null) ? adm3.Id : null,
            Service_Date__c = Date.today().addDays(-1)
        ));
    }
}

// Insert the Patient Services
if (!servicesToInsert.isEmpty()) {
    insert servicesToInsert;
    System.debug('Successfully seeded ' + servicesToInsert.size() + ' Patient Service records.');
} else {
    System.debug('Warning: No Patient Service records were created.');
}
