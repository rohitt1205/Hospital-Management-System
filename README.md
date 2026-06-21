# Hospital Management System (HMS)

An end-to-end, enterprise-grade Hospital Management System built on the Salesforce Platform. This project integrates core clinical workflows (admissions, doctor scheduling, ward/bed allocations, lab results, prescriptions) with modern third-party services like Twilio (WhatsApp notifications), Razorpay (payments), CRM Analytics, and Datadog monitoring.

---

## 🌟 Key Features & Modules

### 1. Clinical Workflows & Patient Portal
- **Patient Intake & Admissions**: Automated patient onboarding and tracking from triage/emergency to discharge.
- **Doctor Assignment & Scheduling**: Match patients to doctors based on department availability and auto-assign emergency fallback coverage.
- **Today's Appointments Panel**: Lightning Web Components (LWC) providing live lists of scheduled appointments for staff.

### 2. Intelligent Ward & Bed Allocation
- **Dynamic Capacity Control**: Custom Apex validation in `RoomCodeGenerator.cls` and validation rules check manual inputs against `Ward__c` capacity.
- **Auto-Sequence Numbering**: Auto-generates sequential room numbering prefixes (e.g., `OPD001`, `OPD002`) during insertions, while validating capacity.
- **Real-Time Bed Booking**: Interactive flows for allocating beds dynamically during patient admissions.

### 3. Emergency SLA Automation
- **Automatic Task Escalation**: If an emergency admission is checked in without a doctor assigned, the system automatically routes tasks to administrative backups (e.g. System Administrators or designated `Hospital_Admin` queues) using safe system-context queries (`WITH SYSTEM_MODE`) to support portal and guest users.

### 4. Insurance & Billing Integration
- **Queueable Verification**: Scalable asynchronous queueable class `InsuranceVerificationQueueable.cls` performs insurance validations, and updates invoice records securely.
- **Secure DML Processing**: DML executes in `AccessLevel.SYSTEM_MODE` preventing guest user permission check failure during checkout transitions.

### 5. Third-Party Integrations
- **WhatsApp Notification Service**: Integrates with Twilio API via custom metadata config to send notifications to patient phone numbers.
- **Razorpay Payment Gateway**: Provides integrated checkout, signature validation, and secure payment processing.
- **Datadog Monitoring & CRMA**: Tracks org health metrics and provides analytics on patient outcomes and SLA performance.

---

## 📂 Repository Structure

```
├── force-app/main/default/
│   ├── classes/             # Apex Controllers, Triggers, Handlers, and Test Classes
│   ├── flows/               # Salesforce Screen & Autolaunched Flows (e.g. Discharge processing)
│   ├── lwc/                 # Lightning Web Components for front-end interface
│   ├── objects/             # Custom SObject schemas and validation rules (e.g., Room__c, Ward__c)
│   ├── customMetadata/      # Integration settings schemas & placeholder settings
│   └── triggers/            # Trigger definitions for clinical object business rules
├── manifest/                # Package manifest files and destructive change manifests
├── scripts/                 # Post-deployment apex and scripting files for data seeding
└── sfdx-project.json        # Salesforce project configuration
```

---

## ⚙️ Setup & Deployment

### Prerequisites
1. Install [Salesforce CLI (sf)](https://developer.salesforce.com/tools/sfdxcli).
2. Create or authenticate to a Salesforce Developer Hub / Scratch Org.

### 1. Authenticate to your Org
```bash
sf org login web -d -a hms-org
```

### 2. Deploy Metadata
Deploy the codebase metadata to your active target org:
```bash
sf project deploy start
```

### 3. Post-Deployment Setup & Data Seeding
Run the following Apex scripts using Salesforce CLI to seed test records, setup demo users, and configure profile permissions:
```bash
# Seed initial sample configuration/records
sf apex run --file scripts/seed_hms_data.apex

# Enable Patient Service object permissions and FLS 
sf apex run --file scripts/apply_patient_service_obj_perms.apex
sf apex run --file scripts/apply_patient_service_fls.apex
```

### 4. Running Tests
Verify implementation correctness by running Apex test suites:
```bash
sf apex run test --class-names EmergencyAdmissionSlaServiceTest RoomCodeGeneratorTest FinalReportAutomationHandlerTest HMS_PaymentControllerTest --result-format human
```

---

## 🔒 Configuration & Credentials Safety

This repository uses Custom Metadata Types for holding integration settings. Sensitive fields are masked in this repository for safety:
- **Twilio Config**: [Twilio_Configuration.Hospital_WhatsApp_Config.md-meta.xml](force-app/main/default/customMetadata/Twilio_Configuration.Hospital_WhatsApp_Config.md-meta.xml)
- **Razorpay Config**: [Razorpay_Setting.Default.md-meta.xml](force-app/main/default/customMetadata/Razorpay_Setting.Default.md-meta.xml)

To configure integrations on your target org:
1. Navigate to **Setup** > **Custom Metadata Types**.
2. Click **Manage Records** on `Twilio Configuration` and `Razorpay Setting`.
3. Input your active production/sandbox API keys and Account SIDs. **Do not commit these values back to the repository.**
