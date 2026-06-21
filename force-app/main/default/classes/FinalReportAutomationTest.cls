@isTest
public class FinalReportAutomationTest {

    private class PatientAdmissionMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"success": true}');
            res.setStatusCode(200);
            return res;
        }
    }

    @isTest
    static void testFinalReportLifecycle() {
        Test.setMock(HttpCalloutMock.class, new PatientAdmissionMock());

        // Create Department
        Department__c dept = new Department__c(
            Name = 'Cardiology',
            Is_Medical_Department__c = true,
            Active__c = true
        );
        insert dept;

        // Create Doctor
        Doctor__c doctor = new Doctor__c(
            Name = 'Test Doctor',
            Specialization__c = 'Cardiology',
            Department__c = dept.Id
        );
        insert doctor;

        // Create Patient
        Patient__c patient = new Patient__c(
            Name = 'Test Patient',
            Phone__c = '9910154408',
            Email__c = 'test@example.com',
            Gender__c = 'Male',
            Status__c = 'Active'
        );
        insert patient;

        // 1. Create Appointment -> triggers Final Report creation
        Test.startTest();
        Appointment__c appt = new Appointment__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = dept.Id,
            Appointment_Date_Time__c = System.now().addHours(1),
            Appointment_Date__c = Date.today().addDays(1),
            Appointment_Time__c = '10:00',
            Symptoms__c = 'Chest Pain',
            Status__c = 'Confirmed'
        );
        insert appt;
        
        // Verify Final Report was created
        List<Final_Report__c> reports = [
            SELECT Id, Appointment__c, Patient__c, Doctor__c, Admission__c, Status__c 
            FROM Final_Report__c 
            WHERE Appointment__c = :appt.Id
        ];
        System.assertEquals(1, reports.size(), 'A Final Report should be created when Appointment is created.');
        System.assertEquals(patient.Id, reports[0].Patient__c);
        System.assertEquals(doctor.Id, reports[0].Doctor__c);
        System.assertEquals('Draft', reports[0].Status__c);

        // 2. Create Admission linked to Appointment -> triggers Final Report update
        Admission__c adm = new Admission__c(
            Appointment__c = appt.Id,
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = dept.Id,
            Admission_Type__c = 'Planned',
            Admission_Date_Time__c = System.now(),
            Status__c = 'Admitted',
            Diagnosis__c = 'Cardiac Monitoring'
        );
        insert adm;
        
        // Verify Final Report was linked to the Admission
        reports = [
            SELECT Id, Appointment__c, Patient__c, Doctor__c, Admission__c 
            FROM Final_Report__c 
            WHERE Appointment__c = :appt.Id
        ];
        System.assertEquals(adm.Id, reports[0].Admission__c, 'The existing Final Report should be updated with the Admission lookup.');

        // Create Medicine, Medical Record, and Prescriptions (one direct, one indirect with line items)
        Medicine__c med = new Medicine__c(
            Name = 'Pantoprazole 40mg',
            Unit_Price__c = 12
        );
        insert med;

        Medical_Record__c mr = new Medical_Record__c(
            Admission__c = adm.Id,
            Appointment__c = appt.Id,
            Patient__c = patient.Id,
            Doctor__c = doctor.Id
        );
        insert mr;

        Prescription__c prDirect = new Prescription__c(
            Admission__c = adm.Id,
            Medicine__c = med.Id,
            Quantity__c = 10,
            Unit_Price__c = 12,
            Instructions__c = 'Take once daily',
            Patient__c = patient.Id,
            Doctor__c = doctor.Id
        );
        insert prDirect;

        Prescription__c prIndirect = new Prescription__c(
            Medical_Record__c = mr.Id,
            Patient__c = patient.Id,
            Doctor__c = doctor.Id
        );
        insert prIndirect;
        
        Prescription_Line_Item__c pli = new Prescription_Line_Item__c(
            Prescription__c = prIndirect.Id,
            Medicine__c = med.Id,
            Quantity__c = 5,
            Dosage__c = '1 tablet',
            Frequency__c = 'Daily',
            Duration_Days__c = 5
        );
        insert pli;

        Invoice__c invoice = new Invoice__c(
            Admission__c = adm.Id,
            Patient__c = patient.Id,
            Patient_Category__c = 'Normal',
            Payment_Status__c = 'Unpaid'
        );
        insert invoice;

        insert new List<Invoice_Line_Item__c>{
            new Invoice_Line_Item__c(
                Invoice__c = invoice.Id,
                Charge_Type__c = 'Clinical Service',
                Description__c = 'ECG',
                Quantity__c = 1,
                Unit_Price__c = 700,
                Line_Total__c = 700
            ),
            new Invoice_Line_Item__c(
                Invoice__c = invoice.Id,
                Charge_Type__c = 'Insurance Deduction',
                Description__c = 'Insurance Coverage - 80%',
                Quantity__c = 1,
                Unit_Price__c = -560,
                Line_Total__c = -560
            )
        };

        // 3. Test LWC Controller
        FinalReportController.ReportWrapper data = FinalReportController.getReportDetails(reports[0].Id);
        System.assertNotEquals(null, data.report);
        System.assertNotEquals(null, data.patient);
        System.assertNotEquals(null, data.appointment);
        System.assertNotEquals(null, data.admission);
        System.assertEquals(2, data.prescriptionLineItems.size(), 'Should retrieve two prescription line items (one direct, one via medical record).');
        for (Invoice_Line_Item__c item : data.invoiceLineItems) {
            System.assertNotEquals('Insurance', item.Charge_Type__c, 'Insurance belongs only in the billing summary.');
            System.assertNotEquals('Insurance Deduction', item.Charge_Type__c, 'Insurance deductions must not appear as itemized charges.');
        }

        // 4. Test Invocable WhatsApp Send
        SendFinalReportWhatsApp.sendWhatsAppReportFlow(new List<Id>{ adm.Id });
        
        // 5. Test manual LWC WhatsApp send
        FinalReportController.sendReportWhatsApp(reports[0].Id);
        
        Test.stopTest();
    }
    
    @isTest
    static void testDirectAdmissionReport() {
        Test.setMock(HttpCalloutMock.class, new PatientAdmissionMock());

        // Create Department
        Department__c dept = new Department__c(
            Name = 'General Medicine',
            Is_Medical_Department__c = true,
            Active__c = true
        );
        insert dept;

        // Create Doctor
        Doctor__c doctor = new Doctor__c(
            Name = 'Direct Doctor',
            Specialization__c = 'General Medicine',
            Department__c = dept.Id
        );
        insert doctor;

        // Create Patient
        Patient__c patient = new Patient__c(
            Name = 'Direct Patient',
            Phone__c = '9910154408',
            Status__c = 'Active'
        );
        insert patient;

        // Create Admission directly without Appointment
        Test.startTest();
        Admission__c adm = new Admission__c(
            Patient__c = patient.Id,
            Doctor__c = doctor.Id,
            Department__c = dept.Id,
            Admission_Type__c = 'Planned',
            Admission_Date_Time__c = System.now(),
            Status__c = 'Admitted',
            Diagnosis__c = 'Fever'
        );
        insert adm;
        
        // Verify Final Report was created directly
        List<Final_Report__c> reports = [
            SELECT Id, Appointment__c, Patient__c, Doctor__c, Admission__c 
            FROM Final_Report__c 
            WHERE Admission__c = :adm.Id
        ];
        System.assertEquals(1, reports.size(), 'A Final Report should be created directly when Admission has no Appointment.');
        System.assertEquals(patient.Id, reports[0].Patient__c);
        System.assertEquals(doctor.Id, reports[0].Doctor__c);
        Test.stopTest();
    }
}