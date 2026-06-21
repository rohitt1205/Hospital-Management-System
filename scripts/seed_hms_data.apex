Hospital_Branch__c branch = new Hospital_Branch__c(
    Name = 'Apollo City Hospital - Bengaluru',
    Branch_Code__c = 'BLR-MAIN',
    City__c = 'Bengaluru',
    State__c = 'Karnataka',
    Address__c = 'MG Road, Bengaluru',
    Phone__c = '08040001234',
    Active__c = true
);
insert branch;

List<Department__c> departments = new List<Department__c>{
    new Department__c(Name='Cardiology', Department_Code__c='CARD', Department_Type__c='Medical', Hospital_Branch__c=branch.Id, Active__c=true),
    new Department__c(Name='Oncology', Department_Code__c='ONCO', Department_Type__c='Medical', Hospital_Branch__c=branch.Id, Active__c=true),
    new Department__c(Name='Neurology', Department_Code__c='NEURO', Department_Type__c='Medical', Hospital_Branch__c=branch.Id, Active__c=true),
    new Department__c(Name='Orthopedics', Department_Code__c='ORTHO', Department_Type__c='Medical', Hospital_Branch__c=branch.Id, Active__c=true),
    new Department__c(Name='General Medicine', Department_Code__c='GEN', Department_Type__c='Medical', Hospital_Branch__c=branch.Id, Default_Routing_Department__c=true, Active__c=true),
    new Department__c(Name='Emergency', Department_Code__c='ER', Department_Type__c='Medical', Hospital_Branch__c=branch.Id, Active__c=true),
    new Department__c(Name='Diagnostics Lab', Department_Code__c='LAB', Department_Type__c='Lab', Hospital_Branch__c=branch.Id, Active__c=true),
    new Department__c(Name='Reception', Department_Code__c='REC', Department_Type__c='Reception', Hospital_Branch__c=branch.Id, Active__c=true),
    new Department__c(Name='Pharmacy', Department_Code__c='PHAR', Department_Type__c='Pharmacy', Hospital_Branch__c=branch.Id, Active__c=true),
    new Department__c(Name='Finance', Department_Code__c='FIN', Department_Type__c='Finance', Hospital_Branch__c=branch.Id, Active__c=true)
};
insert departments;
Map<String, Department__c> deptByName = new Map<String, Department__c>();
for (Department__c d : departments) deptByName.put(d.Name, d);

