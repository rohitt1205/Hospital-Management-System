$ErrorActionPreference = "Stop"
$Org = "new-org"

function Format-Value($value) {
    if ($null -eq $value) { return "''" }
    if ($value -is [bool]) { return $value.ToString().ToLowerInvariant() }
    if ($value -is [int] -or $value -is [long] -or $value -is [decimal] -or $value -is [double]) { return [string]$value }
    $text = [string]$value
    $text = $text.Replace("'", "\'")
    return "'$text'"
}

function New-HmsRecord($sobject, [hashtable]$fields) {
    $pairs = @()
    foreach ($key in $fields.Keys) {
        $pairs += "$key=$(Format-Value $fields[$key])"
    }
    $values = $pairs -join " "
    $raw = & sf data record create --target-org $Org --sobject $sobject --values $values --json
    $result = $raw | ConvertFrom-Json
    if ($result.status -ne 0) {
        throw "Failed creating $sobject with $values`n$raw"
    }
    return $result.result.id
}

$branch = New-HmsRecord "Hospital_Branch__c" ([ordered]@{
    Name = "Apollo City Hospital - Bengaluru"
    Branch_Code__c = "BLR-MAIN"
    City__c = "Bengaluru"
    State__c = "Karnataka"
    Address__c = "MG Road, Bengaluru"
    Phone__c = "08040001234"
    Active__c = $true
})

$dept = @{}
foreach ($d in @(
    @("Cardiology","CARD","Medical",$false),
    @("Oncology","ONCO","Medical",$false),
    @("Neurology","NEURO","Medical",$false),
    @("Orthopedics","ORTHO","Medical",$false),
    @("General Medicine","GEN","Medical",$true),
    @("Emergency","ER","Medical",$false),
    @("Diagnostics Lab","LAB","Lab",$false),
    @("Reception","REC","Reception",$false),
    @("Pharmacy","PHAR","Pharmacy",$false),
    @("Finance","FIN","Finance",$false)
)) {
    $dept[$d[0]] = New-HmsRecord "Department__c" ([ordered]@{
        Name = $d[0]
        Department_Code__c = $d[1]
        Department_Type__c = $d[2]
        Hospital_Branch__c = $branch
        Default_Routing_Department__c = [bool]$d[3]
        Active__c = $true
    })
}

$staff = @{}
$staff["Dr. Ananya Rao"] = New-HmsRecord "Staff__c" ([ordered]@{ Name="Dr. Ananya Rao"; Employee_ID__c="EMP-DOC-001"; Staff_Role__c="Doctor"; Department__c=$dept["Cardiology"]; Phone__c="9876500001"; Email__c="ananya.rao@example.com"; Joining_Date__c="2021-06-17"; Monthly_Salary__c=260000; Shift__c="Morning"; Status__c="Active" })
$staff["Dr. Vikram Mehta"] = New-HmsRecord "Staff__c" ([ordered]@{ Name="Dr. Vikram Mehta"; Employee_ID__c="EMP-DOC-002"; Staff_Role__c="Doctor"; Department__c=$dept["General Medicine"]; Phone__c="9876500002"; Email__c="vikram.mehta@example.com"; Joining_Date__c="2022-06-17"; Monthly_Salary__c=220000; Shift__c="Morning"; Status__c="Active" })
$staff["Dr. Nisha Kapoor"] = New-HmsRecord "Staff__c" ([ordered]@{ Name="Dr. Nisha Kapoor"; Employee_ID__c="EMP-DOC-003"; Staff_Role__c="Doctor"; Department__c=$dept["Orthopedics"]; Phone__c="9876500003"; Email__c="nisha.kapoor@example.com"; Joining_Date__c="2023-06-17"; Monthly_Salary__c=230000; Shift__c="Evening"; Status__c="Active" })
$staff["Priya Sharma"] = New-HmsRecord "Staff__c" ([ordered]@{ Name="Priya Sharma"; Employee_ID__c="EMP-NUR-001"; Staff_Role__c="Nurse"; Department__c=$dept["Cardiology"]; Phone__c="9876500011"; Email__c="priya.sharma@example.com"; Joining_Date__c="2024-06-17"; Monthly_Salary__c=65000; Shift__c="Morning"; Status__c="Active" })
$staff["Meera Kulkarni"] = New-HmsRecord "Staff__c" ([ordered]@{ Name="Meera Kulkarni"; Employee_ID__c="EMP-BILL-001"; Staff_Role__c="Billing Manager"; Department__c=$dept["Finance"]; Phone__c="9876500031"; Email__c="meera.kulkarni@example.com"; Joining_Date__c="2022-06-17"; Monthly_Salary__c=110000; Shift__c="Morning"; Status__c="Active" })

