Savepoint sp = Database.setSavepoint();
try {
    Department__c cardiology = new Department__c(
        Name = 'Cardiology',
        Department_Code__c = 'CARD-T',
        Department_Type__c = 'Medical',
        Active__c = true
    );
    insert cardiology;

    Doctor__c doctor = new Doctor__c(
        Name = 'Automation Test Doctor',
        Specialization__c = 'Cardiologist',
        Availability_Status__c = 'Available'
    );
    insert doctor;
    doctor = [SELECT Department__c FROM Doctor__c WHERE Id = :doctor.Id];
    System.assertEquals(cardiology.Id, doctor.Department__c, 'Doctor department should map from specialization.');

    Ward__c ward = new Ward__c(
        Name = 'Automation Ward',
        Ward_Type__c = 'General',
        Department__c = cardiology.Id,
        Status__c = 'Active',
        Capacity__c = 20
    );
    insert ward;

    Room__c room = new Room__c(
        Name = 'AUTO-ROOM',
        Ward__c = ward.Id,
        Room_Type__c = 'Private',
        Status__c = 'Available'
    );
    insert room;
    room = [SELECT Capacity__c, Price__c FROM Room__c WHERE Id = :room.Id];
    System.assertEquals(20, Integer.valueOf(room.Capacity__c), 'Room capacity should default to 20.');
    System.assertEquals(200, Integer.valueOf(room.Price__c), 'Private room price should default to 200.');

    Bed__c bed = new Bed__c(Name = 'AUTO-BED-01', Room__c = room.Id, Status__c = 'Available');
    insert bed;
    bed = [SELECT Daily_Rate__c FROM Bed__c WHERE Id = :bed.Id];
    System.assertEquals(200, Integer.valueOf(bed.Daily_Rate__c), 'Bed rate should inherit room price.');

    Admission__c admission = new Admission__c(
        Department__c = cardiology.Id,
        Doctor__c = doctor.Id,
        Ward__c = ward.Id,
        Room__c = room.Id,
        Bed__c = bed.Id,
        Status__c = 'Admitted',
        Admission_Type__c = 'Emergency',
        Admission_Date_Time__c = System.now()
    );
    insert admission;
    admission = [SELECT Name, Patient__c, Patient__r.Patient_ID__c, Estimated_Cost__c FROM Admission__c WHERE Id = :admission.Id];
    System.assertNotEquals(null, admission.Patient__c, 'Admission should create/link a patient.');
    System.assertEquals(admission.Name, admission.Patient__r.Patient_ID__c, 'Patient ID should map from admission number.');
    System.assertEquals(200, Integer.valueOf(admission.Estimated_Cost__c), 'Admission estimate should inherit selected bed rate.');

    Invoice__c invoice = new Invoice__c(
        Patient__c = admission.Patient__c,
        Admission__c = admission.Id,
        Patient_Category__c = 'Hospital Employee',
        Gross_Amount__c = 1000,
        Invoice_Date__c = Date.today(),
        Payment_Status__c = 'Unpaid'
    );
    insert invoice;
    invoice = [SELECT Discount_Amount__c, Insurance_Covered_Amount__c, Net_Payable__c FROM Invoice__c WHERE Id = :invoice.Id];
    System.assertEquals(300, Integer.valueOf(invoice.Discount_Amount__c), 'Hospital employee discount should be 30%.');
    System.assertEquals(0, Integer.valueOf(invoice.Insurance_Covered_Amount__c), 'Insurance coverage should require an insurance policy.');
    System.assertEquals(700, Integer.valueOf(invoice.Net_Payable__c), 'Net payable should apply the category discount.');
} finally {
    Database.rollback(sp);
}