List<Staff__c> staff = new List<Staff__c>{
    new Staff__c(Name='Dr. Ananya Rao', Employee_ID__c='EMP-DOC-001', Staff_Role__c='Doctor', Department__c=deptByName.get('Cardiology').Id, Phone__c='9876500001', Email__c='ananya.rao@example.com', Joining_Date__c=Date.today().addYears(-5), Monthly_Salary__c=260000, Shift__c='Morning', Status__c='Active'),
    new Staff__c(Name='Dr. Vikram Mehta', Employee_ID__c='EMP-DOC-002', Staff_Role__c='Doctor', Department__c=deptByName.get('General Medicine').Id, Phone__c='9876500002', Email__c='vikram.mehta@example.com', Joining_Date__c=Date.today().addYears(-4), Monthly_Salary__c=220000, Shift__c='Morning', Status__c='Active'),
    new Staff__c(Name='Dr. Nisha Kapoor', Employee_ID__c='EMP-DOC-003', Staff_Role__c='Doctor', Department__c=deptByName.get('Orthopedics').Id, Phone__c='9876500003', Email__c='nisha.kapoor@example.com', Joining_Date__c=Date.today().addYears(-3), Monthly_Salary__c=230000, Shift__c='Evening', Status__c='Active'),
    new Staff__c(Name='Priya Sharma', Employee_ID__c='EMP-NUR-001', Staff_Role__c='Nurse', Department__c=deptByName.get('Cardiology').Id, Phone__c='9876500011', Email__c='priya.sharma@example.com', Joining_Date__c=Date.today().addYears(-2), Monthly_Salary__c=65000, Shift__c='Morning', Status__c='Active'),
    new Staff__c(Name='Ramesh Iyer', Employee_ID__c='EMP-LAB-001', Staff_Role__c='Lab Head', Department__c=deptByName.get('Diagnostics Lab').Id, Phone__c='9876500021', Email__c='ramesh.iyer@example.com', Joining_Date__c=Date.today().addYears(-6), Monthly_Salary__c=120000, Shift__c='Morning', Status__c='Active'),
    new Staff__c(Name='Meera Kulkarni', Employee_ID__c='EMP-BILL-001', Staff_Role__c='Billing Manager', Department__c=deptByName.get('Finance').Id, Phone__c='9876500031', Email__c='meera.kulkarni@example.com', Joining_Date__c=Date.today().addYears(-4), Monthly_Salary__c=110000, Shift__c='Morning', Status__c='Active'),
    new Staff__c(Name='Karan Malhotra', Employee_ID__c='EMP-PHAR-001', Staff_Role__c='Pharmacist', Department__c=deptByName.get('Pharmacy').Id, Phone__c='9876500041', Email__c='karan.malhotra@example.com', Joining_Date__c=Date.today().addYears(-1), Monthly_Salary__c=52000, Shift__c='Evening', Status__c='Active'),
    new Staff__c(Name='Sunita Verma', Employee_ID__c='EMP-REC-001', Staff_Role__c='Receptionist', Department__c=deptByName.get('Reception').Id, Phone__c='9876500051', Email__c='sunita.verma@example.com', Joining_Date__c=Date.today().addYears(-2), Monthly_Salary__c=42000, Shift__c='Morning', Status__c='Active')
};
insert staff;

List<Doctor__c> doctors = new List<Doctor__c>{
    new Doctor__c(Name='Dr. Ananya Rao', Staff__c=staff[0].Id, Department__c=deptByName.get('Cardiology').Id, Registration_Number__c='KMC-12345', Specialization__c='Interventional Cardiology', Consultation_Fee__c=1200, Max_Daily_Appointments__c=20, Availability_Status__c='Available', Active__c=true),
    new Doctor__c(Name='Dr. Vikram Mehta', Staff__c=staff[1].Id, Department__c=deptByName.get('General Medicine').Id, Registration_Number__c='KMC-23456', Specialization__c='Internal Medicine', Consultation_Fee__c=800, Max_Daily_Appointments__c=30, Availability_Status__c='Available', Active__c=true),
    new Doctor__c(Name='Dr. Nisha Kapoor', Staff__c=staff[2].Id, Department__c=deptByName.get('Orthopedics').Id, Registration_Number__c='KMC-34567', Specialization__c='Joint Replacement', Consultation_Fee__c=1000, Max_Daily_Appointments__c=18, Availability_Status__c='Available', Active__c=true)
};
insert doctors;

insert new List<Doctor_Availability__c>{
    new Doctor_Availability__c(Doctor__c=doctors[0].Id, Day_of_Week__c='Monday', Start_Time__c='09:00', End_Time__c='13:00', Slot_Capacity__c=12, Active__c=true),
    new Doctor_Availability__c(Doctor__c=doctors[0].Id, Day_of_Week__c='Wednesday', Start_Time__c='09:00', End_Time__c='13:00', Slot_Capacity__c=12, Active__c=true),
    new Doctor_Availability__c(Doctor__c=doctors[1].Id, Day_of_Week__c='Tuesday', Start_Time__c='10:00', End_Time__c='16:00', Slot_Capacity__c=20, Active__c=true),
    new Doctor_Availability__c(Doctor__c=doctors[2].Id, Day_of_Week__c='Friday', Start_Time__c='14:00', End_Time__c='18:00', Slot_Capacity__c=10, Active__c=true)
};