$doctor = @{}
$doctor["Cardiology"] = New-HmsRecord "Doctor__c" ([ordered]@{ Name="Dr. Ananya Rao"; Staff__c=$staff["Dr. Ananya Rao"]; Department__c=$dept["Cardiology"]; Registration_Number__c="KMC-12345"; Specialization__c="Interventional Cardiology"; Consultation_Fee__c=1200; Max_Daily_Appointments__c=20; Availability_Status__c="Available"; Active__c=$true })
$doctor["General Medicine"] = New-HmsRecord "Doctor__c" ([ordered]@{ Name="Dr. Vikram Mehta"; Staff__c=$staff["Dr. Vikram Mehta"]; Department__c=$dept["General Medicine"]; Registration_Number__c="KMC-23456"; Specialization__c="Internal Medicine"; Consultation_Fee__c=800; Max_Daily_Appointments__c=30; Availability_Status__c="Available"; Active__c=$true })
$doctor["Orthopedics"] = New-HmsRecord "Doctor__c" ([ordered]@{ Name="Dr. Nisha Kapoor"; Staff__c=$staff["Dr. Nisha Kapoor"]; Department__c=$dept["Orthopedics"]; Registration_Number__c="KMC-34567"; Specialization__c="Joint Replacement"; Consultation_Fee__c=1000; Max_Daily_Appointments__c=18; Availability_Status__c="Available"; Active__c=$true })

New-HmsRecord "Doctor_Availability__c" ([ordered]@{ Doctor__c=$doctor["Cardiology"]; Day_of_Week__c="Monday"; Start_Time__c="09:00"; End_Time__c="13:00"; Slot_Capacity__c=12; Active__c=$true }) | Out-Null
New-HmsRecord "Doctor_Availability__c" ([ordered]@{ Doctor__c=$doctor["General Medicine"]; Day_of_Week__c="Tuesday"; Start_Time__c="10:00"; End_Time__c="16:00"; Slot_Capacity__c=20; Active__c=$true }) | Out-Null

$ward = @{}
$ward["ICU"] = New-HmsRecord "Ward__c" ([ordered]@{ Name="ICU Ward"; Department__c=$dept["Emergency"]; Ward_Type__c="ICU"; Capacity__c=10; Occupied_Beds__c=1; Floor__c="1"; Status__c="Active" })
$ward["General"] = New-HmsRecord "Ward__c" ([ordered]@{ Name="General Ward A"; Department__c=$dept["General Medicine"]; Ward_Type__c="General"; Capacity__c=40; Occupied_Beds__c=1; Floor__c="2"; Status__c="Active" })
$ward["Private"] = New-HmsRecord "Ward__c" ([ordered]@{ Name="Private Ward"; Department__c=$dept["Cardiology"]; Ward_Type__c="Private"; Capacity__c=12; Occupied_Beds__c=0; Floor__c="3"; Status__c="Active" })

$room = @{}
$room["ICU-101"] = New-HmsRecord "Room__c" ([ordered]@{ Name="ICU-101"; Ward__c=$ward["ICU"]; Room_Type__c="ICU"; Capacity__c=2; Status__c="Available" })
$room["GEN-201"] = New-HmsRecord "Room__c" ([ordered]@{ Name="GEN-201"; Ward__c=$ward["General"]; Room_Type__c="Shared"; Capacity__c=4; Status__c="Available" })
$room["PVT-301"] = New-HmsRecord "Room__c" ([ordered]@{ Name="PVT-301"; Ward__c=$ward["Private"]; Room_Type__c="Private"; Capacity__c=1; Status__c="Available" })

