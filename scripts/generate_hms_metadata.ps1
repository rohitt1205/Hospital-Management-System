$ErrorActionPreference = "Stop"

$base = Join-Path (Get-Location) "force-app/main/default"
$objectsDir = Join-Path $base "objects"
$tabsDir = Join-Path $base "tabs"
$appsDir = Join-Path $base "applications"
$rolesDir = Join-Path $base "roles"
$permsetsDir = Join-Path $base "permissionsets"
$layoutsDir = Join-Path $base "layouts"
if (Test-Path $base) {
    Remove-Item -LiteralPath $base -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $objectsDir,$tabsDir,$appsDir,$rolesDir,$permsetsDir,$layoutsDir | Out-Null

function XmlEscape([string]$Value) {
    if ($null -eq $Value) { return "" }
    return [System.Security.SecurityElement]::Escape($Value)
}

function FieldXml($f) {
    $label = XmlEscape $f.label
    $name = XmlEscape $f.name
    $type = $f.type
    $xml = @"
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>$name</fullName>
    <label>$label</label>
"@
    switch ($type) {
        "Text" { $xml += "    <length>$($f.length)</length>`n    <type>Text</type>`n" }
        "LongTextArea" { $xml += "    <length>$($f.length)</length>`n    <type>LongTextArea</type>`n    <visibleLines>$($f.visibleLines)</visibleLines>`n" }
        "Number" { $xml += "    <precision>$($f.precision)</precision>`n    <scale>$($f.scale)</scale>`n    <type>Number</type>`n" }
        "Currency" { $xml += "    <precision>$($f.precision)</precision>`n    <scale>$($f.scale)</scale>`n    <type>Currency</type>`n" }
        "Percent" { $xml += "    <precision>$($f.precision)</precision>`n    <scale>$($f.scale)</scale>`n    <type>Percent</type>`n" }
        "Date" { $xml += "    <type>Date</type>`n" }
        "DateTime" { $xml += "    <type>DateTime</type>`n" }
        "Checkbox" { $xml += "    <defaultValue>false</defaultValue>`n    <type>Checkbox</type>`n" }
        "Phone" { $xml += "    <type>Phone</type>`n" }
        "Email" { $xml += "    <type>Email</type>`n" }
        "Url" { $xml += "    <type>Url</type>`n" }
        "Picklist" {
            $xml += "    <type>Picklist</type>`n    <valueSet>`n        <restricted>true</restricted>`n        <valueSetDefinition>`n            <sorted>false</sorted>`n"
            foreach ($v in $f.values) {
                $vv = XmlEscape $v
                $default = if ($v -eq $f.default) { "true" } else { "false" }
                $xml += "            <value><fullName>$vv</fullName><default>$default</default><label>$vv</label></value>`n"
            }
            $xml += "        </valueSetDefinition>`n    </valueSet>`n"
        }
        "Lookup" {
            $relLabel = XmlEscape $f.relationshipLabel
            $relName = XmlEscape $f.relationshipName
            $ref = XmlEscape $f.referenceTo
            $xml += "    <deleteConstraint>SetNull</deleteConstraint>`n    <referenceTo>$ref</referenceTo>`n    <relationshipLabel>$relLabel</relationshipLabel>`n    <relationshipName>$relName</relationshipName>`n    <type>Lookup</type>`n"
        }
        "MasterDetail" {
            $relLabel = XmlEscape $f.relationshipLabel
            $relName = XmlEscape $f.relationshipName
            $ref = XmlEscape $f.referenceTo
            $xml += "    <referenceTo>$ref</referenceTo>`n    <relationshipLabel>$relLabel</relationshipLabel>`n    <relationshipName>$relName</relationshipName>`n    <reparentableMasterDetail>false</reparentableMasterDetail>`n    <type>MasterDetail</type>`n    <writeRequiresMasterRead>false</writeRequiresMasterRead>`n"
        }
        default { throw "Unsupported field type $type for $name" }
    }
    if ($f.required) { $xml += "    <required>true</required>`n" }
    $xml += "</CustomField>`n"
    return $xml
}

function TextField($name,$label,$length=80,$required=$false) { @{ name=$name; label=$label; type="Text"; length=$length; required=$required } }
function LongField($name,$label,$length=32768,$visibleLines=4) { @{ name=$name; label=$label; type="LongTextArea"; length=$length; visibleLines=$visibleLines } }
function NumberField($name,$label,$precision=18,$scale=0) { @{ name=$name; label=$label; type="Number"; precision=$precision; scale=$scale } }
function CurrencyField($name,$label,$precision=18,$scale=2) { @{ name=$name; label=$label; type="Currency"; precision=$precision; scale=$scale } }
function PercentField($name,$label,$precision=5,$scale=2) { @{ name=$name; label=$label; type="Percent"; precision=$precision; scale=$scale } }
function DateField($name,$label) { @{ name=$name; label=$label; type="Date" } }
function DateTimeField($name,$label) { @{ name=$name; label=$label; type="DateTime" } }
function CheckboxField($name,$label) { @{ name=$name; label=$label; type="Checkbox" } }
function PhoneField($name,$label) { @{ name=$name; label=$label; type="Phone" } }
function PicklistField($name,$label,$values,$default=$null) { @{ name=$name; label=$label; type="Picklist"; values=$values; default=$default } }
function LookupField($name,$label,$referenceTo,$relationshipLabel,$relationshipName) { @{ name=$name; label=$label; type="Lookup"; referenceTo=$referenceTo; relationshipLabel=$relationshipLabel; relationshipName=$relationshipName } }
function MasterField($name,$label,$referenceTo,$relationshipLabel,$relationshipName) { @{ name=$name; label=$label; type="MasterDetail"; referenceTo=$referenceTo; relationshipLabel=$relationshipLabel; relationshipName=$relationshipName } }

$objects = @(
    @{ api="Hospital_Branch__c"; label="Hospital Branch"; plural="Hospital Branches"; sharing="ReadWrite"; nameType="Text"; nameLabel="Branch Name"; fields=@(
        (TextField "Branch_Code__c" "Branch Code" 30),
        (TextField "City__c" "City" 80),
        (TextField "State__c" "State" 80),
        (TextField "Address__c" "Address" 255),
        (PhoneField "Phone__c" "Phone"),
        (CheckboxField "Active__c" "Active")
    )},
    @{ api="Department__c"; label="Department"; plural="Departments"; sharing="ReadWrite"; nameType="Text"; nameLabel="Department Name"; fields=@(
        (LookupField "Hospital_Branch__c" "Hospital Branch" "Hospital_Branch__c" "Departments" "Departments"),
        (PicklistField "Department_Type__c" "Department Type" @("Medical","Lab","Reception","Pharmacy","Finance","Administration")),
        (TextField "Department_Code__c" "Department Code" 30),
        (CheckboxField "Default_Routing_Department__c" "Default Routing Department"),
        (CheckboxField "Active__c" "Active")
    )},
    @{ api="Staff__c"; label="Staff"; plural="Staff"; sharing="Private"; nameType="Text"; nameLabel="Staff Name"; fields=@(
        (LookupField "Department__c" "Department" "Department__c" "Staff Members" "Staff_Members"),
        (LookupField "Salesforce_User__c" "Salesforce User" "User" "Staff Profiles" "Staff_Profiles"),
        (TextField "Employee_ID__c" "Employee ID" 30),
        (PicklistField "Staff_Role__c" "Staff Role" @("Hospital Admin","Department Head","Doctor","Nurse","Resident","Lab Head","Lab Assistant","Reception Head","Receptionist","Pharmacy Manager","Pharmacist","Finance Head","Payroll Manager","Billing Manager","Billing Executive")),
        (PhoneField "Phone__c" "Phone"),
        @{ name="Email__c"; label="Email"; type="Email" },
        (DateField "Joining_Date__c" "Joining Date"),
        (CurrencyField "Monthly_Salary__c" "Monthly Salary"),
        (PicklistField "Shift__c" "Shift" @("Morning","Evening","Night","Rotational")),
        (PicklistField "Status__c" "Status" @("Active","On Leave","Inactive") "Active")
    )},
    @{ api="Doctor__c"; label="Doctor"; plural="Doctors"; sharing="Private"; nameType="Text"; nameLabel="Doctor Name"; fields=@(
        (LookupField "Staff__c" "Staff Record" "Staff__c" "Doctor Profiles" "Doctor_Profiles"),
        (LookupField "Department__c" "Department" "Department__c" "Doctors" "Doctors"),
        (TextField "Registration_Number__c" "Medical Registration Number" 50),
        (TextField "Specialization__c" "Specialization" 100),
        (CurrencyField "Consultation_Fee__c" "Consultation Fee"),
        (NumberField "Max_Daily_Appointments__c" "Max Daily Appointments" 3 0),
        (PicklistField "Availability_Status__c" "Availability Status" @("Available","Busy","Off Duty","On Leave") "Available"),
        (CheckboxField "Active__c" "Active")
    )},
    @{ api="Patient__c"; label="Patient"; plural="Patients"; sharing="Private"; nameType="Text"; nameLabel="Patient Name"; fields=@(
        (LookupField "Portal_User__c" "Portal User" "User" "Patient Profiles" "Patient_Profiles"),
        (TextField "Patient_ID__c" "Patient ID" 30),
        (DateField "Date_of_Birth__c" "Date of Birth"),
        (PicklistField "Gender__c" "Gender" @("Male","Female","Other","Prefer Not To Say")),
        (PhoneField "Phone__c" "Phone"),
        @{ name="Email__c"; label="Email"; type="Email" },
        (PicklistField "Blood_Group__c" "Blood Group" @("A+","A-","B+","B-","AB+","AB-","O+","O-")),
        (PicklistField "Patient_Category__c" "Patient Category" @("Normal","Hospital Employee","Civil Servant","Armed Professional","Insurance") "Normal"),
        (TextField "Aadhaar_Last_4__c" "Aadhaar Last 4" 4),
        (TextField "Address__c" "Address" 255),
        (PicklistField "Status__c" "Status" @("Active","Admitted","Discharged","Inactive") "Active")
    )},
    @{ api="Guardian__c"; label="Guardian"; plural="Guardians"; sharing="ControlledByParent"; nameType="Text"; nameLabel="Guardian Name"; fields=@(
        (MasterField "Patient__c" "Patient" "Patient__c" "Guardians" "Guardians"),
        (PicklistField "Relationship__c" "Relationship" @("Father","Mother","Spouse","Son","Daughter","Sibling","Relative","Friend","Legal Guardian")),
        (PhoneField "Phone__c" "Phone"),
        @{ name="Email__c"; label="Email"; type="Email" },
        (CheckboxField "Primary_Guardian__c" "Primary Guardian"),
        (TextField "Address__c" "Address" 255)
    )},
    @{ api="Ward__c"; label="Ward"; plural="Wards"; sharing="ReadWrite"; nameType="Text"; nameLabel="Ward Name"; fields=@(
        (LookupField "Department__c" "Department" "Department__c" "Wards" "Wards"),
        (PicklistField "Ward_Type__c" "Ward Type" @("ICU","OPD","General","Emergency","Private","Maternity","Pediatric")),
        (NumberField "Capacity__c" "Capacity" 5 0),
        (NumberField "Occupied_Beds__c" "Occupied Beds" 5 0),
        (TextField "Floor__c" "Floor" 20),
        (PicklistField "Status__c" "Status" @("Active","Maintenance","Inactive") "Active")
    )},
    @{ api="Room__c"; label="Room"; plural="Rooms"; sharing="ControlledByParent"; nameType="Text"; nameLabel="Room Number"; fields=@(
        (MasterField "Ward__c" "Ward" "Ward__c" "Rooms" "Rooms"),
        (PicklistField "Room_Type__c" "Room Type" @("Shared","Private","Semi Private","ICU","OPD Cabin")),
        (NumberField "Capacity__c" "Capacity" 3 0),
        (PicklistField "Status__c" "Status" @("Available","Occupied","Maintenance","Inactive") "Available")
    )},
    @{ api="Bed__c"; label="Bed"; plural="Beds"; sharing="ControlledByParent"; nameType="Text"; nameLabel="Bed Number"; fields=@(
        (MasterField "Room__c" "Room" "Room__c" "Beds" "Beds"),
        (PicklistField "Bed_Type__c" "Bed Type" @("Normal","Non AC","AC","With Washroom","ICU","Emergency")),
        (CurrencyField "Daily_Rate__c" "Daily Rate"),
        (PicklistField "Status__c" "Status" @("Available","Occupied","Reserved","Cleaning","Maintenance") "Available")
    )},
    @{ api="Insurance_Company__c"; label="Insurance Company"; plural="Insurance Companies"; sharing="ReadWrite"; nameType="Text"; nameLabel="Company Name"; fields=@(
        (PicklistField "Company_Type__c" "Company Type" @("Public Sector","Private","TPA","Government Scheme")),
        (PercentField "Standard_Discount__c" "Standard Discount"),
        (CheckboxField "Claim_API_Enabled__c" "Claim API Enabled"),
        (TextField "Support_Phone__c" "Support Phone" 30),
        (CheckboxField "Active__c" "Active")
    )},
    @{ api="Insurance_Policy__c"; label="Insurance Policy"; plural="Insurance Policies"; sharing="Private"; nameType="Text"; nameLabel="Policy Number"; fields=@(
        (LookupField "Patient__c" "Patient" "Patient__c" "Insurance Policies" "Insurance_Policies"),
        (LookupField "Insurance_Company__c" "Insurance Company" "Insurance_Company__c" "Insurance Policies" "Insurance_Policies"),
        (PicklistField "Plan_Type__c" "Plan Type" @("Individual","Family Floater","Corporate","Government","CGHS","ECHS")),
        (CurrencyField "Coverage_Limit__c" "Coverage Limit"),
        (DateField "Valid_From__c" "Valid From"),
        (DateField "Valid_To__c" "Valid To"),
        (PicklistField "Verification_Status__c" "Verification Status" @("Pending","Verified","Rejected","Expired") "Pending")
    )},
    @{ api="Doctor_Availability__c"; label="Doctor Availability"; plural="Doctor Availability"; sharing="ControlledByParent"; nameType="AutoNumber"; nameLabel="Availability Number"; displayFormat="AVL-{00000}"; fields=@(
        (MasterField "Doctor__c" "Doctor" "Doctor__c" "Availability Slots" "Availability_Slots"),
        (PicklistField "Day_of_Week__c" "Day of Week" @("Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday")),
        (TextField "Start_Time__c" "Start Time" 20),
        (TextField "End_Time__c" "End Time" 20),
        (NumberField "Slot_Capacity__c" "Slot Capacity" 3 0),
        (CheckboxField "Active__c" "Active")
    )},
    @{ api="Appointment__c"; label="Appointment"; plural="Appointments"; sharing="Private"; nameType="AutoNumber"; nameLabel="Appointment Number"; displayFormat="APT-{00000}"; fields=@(
        (LookupField "Patient__c" "Patient" "Patient__c" "Appointments" "Appointments"),
        (LookupField "Doctor__c" "Doctor" "Doctor__c" "Appointments" "Appointments"),
        (LookupField "Department__c" "Department" "Department__c" "Appointments" "Appointments"),
        (DateTimeField "Appointment_Date_Time__c" "Appointment Date Time"),
        (LongField "Symptoms__c" "Symptoms" 5000 4),
        (PicklistField "Priority__c" "Priority" @("Critical","High","Normal") "Normal"),
        (PicklistField "Source__c" "Source" @("Patient Portal","Reception","Agent","Doctor Override","Walk In")),
        (PicklistField "Status__c" "Status" @("Requested","Confirmed","Completed","Cancelled","No Show") "Requested")
    )},
    @{ api="Admission__c"; label="Admission"; plural="Admissions"; sharing="Private"; nameType="AutoNumber"; nameLabel="Admission Number"; displayFormat="ADM-{00000}"; fields=@(
        (LookupField "Patient__c" "Patient" "Patient__c" "Admissions" "Admissions"),
        (LookupField "Appointment__c" "Appointment" "Appointment__c" "Admissions" "Admissions"),
        (LookupField "Doctor__c" "Assigned Doctor" "Doctor__c" "Admissions" "Admissions"),
        (LookupField "Department__c" "Department" "Department__c" "Admissions" "Admissions"),
        (LookupField "Ward__c" "Ward" "Ward__c" "Admissions" "Admissions"),
        (LookupField "Room__c" "Room" "Room__c" "Admissions" "Admissions"),
        (LookupField "Bed__c" "Bed" "Bed__c" "Admissions" "Admissions"),
        (PicklistField "Admission_Type__c" "Admission Type" @("Emergency","Planned","Walk In","Doctor Override")),
        (PicklistField "Priority__c" "Priority" @("Critical","High","Normal") "Normal"),
        (DateTimeField "Admission_Date_Time__c" "Admission Date Time"),
        (DateTimeField "Expected_Discharge_Date_Time__c" "Expected Discharge Date Time"),
        (DateTimeField "Actual_Discharge_Date_Time__c" "Actual Discharge Date Time"),
        (PicklistField "Status__c" "Status" @("Draft","Admitted","Pending Discharge","Discharged","Cancelled") "Draft"),
        (CheckboxField "Insurance_Verified__c" "Insurance Verified"),
        (CurrencyField "Estimated_Cost__c" "Estimated Cost")
    )},
    @{ api="Bed_Allocation__c"; label="Bed Allocation"; plural="Bed Allocations"; sharing="Private"; nameType="AutoNumber"; nameLabel="Allocation Number"; displayFormat="BEDALLOC-{00000}"; fields=@(
        (LookupField "Admission__c" "Admission" "Admission__c" "Bed Allocations" "Bed_Allocations"),
        (LookupField "Bed__c" "Bed" "Bed__c" "Bed Allocations" "Bed_Allocations"),
        (DateTimeField "Start_Date_Time__c" "Start Date Time"),
        (DateTimeField "End_Date_Time__c" "End Date Time"),
        (CurrencyField "Daily_Rate__c" "Daily Rate"),
        (PicklistField "Status__c" "Status" @("Reserved","Occupied","Released","Cancelled") "Reserved")
    )},
    @{ api="Medical_Record__c"; label="Medical Record"; plural="Medical Records"; sharing="Private"; nameType="AutoNumber"; nameLabel="Medical Record Number"; displayFormat="MR-{00000}"; fields=@(
        (LookupField "Patient__c" "Patient" "Patient__c" "Medical Records" "Medical_Records"),
        (LookupField "Doctor__c" "Doctor" "Doctor__c" "Medical Records" "Medical_Records"),
        (LookupField "Appointment__c" "Appointment" "Appointment__c" "Medical Records" "Medical_Records"),
        (LookupField "Admission__c" "Admission" "Admission__c" "Medical Records" "Medical_Records"),
        (LongField "Clinical_Notes__c" "Clinical Notes" 32768 6),
        (LongField "Diagnosis_Summary__c" "Diagnosis Summary" 32768 4),
        (PicklistField "Record_Status__c" "Record Status" @("Draft","Final","Archived") "Draft")
    )},
    @{ api="Clinical_Service__c"; label="Clinical Service"; plural="Clinical Services"; sharing="ReadWrite"; nameType="Text"; nameLabel="Service Name"; fields=@(
        (LookupField "Department__c" "Department" "Department__c" "Clinical Services" "Clinical_Services"),
        (PicklistField "Service_Type__c" "Service Type" @("Consultation","Lab Test","Procedure","Surgery","Bed Charge","Pharmacy","Other")),
        (CurrencyField "Standard_Rate__c" "Standard Rate"),
        (CheckboxField "Non_Billable__c" "Non Billable"),
        (CheckboxField "Active__c" "Active")
    )},
    @{ api="Medicine__c"; label="Medicine"; plural="Medicines"; sharing="ReadWrite"; nameType="Text"; nameLabel="Medicine Name"; fields=@(
        (TextField "Brand__c" "Brand" 80),
        (TextField "Generic_Name__c" "Generic Name" 100),
        (PicklistField "Category__c" "Category" @("Tablet","Capsule","Syrup","Injection","Ointment","Drops","Other")),
        (CurrencyField "Unit_Price__c" "Unit Price"),
        (NumberField "Stock_Quantity__c" "Stock Quantity" 10 0),
        (CheckboxField "Active__c" "Active")
    )},
    @{ api="Prescription__c"; label="Prescription"; plural="Prescriptions"; sharing="Private"; nameType="AutoNumber"; nameLabel="Prescription Number"; displayFormat="RX-{00000}"; fields=@(
        (LookupField "Patient__c" "Patient" "Patient__c" "Prescriptions" "Prescriptions"),
        (LookupField "Doctor__c" "Doctor" "Doctor__c" "Prescriptions" "Prescriptions"),
        (LookupField "Medical_Record__c" "Medical Record" "Medical_Record__c" "Prescriptions" "Prescriptions"),
        (DateField "Prescription_Date__c" "Prescription Date"),
        (LongField "Instructions__c" "Instructions" 5000 4),
        (PicklistField "Status__c" "Status" @("Draft","Issued","Dispensed","Cancelled") "Draft")
    )},
    @{ api="Prescription_Line_Item__c"; label="Prescription Line Item"; plural="Prescription Line Items"; sharing="ControlledByParent"; nameType="AutoNumber"; nameLabel="Prescription Line"; displayFormat="RXLINE-{00000}"; fields=@(
        (MasterField "Prescription__c" "Prescription" "Prescription__c" "Prescription Line Items" "Prescription_Line_Items"),
        (LookupField "Medicine__c" "Medicine" "Medicine__c" "Prescription Line Items" "Prescription_Line_Items"),
        (TextField "Dosage__c" "Dosage" 80),
        (TextField "Frequency__c" "Frequency" 80),
        (NumberField "Duration_Days__c" "Duration Days" 3 0),
        (NumberField "Quantity__c" "Quantity" 8 0)
    )},
    @{ api="Invoice__c"; label="Invoice"; plural="Invoices"; sharing="Private"; nameType="AutoNumber"; nameLabel="Invoice Number"; displayFormat="INV-{00000}"; fields=@(
        (LookupField "Patient__c" "Patient" "Patient__c" "Invoices" "Invoices"),
        (LookupField "Admission__c" "Admission" "Admission__c" "Invoices" "Invoices"),
        (LookupField "Insurance_Policy__c" "Insurance Policy" "Insurance_Policy__c" "Invoices" "Invoices"),
        (PicklistField "Patient_Category__c" "Patient Category" @("Normal","Hospital Employee","Civil Servant","Armed Professional","Insurance") "Normal"),
        (DateField "Invoice_Date__c" "Invoice Date"),
        (CurrencyField "Gross_Amount__c" "Gross Amount"),
        (CurrencyField "Discount_Amount__c" "Discount Amount"),
        (CurrencyField "Insurance_Covered_Amount__c" "Insurance Covered Amount"),
        (CurrencyField "Net_Payable__c" "Net Payable"),
        (PicklistField "Payment_Status__c" "Payment Status" @("Draft","Unpaid","Partially Paid","Paid","Cancelled") "Draft")
    )},
    @{ api="Invoice_Line_Item__c"; label="Invoice Line Item"; plural="Invoice Line Items"; sharing="ControlledByParent"; nameType="AutoNumber"; nameLabel="Invoice Line"; displayFormat="INVLINE-{00000}"; fields=@(
        (MasterField "Invoice__c" "Invoice" "Invoice__c" "Invoice Line Items" "Invoice_Line_Items"),
        (LookupField "Clinical_Service__c" "Clinical Service" "Clinical_Service__c" "Invoice Line Items" "Invoice_Line_Items"),
        (LookupField "Medicine__c" "Medicine" "Medicine__c" "Invoice Line Items" "Invoice_Line_Items"),
        (NumberField "Quantity__c" "Quantity" 8 2),
        (CurrencyField "Unit_Rate__c" "Unit Rate"),
        (CurrencyField "Line_Amount__c" "Line Amount"),
        (CheckboxField "Non_Billable__c" "Non Billable")
    )},
    @{ api="Payment__c"; label="Payment"; plural="Payments"; sharing="Private"; nameType="AutoNumber"; nameLabel="Payment Number"; displayFormat="PAY-{00000}"; fields=@(
        (LookupField "Invoice__c" "Invoice" "Invoice__c" "Payments" "Payments"),
        (CurrencyField "Amount__c" "Amount"),
        (DateField "Payment_Date__c" "Payment Date"),
        (PicklistField "Payment_Mode__c" "Payment Mode" @("Cash","UPI","Card","Net Banking","Insurance","Cheque")),
        (TextField "Transaction_Reference__c" "Transaction Reference" 100),
        (PicklistField "Status__c" "Status" @("Received","Failed","Refunded") "Received")
    )},
    @{ api="Discount_Policy__c"; label="Discount Policy"; plural="Discount Policies"; sharing="ReadWrite"; nameType="Text"; nameLabel="Policy Name"; fields=@(
        (PicklistField "Patient_Category__c" "Patient Category" @("Normal","Hospital Employee","Civil Servant","Armed Professional","Insurance")),
        (LookupField "Insurance_Company__c" "Insurance Company" "Insurance_Company__c" "Discount Policies" "Discount_Policies"),
        (PercentField "Discount_Percent__c" "Discount Percent"),
        (CurrencyField "Max_Discount_Amount__c" "Max Discount Amount"),
        (CheckboxField "Active__c" "Active")
    )},
    @{ api="Final_Report__c"; label="Final Report"; plural="Final Reports"; sharing="Private"; nameType="AutoNumber"; nameLabel="Report Number"; displayFormat="FR-{00000}"; fields=@(
        (LookupField "Patient__c" "Patient" "Patient__c" "Final Reports" "Final_Reports"),
        (LookupField "Admission__c" "Admission" "Admission__c" "Final Reports" "Final_Reports"),
        (LookupField "Doctor__c" "Doctor" "Doctor__c" "Final Reports" "Final_Reports"),
        (LongField "Summary__c" "Summary" 32768 6),
        (LongField "Discharge_Advice__c" "Discharge Advice" 32768 4),
        (PicklistField "Status__c" "Status" @("Draft","Final","Shared With Patient") "Draft")
    )},
    @{ api="Donation__c"; label="Donation"; plural="Donations"; sharing="ReadWrite"; nameType="AutoNumber"; nameLabel="Donation Number"; displayFormat="DON-{00000}"; fields=@(
        (LookupField "Patient__c" "Patient" "Patient__c" "Donations" "Donations"),
        (TextField "Donor_Name__c" "Donor Name" 100),
        (CurrencyField "Amount__c" "Amount"),
        (DateField "Donation_Date__c" "Donation Date"),
        (PicklistField "Purpose__c" "Purpose" @("Charity Care","General Fund","Equipment","Blood Donation Camp","Other")),
        (PicklistField "Status__c" "Status" @("Pledged","Received","Cancelled") "Received")
    )},
    @{ api="Helpdesk_Ticket__c"; label="Helpdesk Ticket"; plural="Helpdesk Tickets"; sharing="Private"; nameType="AutoNumber"; nameLabel="Ticket Number"; displayFormat="HLP-{00000}"; fields=@(
        (LookupField "Patient__c" "Patient" "Patient__c" "Helpdesk Tickets" "Helpdesk_Tickets"),
        (PicklistField "Category__c" "Category" @("Appointment","Admission","Billing","Insurance","Pharmacy","General")),
        (PicklistField "Priority__c" "Priority" @("Low","Medium","High","Critical") "Medium"),
        (LongField "Description__c" "Description" 5000 4),
        (PicklistField "Status__c" "Status" @("New","In Progress","Resolved","Closed") "New")
    )},
    @{ api="Staff_Attendance__c"; label="Staff Attendance"; plural="Staff Attendance"; sharing="Private"; nameType="AutoNumber"; nameLabel="Attendance Number"; displayFormat="ATT-{00000}"; fields=@(
        (LookupField "Staff__c" "Staff" "Staff__c" "Attendance Records" "Attendance_Records"),
        (DateField "Attendance_Date__c" "Attendance Date"),
        (TextField "Check_In_Time__c" "Check In Time" 20),
        (TextField "Check_Out_Time__c" "Check Out Time" 20),
        (NumberField "Work_Hours__c" "Work Hours" 5 2),
        (PicklistField "Status__c" "Status" @("Present","Absent","Half Day","Leave") "Present")
    )},
    @{ api="Payroll__c"; label="Payroll"; plural="Payroll"; sharing="Private"; nameType="AutoNumber"; nameLabel="Payroll Number"; displayFormat="PAYROLL-{00000}"; fields=@(
        (LookupField "Staff__c" "Staff" "Staff__c" "Payroll Records" "Payroll_Records"),
        (PicklistField "Payroll_Month__c" "Payroll Month" @("January","February","March","April","May","June","July","August","September","October","November","December")),
        (NumberField "Payroll_Year__c" "Payroll Year" 4 0),
        (CurrencyField "Gross_Pay__c" "Gross Pay"),
        (CurrencyField "Deductions__c" "Deductions"),
        (CurrencyField "Net_Pay__c" "Net Pay"),
        (PicklistField "Status__c" "Status" @("Draft","Approved","Paid") "Draft")
    )},
    @{ api="Payslip__c"; label="Payslip"; plural="Payslips"; sharing="ControlledByParent"; nameType="AutoNumber"; nameLabel="Payslip Number"; displayFormat="PS-{00000}"; fields=@(
        (MasterField "Payroll__c" "Payroll" "Payroll__c" "Payslips" "Payslips"),
        (DateField "Generated_Date__c" "Generated Date"),
        (TextField "Document_URL__c" "Document URL" 255),
        (PicklistField "Status__c" "Status" @("Generated","Shared","Cancelled") "Generated")
    )},
    @{ api="Lab_Test__c"; label="Lab Test"; plural="Lab Tests"; sharing="ReadWrite"; nameType="Text"; nameLabel="Lab Test Name"; fields=@(
        (LookupField "Department__c" "Department" "Department__c" "Lab Tests" "Lab_Tests"),
        (CurrencyField "Standard_Rate__c" "Standard Rate"),
        (TextField "Sample_Type__c" "Sample Type" 80),
        (CheckboxField "Active__c" "Active")
    )},
    @{ api="Lab_Result__c"; label="Lab Result"; plural="Lab Results"; sharing="Private"; nameType="AutoNumber"; nameLabel="Lab Result Number"; displayFormat="LABRES-{00000}"; fields=@(
        (LookupField "Patient__c" "Patient" "Patient__c" "Lab Results" "Lab_Results"),
        (LookupField "Admission__c" "Admission" "Admission__c" "Lab Results" "Lab_Results"),
        (LookupField "Lab_Test__c" "Lab Test" "Lab_Test__c" "Lab Results" "Lab_Results"),
        (LookupField "Doctor__c" "Requested By" "Doctor__c" "Requested Lab Results" "Requested_Lab_Results"),
        (LongField "Result_Summary__c" "Result Summary" 32768 4),
        (PicklistField "Status__c" "Status" @("Ordered","Sample Collected","Completed","Cancelled") "Ordered")
    )},
    @{ api="Discharge__c"; label="Discharge"; plural="Discharges"; sharing="Private"; nameType="AutoNumber"; nameLabel="Discharge Number"; displayFormat="DIS-{00000}"; fields=@(
        (LookupField "Admission__c" "Admission" "Admission__c" "Discharges" "Discharges"),
        (LookupField "Patient__c" "Patient" "Patient__c" "Discharges" "Discharges"),
        (LookupField "Doctor__c" "Approved By" "Doctor__c" "Approved Discharges" "Approved_Discharges"),
        (DateTimeField "Discharge_Date_Time__c" "Discharge Date Time"),
        (PicklistField "Status__c" "Status" @("Pending Approval","Approved","Completed","Blocked - Unpaid Bill") "Pending Approval"),
        (LongField "Discharge_Notes__c" "Discharge Notes" 32768 4)
    )},
    @{ api="Notification_Log__c"; label="Notification Log"; plural="Notification Logs"; sharing="Private"; nameType="AutoNumber"; nameLabel="Notification Number"; displayFormat="NTF-{00000}"; fields=@(
        (LookupField "Patient__c" "Patient" "Patient__c" "Notification Logs" "Notification_Logs"),
        (PicklistField "Channel__c" "Channel" @("Email","SMS","WhatsApp","In App")),
        (TextField "Recipient__c" "Recipient" 120),
        (TextField "Subject__c" "Subject" 180),
        (LongField "Message__c" "Message" 32768 4),
        (PicklistField "Status__c" "Status" @("Queued","Sent","Failed") "Queued")
    )},
    @{ api="Audit_Log__c"; label="Audit Log"; plural="Audit Logs"; sharing="Private"; nameType="AutoNumber"; nameLabel="Audit Number"; displayFormat="AUD-{00000}"; fields=@(
        (TextField "Object_Name__c" "Object Name" 80),
        (TextField "Record_Id__c" "Record Id" 18),
        (TextField "Action__c" "Action" 80),
        (LongField "Change_Detail__c" "Change Detail" 32768 5),
        (DateTimeField "Change_Date_Time__c" "Change Date Time")
    )}
)

foreach ($o in $objects) {
    $dir = Join-Path $objectsDir $o.api
    New-Item -ItemType Directory -Force -Path $dir,(Join-Path $dir "fields") | Out-Null
    $nameField = if ($o.nameType -eq "AutoNumber") {
@"
    <nameField>
        <displayFormat>$($o.displayFormat)</displayFormat>
        <label>$($o.nameLabel)</label>
        <type>AutoNumber</type>
    </nameField>
"@
    } else {
@"
    <nameField>
        <label>$($o.nameLabel)</label>
        <type>Text</type>
    </nameField>
"@
    }
    $objectXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
    <deploymentStatus>Deployed</deploymentStatus>
    <description>Hospital Management System object for $($o.label).</description>
    <enableActivities>true</enableActivities>
    <enableBulkApi>true</enableBulkApi>
    <enableFeeds>false</enableFeeds>
    <enableHistory>true</enableHistory>
    <enableReports>true</enableReports>
    <label>$($o.label)</label>
$nameField
    <pluralLabel>$($o.plural)</pluralLabel>
    <searchLayouts/>
    <sharingModel>$($o.sharing)</sharingModel>
</CustomObject>
"@
    Set-Content -Path (Join-Path $dir "$($o.api).object-meta.xml") -Value $objectXml -Encoding UTF8
    foreach ($f in $o.fields) {
        Set-Content -Path (Join-Path $dir "fields/$($f.name).field-meta.xml") -Value (FieldXml $f) -Encoding UTF8
    }

    $tabXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<CustomTab xmlns="http://soap.sforce.com/2006/04/metadata">
    <customObject>true</customObject>
    <motif>Custom63: Chip</motif>
</CustomTab>
"@
    Set-Content -Path (Join-Path $tabsDir "$($o.api).tab-meta.xml") -Value $tabXml -Encoding UTF8
}

$appTabs = @("standard-home","Patient__c","Appointment__c","Admission__c","Doctor__c","Guardian__c","Ward__c","Room__c","Bed__c","Bed_Allocation__c","Medical_Record__c","Clinical_Service__c","Medicine__c","Prescription__c","Insurance_Company__c","Insurance_Policy__c","Invoice__c","Payment__c","Final_Report__c","Donation__c","Helpdesk_Ticket__c","Staff__c","Staff_Attendance__c","Payroll__c","Lab_Test__c","Lab_Result__c","Department__c")
$tabsXml = ($appTabs | ForEach-Object { "    <tabs>$_</tabs>" }) -join "`n"
$appXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<CustomApplication xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>Custom Hospital Management System app for staff, doctors, billing, pharmacy, lab, and patient-service operations.</description>
    <formFactors>Large</formFactors>
    <isNavAutoTempTabsDisabled>false</isNavAutoTempTabsDisabled>
    <isNavPersonalizationDisabled>false</isNavPersonalizationDisabled>
    <label>Hospital Management</label>
    <navType>Standard</navType>
$tabsXml
    <uiType>Lightning</uiType>
</CustomApplication>
"@
Set-Content -Path (Join-Path $appsDir "Hospital_Management.app-meta.xml") -Value $appXml -Encoding UTF8

$patientAppTabs = @("standard-home","Appointment__c","Medical_Record__c","Lab_Result__c","Admission__c","Final_Report__c","Invoice__c","Payment__c","Insurance_Policy__c")
$patientTabsXml = ($patientAppTabs | ForEach-Object { "    <tabs>$_</tabs>" }) -join "`n"
$patientAppXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<CustomApplication xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>Salesforce-authenticated patient-service app surface for appointments, reports, payments, invoices, and insurance details.</description>
    <formFactors>Large</formFactors>
    <isNavAutoTempTabsDisabled>false</isNavAutoTempTabsDisabled>
    <isNavPersonalizationDisabled>false</isNavPersonalizationDisabled>
    <label>Hospital Patient Portal</label>
    <navType>Standard</navType>
$patientTabsXml
    <uiType>Lightning</uiType>
</CustomApplication>
"@
Set-Content -Path (Join-Path $appsDir "Hospital_Patient_Portal.app-meta.xml") -Value $patientAppXml -Encoding UTF8

$relatedListsByObject = @{}
foreach ($o in $objects) {
    $relatedListsByObject[$o.api] = New-Object System.Collections.Generic.List[string]
}
foreach ($child in $objects) {
    foreach ($f in $child.fields) {
        if (($f["type"] -eq "Lookup" -or $f["type"] -eq "MasterDetail") -and $relatedListsByObject.ContainsKey($f["referenceTo"])) {
            $childApi = $child["api"]
            $lookupFieldApi = $f["name"]
            $childRelationshipApi = "$childApi.$lookupFieldApi"
            if (-not $relatedListsByObject[$f["referenceTo"]].Contains($childRelationshipApi)) {
                $relatedListsByObject[$f["referenceTo"]].Add($childRelationshipApi)
            }
        }
    }
}

foreach ($o in $objects) {
    $layoutName = "$($o.api)-$($o.label) Layout"
    $leftItems = New-Object System.Collections.Generic.List[object]
    $rightItems = New-Object System.Collections.Generic.List[object]

    $nameBehavior = if ($o.nameType -eq "AutoNumber") { "Readonly" } else { "Required" }
    $leftItems.Add(@{ field = "Name"; behavior = $nameBehavior })

    $index = 0
    foreach ($f in $o.fields) {
        $behavior = if ($f["required"] -or $f["type"] -eq "MasterDetail") { "Required" } else { "Edit" }
        $item = @{ field = $f["name"]; behavior = $behavior }
        if (($index % 2) -eq 0) {
            $rightItems.Add($item)
        } else {
            $leftItems.Add($item)
        }
        $index++
    }

    function LayoutColumnXml($items) {
        $text = "        <layoutColumns>`n"
        foreach ($item in $items) {
            $text += "            <layoutItems>`n"
            $text += "                <behavior>$($item.behavior)</behavior>`n"
            $text += "                <field>$($item.field)</field>`n"
            $text += "            </layoutItems>`n"
        }
        $text += "        </layoutColumns>`n"
        return $text
    }

    $layoutXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Layout xmlns="http://soap.sforce.com/2006/04/metadata">
    <layoutSections>
        <customLabel>false</customLabel>
        <detailHeading>true</detailHeading>
        <editHeading>true</editHeading>
        <label>Information</label>
"@
    $layoutXml += LayoutColumnXml $leftItems
    $layoutXml += LayoutColumnXml $rightItems
    $layoutXml += @"
        <style>TwoColumnsTopToBottom</style>
    </layoutSections>
"@
    foreach ($relatedList in ($relatedListsByObject[$o.api] | Sort-Object)) {
        $layoutXml += @"
    <relatedLists>
        <fields>NAME</fields>
        <relatedList>$relatedList</relatedList>
    </relatedLists>
"@
    }
    $layoutXml += @"
</Layout>
"@
    Set-Content -Path (Join-Path $layoutsDir "$layoutName.layout-meta.xml") -Value $layoutXml -Encoding UTF8
}

$roles = @(
    @{ name="Hospital_Admin"; label="Hospital Admin"; parent=$null },
    @{ name="Cardiology_Head"; label="Cardiology Head"; parent="Hospital_Admin" },
    @{ name="Oncology_Head"; label="Oncology Head"; parent="Hospital_Admin" },
    @{ name="Neurology_Head"; label="Neurology Head"; parent="Hospital_Admin" },
    @{ name="Orthopedics_Head"; label="Orthopedics Head"; parent="Hospital_Admin" },
    @{ name="General_Medicine_Head"; label="General Medicine Head"; parent="Hospital_Admin" },
    @{ name="Emergency_Head"; label="Emergency Head"; parent="Hospital_Admin" },
    @{ name="Lab_Head"; label="Lab Head"; parent="Hospital_Admin" },
    @{ name="Reception_Head"; label="Reception Head"; parent="Hospital_Admin" },
    @{ name="Pharmacy_Manager"; label="Pharmacy Manager"; parent="Hospital_Admin" },
    @{ name="Finance_Head"; label="Finance Head"; parent="Hospital_Admin" },
    @{ name="Cardiology_Doctor"; label="Cardiology Doctor"; parent="Cardiology_Head" },
    @{ name="Cardiology_Nurse"; label="Cardiology Nurse"; parent="Cardiology_Doctor" },
    @{ name="Cardiology_Resident"; label="Cardiology Resident"; parent="Cardiology_Doctor" },
    @{ name="Oncology_Doctor"; label="Oncology Doctor"; parent="Oncology_Head" },
    @{ name="Oncology_Nurse"; label="Oncology Nurse"; parent="Oncology_Doctor" },
    @{ name="Oncology_Resident"; label="Oncology Resident"; parent="Oncology_Doctor" },
    @{ name="Neurology_Doctor"; label="Neurology Doctor"; parent="Neurology_Head" },
    @{ name="Neurology_Nurse"; label="Neurology Nurse"; parent="Neurology_Doctor" },
    @{ name="Neurology_Resident"; label="Neurology Resident"; parent="Neurology_Doctor" },
    @{ name="Orthopedics_Doctor"; label="Orthopedics Doctor"; parent="Orthopedics_Head" },
    @{ name="Orthopedics_Nurse"; label="Orthopedics Nurse"; parent="Orthopedics_Doctor" },
    @{ name="Orthopedics_Resident"; label="Orthopedics Resident"; parent="Orthopedics_Doctor" },
    @{ name="General_Medicine_Doctor"; label="General Medicine Doctor"; parent="General_Medicine_Head" },
    @{ name="General_Medicine_Nurse"; label="General Medicine Nurse"; parent="General_Medicine_Doctor" },
    @{ name="General_Medicine_Resident"; label="General Medicine Resident"; parent="General_Medicine_Doctor" },
    @{ name="Emergency_Doctor"; label="Emergency Doctor"; parent="Emergency_Head" },
    @{ name="Emergency_Nurse"; label="Emergency Nurse"; parent="Emergency_Doctor" },
    @{ name="Emergency_Resident"; label="Emergency Resident"; parent="Emergency_Doctor" },
    @{ name="Lab_Assistant"; label="Lab Assistant"; parent="Lab_Head" },
    @{ name="Receptionist"; label="Receptionist"; parent="Reception_Head" },
    @{ name="Pharmacist"; label="Pharmacist"; parent="Pharmacy_Manager" },
    @{ name="Payroll_Manager"; label="Payroll Manager"; parent="Finance_Head" },
    @{ name="Billing_Manager"; label="Billing Manager"; parent="Finance_Head" },
    @{ name="Billing_Executive"; label="Billing Executive"; parent="Billing_Manager" },
    @{ name="Billing_Assistant"; label="Billing Assistant"; parent="Billing_Manager" }
)
foreach ($r in $roles) {
    $parentXml = if ($r.parent) { "    <parentRole>$($r.parent)</parentRole>`n" } else { "" }
    $roleXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<Role xmlns="http://soap.sforce.com/2006/04/metadata">
    <caseAccessLevel>Edit</caseAccessLevel>
    <contactAccessLevel>Edit</contactAccessLevel>
    <name>$($r.name)</name>
    <opportunityAccessLevel>Edit</opportunityAccessLevel>
$parentXml</Role>
"@
    Set-Content -Path (Join-Path $rolesDir "$($r.name).role-meta.xml") -Value $roleXml -Encoding UTF8
}

$permXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>Full admin access for the custom Hospital Management System data model.</description>
    <hasActivationRequired>false</hasActivationRequired>
    <label>HMS Admin Access</label>
    <license>Salesforce</license>
"@
foreach ($o in $objects) {
    foreach ($f in $o.fields) {
        if ($f["type"] -eq "MasterDetail") { continue }
        $permXml += @"
    <fieldPermissions>
        <editable>true</editable>
        <field>$($o.api).$($f.name)</field>
        <readable>true</readable>
    </fieldPermissions>
"@
    }
}
foreach ($o in $objects) {
    $permXml += @"
    <objectPermissions>
        <allowCreate>true</allowCreate>
        <allowDelete>true</allowDelete>
        <allowEdit>true</allowEdit>
        <allowRead>true</allowRead>
        <modifyAllRecords>true</modifyAllRecords>
        <object>$($o.api)</object>
        <viewAllRecords>true</viewAllRecords>
    </objectPermissions>
"@
}
foreach ($tab in $appTabs | Where-Object { $_ -like "*__c" }) {
    $permXml += @"
    <tabSettings>
        <tab>$tab</tab>
        <visibility>Visible</visibility>
    </tabSettings>
"@
}
$permXml += "</PermissionSet>`n"
Set-Content -Path (Join-Path $permsetsDir "HMS_Admin.permissionset-meta.xml") -Value $permXml -Encoding UTF8

function PermissionSetXml($label, $description, $visibleApp, $hiddenApp, $visibleTabs, $hiddenTabs, $objectAccessByApi, $fieldEditByApi) {
    $xml = @"
<?xml version="1.0" encoding="UTF-8"?>
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>$description</description>
    <hasActivationRequired>false</hasActivationRequired>
    <label>$label</label>
"@
    if ($label -eq "HMS Patient User") {
        $xml += @"
    <classAccesses>
        <apexClass>HMSPatientPortalController</apexClass>
        <enabled>true</enabled>
    </classAccesses>
"@
    }
    if ($label -eq "HMS Hospital Staff") {
        $xml += @"
    <userPermissions>
        <enabled>true</enabled>
        <name>LightningExperienceUser</name>
    </userPermissions>
"@
    }
    $xml += @"
    <applicationVisibilities>
        <application>$visibleApp</application>
        <visible>true</visible>
    </applicationVisibilities>
    <applicationVisibilities>
        <application>$hiddenApp</application>
        <visible>false</visible>
    </applicationVisibilities>
"@
    foreach ($o in $objects) {
        if (-not $objectAccessByApi.ContainsKey($o.api)) { continue }
        $fieldEditable = $fieldEditByApi.ContainsKey($o.api) -and $fieldEditByApi[$o.api]
        foreach ($f in $o.fields) {
            if ($f["type"] -eq "MasterDetail") { continue }
            $xml += @"
    <fieldPermissions>
        <editable>$($fieldEditable.ToString().ToLower())</editable>
        <field>$($o.api).$($f.name)</field>
        <readable>true</readable>
    </fieldPermissions>
"@
        }
    }
    foreach ($o in $objects) {
        if (-not $objectAccessByApi.ContainsKey($o.api)) { continue }
        $access = $objectAccessByApi[$o.api]
        $xml += @"
    <objectPermissions>
        <allowCreate>$($access.create.ToString().ToLower())</allowCreate>
        <allowDelete>$($access.delete.ToString().ToLower())</allowDelete>
        <allowEdit>$($access.edit.ToString().ToLower())</allowEdit>
        <allowRead>true</allowRead>
        <modifyAllRecords>false</modifyAllRecords>
        <object>$($o.api)</object>
        <viewAllRecords>$($access.viewAll.ToString().ToLower())</viewAllRecords>
    </objectPermissions>
"@
    }
    foreach ($tab in $visibleTabs) {
        if ($tab -like "*__c") {
            $xml += @"
    <tabSettings>
        <tab>$tab</tab>
        <visibility>Visible</visibility>
    </tabSettings>
"@
        }
    }
    foreach ($tab in $hiddenTabs) {
        if ($tab -like "*__c" -and -not ($visibleTabs -contains $tab)) {
            $xml += @"
    <tabSettings>
        <tab>$tab</tab>
        <visibility>None</visibility>
    </tabSettings>
"@
        }
    }
    $xml += "</PermissionSet>`n"
    return $xml
}

$patientReadOnly = @{ create=$false; edit=$false; delete=$false; viewAll=$false }
$patientWritable = @{ create=$true; edit=$true; delete=$false; viewAll=$false }
$patientObjects = @{
    "Patient__c" = $patientReadOnly
    "Appointment__c" = $patientWritable
    "Medical_Record__c" = $patientReadOnly
    "Lab_Result__c" = $patientReadOnly
    "Admission__c" = $patientReadOnly
    "Discharge__c" = $patientReadOnly
    "Final_Report__c" = $patientReadOnly
    "Invoice__c" = $patientReadOnly
    "Invoice_Line_Item__c" = $patientReadOnly
    "Payment__c" = $patientWritable
    "Insurance_Policy__c" = $patientWritable
    "Insurance_Company__c" = $patientReadOnly
}
$patientFieldEdit = @{
    "Appointment__c" = $true
    "Payment__c" = $true
    "Insurance_Policy__c" = $true
}
$allCustomTabs = $appTabs | Where-Object { $_ -like "*__c" }
$patientVisibleTabs = $patientAppTabs | Where-Object { $_ -like "*__c" }
$patientHiddenTabs = $allCustomTabs | Where-Object { -not ($patientVisibleTabs -contains $_) }
$patientPermXml = PermissionSetXml "HMS Patient User" "Native Salesforce access for patient users. Exposes only appointments, reports, payments, invoices, and insurance details." "Hospital_Patient_Portal" "Hospital_Management" $patientVisibleTabs $patientHiddenTabs $patientObjects $patientFieldEdit
Set-Content -Path (Join-Path $permsetsDir "HMS_Patient_User.permissionset-meta.xml") -Value $patientPermXml -Encoding UTF8

$staffObjects = @{}
$staffFieldEdit = @{}
foreach ($o in $objects) {
    $staffObjects[$o.api] = @{ create=$true; edit=$true; delete=$false; viewAll=$true }
    $staffFieldEdit[$o.api] = $true
}
$staffVisibleTabs = $appTabs | Where-Object { $_ -like "*__c" }
$staffPermXml = PermissionSetXml "HMS Hospital Staff" "Native Salesforce access for hospital staff users across the operational Hospital Management app." "Hospital_Management" "Hospital_Patient_Portal" $staffVisibleTabs @() $staffObjects $staffFieldEdit
Set-Content -Path (Join-Path $permsetsDir "HMS_Hospital_Staff.permissionset-meta.xml") -Value $staffPermXml -Encoding UTF8

Write-Host "Generated $($objects.Count) objects, $($objects.Count) tabs, 2 Lightning apps, $($roles.Count) roles, and 3 permission sets."