List<Ward__c> wards = new List<Ward__c>{
    new Ward__c(Name='ICU', Department__c=deptByName.get('Emergency').Id, Ward_Type__c='ICU', Capacity__c=10, Occupied_Beds__c=1, Floor__c='1', Status__c='Active'),
    new Ward__c(Name='OPD', Department__c=deptByName.get('General Medicine').Id, Ward_Type__c='OPD', Capacity__c=20, Occupied_Beds__c=0, Floor__c='G', Status__c='Active'),
    new Ward__c(Name='General', Department__c=deptByName.get('General Medicine').Id, Ward_Type__c='General', Capacity__c=40, Occupied_Beds__c=1, Floor__c='2', Status__c='Active'),
    new Ward__c(Name='Private', Department__c=deptByName.get('Cardiology').Id, Ward_Type__c='Private', Capacity__c=12, Occupied_Beds__c=0, Floor__c='3', Status__c='Active')
};
insert wards;

List<Room__c> rooms = new List<Room__c>{
    new Room__c(Name='ICU-101', Ward__c=wards[0].Id, Room_Type__c='ICU', Capacity__c=2, Status__c='Available'),
    new Room__c(Name='GEN-201', Ward__c=wards[2].Id, Room_Type__c='Shared', Capacity__c=4, Status__c='Available'),
    new Room__c(Name='PVT-301', Ward__c=wards[3].Id, Room_Type__c='Private', Capacity__c=1, Status__c='Available'),
    new Room__c(Name='OPD-01', Ward__c=wards[1].Id, Room_Type__c='OPD Cabin', Capacity__c=1, Status__c='Available')
};
insert rooms;

List<Bed__c> beds = new List<Bed__c>{
    new Bed__c(Name='ICU-101-A', Room__c=rooms[0].Id, Bed_Type__c='ICU', Daily_Rate__c=12000, Status__c='Occupied'),
    new Bed__c(Name='GEN-201-A', Room__c=rooms[1].Id, Bed_Type__c='Normal', Daily_Rate__c=2500, Status__c='Available'),
    new Bed__c(Name='GEN-201-B', Room__c=rooms[1].Id, Bed_Type__c='Non AC', Daily_Rate__c=3500, Status__c='Occupied'),
    new Bed__c(Name='PVT-301-A', Room__c=rooms[2].Id, Bed_Type__c='With Washroom', Daily_Rate__c=8000, Status__c='Available')
};
insert beds;

List<Insurance_Company__c> insurers = new List<Insurance_Company__c>{
    new Insurance_Company__c(Name='Star Health and Allied Insurance', Company_Type__c='Private', Standard_Discount__c=12, Claim_API_Enabled__c=false, Support_Phone__c='18001024477', Active__c=true),
    new Insurance_Company__c(Name='HDFC ERGO General Insurance', Company_Type__c='Private', Standard_Discount__c=10, Claim_API_Enabled__c=false, Support_Phone__c='02262346234', Active__c=true),
    new Insurance_Company__c(Name='ICICI Lombard General Insurance', Company_Type__c='Private', Standard_Discount__c=10, Claim_API_Enabled__c=false, Support_Phone__c='18002666', Active__c=true),
    new Insurance_Company__c(Name='New India Assurance', Company_Type__c='Public Sector', Standard_Discount__c=8, Claim_API_Enabled__c=false, Support_Phone__c='18002091415', Active__c=true),
    new Insurance_Company__c(Name='CGHS', Company_Type__c='Government Scheme', Standard_Discount__c=15, Claim_API_Enabled__c=false, Support_Phone__c='01120863486', Active__c=true),
    new Insurance_Company__c(Name='ECHS', Company_Type__c='Government Scheme', Standard_Discount__c=20, Claim_API_Enabled__c=false, Support_Phone__c='01125684946', Active__c=true)
};
insert insurers;