$bed = @{}
$bed["ICU-101-A"] = New-HmsRecord "Bed__c" ([ordered]@{ Name="ICU-101-A"; Room__c=$room["ICU-101"]; Bed_Type__c="ICU"; Daily_Rate__c=12000; Status__c="Occupied" })
$bed["GEN-201-A"] = New-HmsRecord "Bed__c" ([ordered]@{ Name="GEN-201-A"; Room__c=$room["GEN-201"]; Bed_Type__c="Normal"; Daily_Rate__c=2500; Status__c="Available" })
$bed["GEN-201-B"] = New-HmsRecord "Bed__c" ([ordered]@{ Name="GEN-201-B"; Room__c=$room["GEN-201"]; Bed_Type__c="Non AC"; Daily_Rate__c=3500; Status__c="Occupied" })
$bed["PVT-301-A"] = New-HmsRecord "Bed__c" ([ordered]@{ Name="PVT-301-A"; Room__c=$room["PVT-301"]; Bed_Type__c="With Washroom"; Daily_Rate__c=8000; Status__c="Available" })

$insurer = @{}
$insurer["Star"] = New-HmsRecord "Insurance_Company__c" ([ordered]@{ Name="Star Health and Allied Insurance"; Company_Type__c="Private"; Standard_Discount__c=12; Claim_API_Enabled__c=$false; Support_Phone__c="18001024477"; Active__c=$true })
$insurer["HDFC"] = New-HmsRecord "Insurance_Company__c" ([ordered]@{ Name="HDFC ERGO General Insurance"; Company_Type__c="Private"; Standard_Discount__c=10; Claim_API_Enabled__c=$false; Support_Phone__c="02262346234"; Active__c=$true })
$insurer["CGHS"] = New-HmsRecord "Insurance_Company__c" ([ordered]@{ Name="CGHS"; Company_Type__c="Government Scheme"; Standard_Discount__c=15; Claim_API_Enabled__c=$false; Support_Phone__c="01120863486"; Active__c=$true })
$insurer["ECHS"] = New-HmsRecord "Insurance_Company__c" ([ordered]@{ Name="ECHS"; Company_Type__c="Government Scheme"; Standard_Discount__c=20; Claim_API_Enabled__c=$false; Support_Phone__c="01125684946"; Active__c=$true })

New-HmsRecord "Discount_Policy__c" ([ordered]@{ Name="Hospital Employee Benefit"; Patient_Category__c="Hospital Employee"; Discount_Percent__c=25; Max_Discount_Amount__c=50000; Active__c=$true }) | Out-Null
New-HmsRecord "Discount_Policy__c" ([ordered]@{ Name="Civil Servant Benefit"; Patient_Category__c="Civil Servant"; Discount_Percent__c=15; Max_Discount_Amount__c=30000; Active__c=$true }) | Out-Null
New-HmsRecord "Discount_Policy__c" ([ordered]@{ Name="Armed Professional Benefit"; Patient_Category__c="Armed Professional"; Discount_Percent__c=20; Max_Discount_Amount__c=40000; Active__c=$true }) | Out-Null
New-HmsRecord "Discount_Policy__c" ([ordered]@{ Name="Insurance Base Discount"; Patient_Category__c="Insurance"; Insurance_Company__c=$insurer["Star"]; Discount_Percent__c=12; Max_Discount_Amount__c=25000; Active__c=$true }) | Out-Null

$patient = @{}
$patient["Rahul"] = New-HmsRecord "Patient__c" ([ordered]@{ Name="Rahul Sharma"; Patient_ID__c="PAT-001"; Date_of_Birth__c="1988-04-12"; Gender__c="Male"; Phone__c="9988776601"; Email__c="rahul.sharma@example.com"; Blood_Group__c="B+"; Patient_Category__c="Insurance"; Aadhaar_Last_4__c="4321"; Address__c="Indiranagar, Bengaluru"; Status__c="Admitted" })
$patient["Asha"] = New-HmsRecord "Patient__c" ([ordered]@{ Name="Asha Menon"; Patient_ID__c="PAT-002"; Date_of_Birth__c="1995-09-21"; Gender__c="Female"; Phone__c="9988776602"; Email__c="asha.menon@example.com"; Blood_Group__c="O+"; Patient_Category__c="Normal"; Aadhaar_Last_4__c="9876"; Address__c="Jayanagar, Bengaluru"; Status__c="Active" })
$patient["Arjun"] = New-HmsRecord "Patient__c" ([ordered]@{ Name="Col. Arjun Singh"; Patient_ID__c="PAT-003"; Date_of_Birth__c="1978-01-03"; Gender__c="Male"; Phone__c="9988776603"; Email__c="arjun.singh@example.com"; Blood_Group__c="A+"; Patient_Category__c="Armed Professional"; Aadhaar_Last_4__c="1122"; Address__c="HAL, Bengaluru"; Status__c="Active" })
$patient["Meena"] = New-HmsRecord "Patient__c" ([ordered]@{ Name="Meena Iyer"; Patient_ID__c="PAT-004"; Date_of_Birth__c="1982-07-15"; Gender__c="Female"; Phone__c="9988776604"; Email__c="meena.iyer@example.com"; Blood_Group__c="AB+"; Patient_Category__c="Civil Servant"; Aadhaar_Last_4__c="5566"; Address__c="Malleshwaram, Bengaluru"; Status__c="Active" })

New-HmsRecord "Guardian__c" ([ordered]@{ Name="Neha Sharma"; Patient__c=$patient["Rahul"]; Relationship__c="Spouse"; Phone__c="9988776611"; Email__c="neha.sharma@example.com"; Primary_Guardian__c=$true; Address__c="Indiranagar, Bengaluru" }) | Out-Null
New-HmsRecord "Guardian__c" ([ordered]@{ Name="Ravi Menon"; Patient__c=$patient["Asha"]; Relationship__c="Father"; Phone__c="9988776612"; Email__c="ravi.menon@example.com"; Primary_Guardian__c=$true; Address__c="Jayanagar, Bengaluru" }) | Out-Null

$policy = New-HmsRecord "Insurance_Policy__c" ([ordered]@{ Name="STAR-POL-778899"; Patient__c=$patient["Rahul"]; Insurance_Company__c=$insurer["Star"]; Plan_Type__c="Family Floater"; Coverage_Limit__c=500000; Valid_From__c="2025-12-17"; Valid_To__c="2026-12-17"; Verification_Status__c="Verified" })

$service = @{}
$service["Consult"] = New-HmsRecord "Clinical_Service__c" ([ordered]@{ Name="Cardiology Consultation"; Department__c=$dept["Cardiology"]; Service_Type__c="Consultation"; Standard_Rate__c=1200; Non_Billable__c=$false; Active__c=$true })
$service["ECG"] = New-HmsRecord "Clinical_Service__c" ([ordered]@{ Name="ECG"; Department__c=$dept["Cardiology"]; Service_Type__c="Lab Test"; Standard_Rate__c=700; Non_Billable__c=$false; Active__c=$true })
$service["CBC"] = New-HmsRecord "Clinical_Service__c" ([ordered]@{ Name="CBC"; Department__c=$dept["Diagnostics Lab"]; Service_Type__c="Lab Test"; Standard_Rate__c=450; Non_Billable__c=$false; Active__c=$true })

$medicine = @{}
$medicine["Atorvastatin"] = New-HmsRecord "Medicine__c" ([ordered]@{ Name="Atorvastatin 10mg"; Brand__c="Lipvas"; Generic_Name__c="Atorvastatin"; Category__c="Tablet"; Unit_Price__c=18; Stock_Quantity__c=500; Active__c=$true })
$medicine["Pantoprazole"] = New-HmsRecord "Medicine__c" ([ordered]@{ Name="Pantoprazole 40mg"; Brand__c="Pan-D"; Generic_Name__c="Pantoprazole"; Category__c="Tablet"; Unit_Price__c=12; Stock_Quantity__c=800; Active__c=$true })