insert new List<Discount_Policy__c>{
    new Discount_Policy__c(Name='Normal Patient Standard', Patient_Category__c='Normal', Discount_Percent__c=0, Max_Discount_Amount__c=0, Active__c=true),
    new Discount_Policy__c(Name='Hospital Employee Benefit', Patient_Category__c='Hospital Employee', Discount_Percent__c=25, Max_Discount_Amount__c=50000, Active__c=true),
    new Discount_Policy__c(Name='Civil Servant Benefit', Patient_Category__c='Civil Servant', Discount_Percent__c=15, Max_Discount_Amount__c=30000, Active__c=true),
    new Discount_Policy__c(Name='Armed Professional Benefit', Patient_Category__c='Armed Professional', Discount_Percent__c=20, Max_Discount_Amount__c=40000, Active__c=true),
    new Discount_Policy__c(Name='Insurance Base Discount', Patient_Category__c='Insurance', Insurance_Company__c=insurers[0].Id, Discount_Percent__c=12, Max_Discount_Amount__c=25000, Active__c=true)
};

List<Patient__c> patients = new List<Patient__c>{
    new Patient__c(Name='Rahul Sharma', Patient_ID__c='PAT-001', Date_of_Birth__c=Date.newInstance(1988, 4, 12), Gender__c='Male', Phone__c='9988776601', Email__c='rahul.sharma@example.com', Blood_Group__c='B+', Patient_Category__c='Insurance', Aadhaar_Last_4__c='4321', Address__c='Indiranagar, Bengaluru', Status__c='Admitted'),
    new Patient__c(Name='Asha Menon', Patient_ID__c='PAT-002', Date_of_Birth__c=Date.newInstance(1995, 9, 21), Gender__c='Female', Phone__c='9988776602', Email__c='asha.menon@example.com', Blood_Group__c='O+', Patient_Category__c='Normal', Aadhaar_Last_4__c='9876', Address__c='Jayanagar, Bengaluru', Status__c='Active'),
    new Patient__c(Name='Col. Arjun Singh', Patient_ID__c='PAT-003', Date_of_Birth__c=Date.newInstance(1978, 1, 3), Gender__c='Male', Phone__c='9988776603', Email__c='arjun.singh@example.com', Blood_Group__c='A+', Patient_Category__c='Armed Professional', Aadhaar_Last_4__c='1122', Address__c='HAL, Bengaluru', Status__c='Active'),
    new Patient__c(Name='Meena Iyer', Patient_ID__c='PAT-004', Date_of_Birth__c=Date.newInstance(1982, 7, 15), Gender__c='Female', Phone__c='9988776604', Email__c='meena.iyer@example.com', Blood_Group__c='AB+', Patient_Category__c='Civil Servant', Aadhaar_Last_4__c='5566', Address__c='Malleshwaram, Bengaluru', Status__c='Active')
};
insert patients;

insert new List<Guardian__c>{
    new Guardian__c(Name='Neha Sharma', Patient__c=patients[0].Id, Relationship__c='Spouse', Phone__c='9988776611', Email__c='neha.sharma@example.com', Primary_Guardian__c=true, Address__c='Indiranagar, Bengaluru'),
    new Guardian__c(Name='Ravi Menon', Patient__c=patients[1].Id, Relationship__c='Father', Phone__c='9988776612', Email__c='ravi.menon@example.com', Primary_Guardian__c=true, Address__c='Jayanagar, Bengaluru')
};

Insurance_Policy__c policy = new Insurance_Policy__c(Name='STAR-POL-778899', Patient__c=patients[0].Id, Insurance_Company__c=insurers[0].Id, Plan_Type__c='Family Floater', Coverage_Limit__c=500000, Valid_From__c=Date.today().addMonths(-6), Valid_To__c=Date.today().addMonths(6), Verification_Status__c='Verified');
insert policy;

List<Clinical_Service__c> services = new List<Clinical_Service__c>{
    new Clinical_Service__c(Name='Cardiology Consultation', Department__c=deptByName.get('Cardiology').Id, Service_Type__c='Consultation', Standard_Rate__c=1200, Non_Billable__c=false, Active__c=true),
    new Clinical_Service__c(Name='ECG', Department__c=deptByName.get('Cardiology').Id, Service_Type__c='Lab Test', Standard_Rate__c=700, Non_Billable__c=false, Active__c=true),
    new Clinical_Service__c(Name='CBC', Department__c=deptByName.get('Diagnostics Lab').Id, Service_Type__c='Lab Test', Standard_Rate__c=450, Non_Billable__c=false, Active__c=true),
    new Clinical_Service__c(Name='Charity Consultation', Department__c=deptByName.get('General Medicine').Id, Service_Type__c='Consultation', Standard_Rate__c=0, Non_Billable__c=true, Active__c=true)
};
insert services;