$appointment = New-HmsRecord "Appointment__c" ([ordered]@{ Patient__c=$patient["Rahul"]; Doctor__c=$doctor["Cardiology"]; Department__c=$dept["Cardiology"]; Appointment_Date_Time__c="2026-06-18T10:00:00+05:30"; Symptoms__c="Chest pain and shortness of breath"; Priority__c="High"; Source__c="Reception"; Status__c="Confirmed" })
$admission = New-HmsRecord "Admission__c" ([ordered]@{ Patient__c=$patient["Rahul"]; Appointment__c=$appointment; Doctor__c=$doctor["Cardiology"]; Department__c=$dept["Cardiology"]; Ward__c=$ward["ICU"]; Room__c=$room["ICU-101"]; Bed__c=$bed["ICU-101-A"]; Admission_Type__c="Emergency"; Priority__c="High"; Admission_Date_Time__c="2026-06-17T09:00:00+05:30"; Expected_Discharge_Date_Time__c="2026-06-19T12:00:00+05:30"; Status__c="Admitted"; Insurance_Verified__c=$true; Estimated_Cost__c=42000 })
New-HmsRecord "Bed_Allocation__c" ([ordered]@{ Admission__c=$admission; Bed__c=$bed["ICU-101-A"]; Start_Date_Time__c="2026-06-17T09:00:00+05:30"; Daily_Rate__c=12000; Status__c="Occupied" }) | Out-Null

$mr = New-HmsRecord "Medical_Record__c" ([ordered]@{ Patient__c=$patient["Rahul"]; Doctor__c=$doctor["Cardiology"]; Appointment__c=$appointment; Admission__c=$admission; Clinical_Notes__c="Patient admitted for cardiac observation. Initial ECG requested."; Diagnosis_Summary__c="Suspected unstable angina. Awaiting lab confirmation."; Record_Status__c="Draft" })
$rx = New-HmsRecord "Prescription__c" ([ordered]@{ Patient__c=$patient["Rahul"]; Doctor__c=$doctor["Cardiology"]; Medical_Record__c=$mr; Prescription_Date__c="2026-06-17"; Instructions__c="Monitor vitals every 4 hours. Review after ECG and blood work."; Status__c="Issued" })
New-HmsRecord "Prescription_Line_Item__c" ([ordered]@{ Prescription__c=$rx; Medicine__c=$medicine["Atorvastatin"]; Dosage__c="10mg"; Frequency__c="Once daily after dinner"; Duration_Days__c=7; Quantity__c=7 }) | Out-Null
New-HmsRecord "Prescription_Line_Item__c" ([ordered]@{ Prescription__c=$rx; Medicine__c=$medicine["Pantoprazole"]; Dosage__c="40mg"; Frequency__c="Once daily before breakfast"; Duration_Days__c=7; Quantity__c=7 }) | Out-Null

$invoice = New-HmsRecord "Invoice__c" ([ordered]@{ Patient__c=$patient["Rahul"]; Admission__c=$admission; Insurance_Policy__c=$policy; Patient_Category__c="Insurance"; Invoice_Date__c="2026-06-17"; Gross_Amount__c=25900; Discount_Amount__c=3108; Insurance_Covered_Amount__c=15000; Net_Payable__c=7792; Payment_Status__c="Partially Paid" })
New-HmsRecord "Invoice_Line_Item__c" ([ordered]@{ Invoice__c=$invoice; Clinical_Service__c=$service["Consult"]; Quantity__c=1; Unit_Rate__c=1200; Line_Amount__c=1200; Non_Billable__c=$false }) | Out-Null
New-HmsRecord "Invoice_Line_Item__c" ([ordered]@{ Invoice__c=$invoice; Clinical_Service__c=$service["ECG"]; Quantity__c=1; Unit_Rate__c=700; Line_Amount__c=700; Non_Billable__c=$false }) | Out-Null
New-HmsRecord "Invoice_Line_Item__c" ([ordered]@{ Invoice__c=$invoice; Quantity__c=2; Unit_Rate__c=12000; Line_Amount__c=24000; Non_Billable__c=$false }) | Out-Null
New-HmsRecord "Payment__c" ([ordered]@{ Invoice__c=$invoice; Amount__c=3000; Payment_Date__c="2026-06-17"; Payment_Mode__c="UPI"; Transaction_Reference__c="UPI-HMS-1001"; Status__c="Received" }) | Out-Null