List<Medicine__c> meds = new List<Medicine__c>{
    new Medicine__c(Name='Atorvastatin 10mg', Brand__c='Lipvas', Generic_Name__c='Atorvastatin', Category__c='Tablet', Unit_Price__c=18, Stock_Quantity__c=500, Active__c=true),
    new Medicine__c(Name='Pantoprazole 40mg', Brand__c='Pan-D', Generic_Name__c='Pantoprazole', Category__c='Tablet', Unit_Price__c=12, Stock_Quantity__c=800, Active__c=true),
    new Medicine__c(Name='Paracetamol 650mg', Brand__c='Dolo', Generic_Name__c='Paracetamol', Category__c='Tablet', Unit_Price__c=3, Stock_Quantity__c=2000, Active__c=true)
};
insert meds;

Appointment__c appointment = new Appointment__c(
    Patient__c=patients[0].Id,
    Doctor__c=doctors[0].Id,
    Department__c=deptByName.get('Cardiology').Id,
    Appointment_Date_Time__c=System.now().addHours(4),
    Symptoms__c='Chest pain and shortness of breath',
    Priority__c='High',
    Source__c='Reception',
    Status__c='Confirmed'
);
insert appointment;

Admission__c admission = new Admission__c(
    Patient__c=patients[0].Id,
    Appointment__c=appointment.Id,
    Doctor__c=doctors[0].Id,
    Department__c=deptByName.get('Cardiology').Id,
    Ward__c=wards[0].Id,
    Room__c=rooms[0].Id,
    Bed__c=beds[0].Id,
    Admission_Type__c='Emergency',
    Priority__c='High',
    Admission_Date_Time__c=System.now().addHours(-5),
    Expected_Discharge_Date_Time__c=System.now().addDays(2),
    Status__c='Admitted',
    Insurance_Verified__c=true,
    Estimated_Cost__c=42000
);
insert admission;

insert new Bed_Allocation__c(Admission__c=admission.Id, Bed__c=beds[0].Id, Start_Date_Time__c=System.now().addHours(-5), Daily_Rate__c=12000, Status__c='Occupied');

Medical_Record__c mr = new Medical_Record__c(
    Patient__c=patients[0].Id,
    Doctor__c=doctors[0].Id,
    Appointment__c=appointment.Id,
    Admission__c=admission.Id,
    Clinical_Notes__c='Patient admitted for cardiac observation. Initial ECG requested.',
    Diagnosis_Summary__c='Suspected unstable angina. Awaiting lab confirmation.',
    Record_Status__c='Draft'
);
insert mr;

Prescription__c rx = new Prescription__c(
    Patient__c=patients[0].Id,
    Doctor__c=doctors[0].Id,
    Medical_Record__c=mr.Id,
    Prescription_Date__c=Date.today(),
    Instructions__c='Monitor vitals every 4 hours. Review after ECG and blood work.',
    Status__c='Issued'
);
insert rx;

insert new List<Prescription_Line_Item__c>{
    new Prescription_Line_Item__c(Prescription__c=rx.Id, Medicine__c=meds[0].Id, Dosage__c='10mg', Frequency__c='Once daily after dinner', Duration_Days__c=7, Quantity__c=7),
    new Prescription_Line_Item__c(Prescription__c=rx.Id, Medicine__c=meds[1].Id, Dosage__c='40mg', Frequency__c='Once daily before breakfast', Duration_Days__c=7, Quantity__c=7)
};

Invoice__c invoice = new Invoice__c(
    Patient__c=patients[0].Id,
    Admission__c=admission.Id,
    Insurance_Policy__c=policy.Id,
    Patient_Category__c='Insurance',
    Invoice_Date__c=Date.today(),
    Gross_Amount__c=25900,
    Discount_Amount__c=3108,
    Insurance_Covered_Amount__c=15000,
    Net_Payable__c=7792,
    Payment_Status__c='Partially Paid'
);
insert invoice;

insert new List<Invoice_Line_Item__c>{
    new Invoice_Line_Item__c(Invoice__c=invoice.Id, Clinical_Service__c=services[0].Id, Quantity__c=1, Unit_Rate__c=1200, Line_Amount__c=1200, Non_Billable__c=false),
    new Invoice_Line_Item__c(Invoice__c=invoice.Id, Clinical_Service__c=services[1].Id, Quantity__c=1, Unit_Rate__c=700, Line_Amount__c=700, Non_Billable__c=false),
    new Invoice_Line_Item__c(Invoice__c=invoice.Id, Quantity__c=2, Unit_Rate__c=12000, Line_Amount__c=24000, Non_Billable__c=false)
};

insert new Payment__c(Invoice__c=invoice.Id, Amount__c=3000, Payment_Date__c=Date.today(), Payment_Mode__c='UPI', Transaction_Reference__c='UPI-HMS-1001', Status__c='Received');

Lab_Test__c lab = new Lab_Test__c(Name='Troponin I', Department__c=deptByName.get('Diagnostics Lab').Id, Standard_Rate__c=1200, Sample_Type__c='Blood', Active__c=true);
insert lab;
insert new Lab_Result__c(Patient__c=patients[0].Id, Admission__c=admission.Id, Lab_Test__c=lab.Id, Doctor__c=doctors[0].Id, Result_Summary__c='Sample collected. Result pending from analyzer.', Status__c='Sample Collected');

insert new List<Donation__c>{
    new Donation__c(Patient__c=patients[2].Id, Donor_Name__c='Col. Arjun Singh', Amount__c=10000, Donation_Date__c=Date.today(), Purpose__c='Charity Care', Status__c='Received')
};

insert new Helpdesk_Ticket__c(Patient__c=patients[1].Id, Category__c='Appointment', Priority__c='Medium', Description__c='Patient requested help rescheduling orthopedic consultation.', Status__c='New');

insert new Staff_Attendance__c(Staff__c=staff[0].Id, Attendance_Date__c=Date.today(), Check_In_Time__c='08:55', Check_Out_Time__c='17:10', Work_Hours__c=8.25, Status__c='Present');
Payroll__c payroll = new Payroll__c(Staff__c=staff[0].Id, Payroll_Month__c='June', Payroll_Year__c=2026, Gross_Pay__c=260000, Deductions__c=18000, Net_Pay__c=242000, Status__c='Approved');
insert payroll;
insert new Payslip__c(Payroll__c=payroll.Id, Generated_Date__c=Date.today(), Document_URL__c='Generated in Salesforce Files later', Status__c='Generated');

insert new Final_Report__c(Patient__c=patients[0].Id, Admission__c=admission.Id, Doctor__c=doctors[0].Id, Summary__c='Draft final report for cardiac observation admission.', Discharge_Advice__c='To be finalized after discharge approval.', Status__c='Draft');
insert new Discharge__c(Admission__c=admission.Id, Patient__c=patients[0].Id, Doctor__c=doctors[0].Id, Status__c='Pending Approval', Discharge_Notes__c='Pending billing clearance and doctor approval.');
insert new Notification_Log__c(Patient__c=patients[0].Id, Channel__c='SMS', Recipient__c='9988776601', Subject__c='Admission Confirmed', Message__c='Your admission is confirmed in ICU Ward, Room ICU-101, Bed ICU-101-A.', Status__c='Queued');
insert new Audit_Log__c(Object_Name__c='Admission__c', Record_Id__c=admission.Id, Action__c='Seed Created', Change_Detail__c='Initial demo admission created for HMS architecture validation.', Change_Date_Time__c=System.now());

System.debug('HMS seed data created. Branch=' + branch.Id + ', Patient=' + patients[0].Id + ', Admission=' + admission.Id + ', Invoice=' + invoice.Id);