$lab = New-HmsRecord "Lab_Test__c" ([ordered]@{ Name="Troponin I"; Department__c=$dept["Diagnostics Lab"]; Standard_Rate__c=1200; Sample_Type__c="Blood"; Active__c=$true })
New-HmsRecord "Lab_Result__c" ([ordered]@{ Patient__c=$patient["Rahul"]; Admission__c=$admission; Lab_Test__c=$lab; Doctor__c=$doctor["Cardiology"]; Result_Summary__c="Sample collected. Result pending from analyzer."; Status__c="Sample Collected" }) | Out-Null
New-HmsRecord "Donation__c" ([ordered]@{ Patient__c=$patient["Arjun"]; Donor_Name__c="Col. Arjun Singh"; Amount__c=10000; Donation_Date__c="2026-06-17"; Purpose__c="Charity Care"; Status__c="Received" }) | Out-Null
New-HmsRecord "Helpdesk_Ticket__c" ([ordered]@{ Patient__c=$patient["Asha"]; Category__c="Appointment"; Priority__c="Medium"; Description__c="Patient requested help rescheduling orthopedic consultation."; Status__c="New" }) | Out-Null
New-HmsRecord "Staff_Attendance__c" ([ordered]@{ Staff__c=$staff["Dr. Ananya Rao"]; Attendance_Date__c="2026-06-17"; Check_In_Time__c="08:55"; Check_Out_Time__c="17:10"; Work_Hours__c=8.25; Status__c="Present" }) | Out-Null
$payroll = New-HmsRecord "Payroll__c" ([ordered]@{ Staff__c=$staff["Dr. Ananya Rao"]; Payroll_Month__c="June"; Payroll_Year__c=2026; Gross_Pay__c=260000; Deductions__c=18000; Net_Pay__c=242000; Status__c="Approved" })
New-HmsRecord "Payslip__c" ([ordered]@{ Payroll__c=$payroll; Generated_Date__c="2026-06-17"; Document_URL__c="Generated in Salesforce Files later"; Status__c="Generated" }) | Out-Null
New-HmsRecord "Final_Report__c" ([ordered]@{ Patient__c=$patient["Rahul"]; Admission__c=$admission; Doctor__c=$doctor["Cardiology"]; Summary__c="Draft final report for cardiac observation admission."; Discharge_Advice__c="To be finalized after discharge approval."; Status__c="Draft" }) | Out-Null
New-HmsRecord "Discharge__c" ([ordered]@{ Admission__c=$admission; Patient__c=$patient["Rahul"]; Doctor__c=$doctor["Cardiology"]; Status__c="Pending Approval"; Discharge_Notes__c="Pending billing clearance and doctor approval." }) | Out-Null
New-HmsRecord "Notification_Log__c" ([ordered]@{ Patient__c=$patient["Rahul"]; Channel__c="SMS"; Recipient__c="9988776601"; Subject__c="Admission Confirmed"; Message__c="Your admission is confirmed in ICU Ward, Room ICU-101, Bed ICU-101-A."; Status__c="Queued" }) | Out-Null
New-HmsRecord "Audit_Log__c" ([ordered]@{ Object_Name__c="Admission__c"; Record_Id__c=$admission; Action__c="Seed Created"; Change_Detail__c="Initial demo admission created for HMS architecture validation."; Change_Date_Time__c="2026-06-17T12:00:00+05:30" }) | Out-Null

Write-Output "Seed complete. Branch=$branch Admission=$admission Invoice=$invoice"
