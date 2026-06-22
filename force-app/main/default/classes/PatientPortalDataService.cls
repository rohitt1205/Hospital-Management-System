/**
 * Loads all patient-scoped portal data in SYSTEM_MODE.
 *
 * @AuraEnabled LWC entry points run in user mode at API 67+, so inline SOQL must
 * use WITH SYSTEM_MODE to return every record linked to the patient — not only
 * records the portal user created/owns.
 */
public without sharing class PatientPortalDataService {

    public static void enrichSummary(Map<String, Object> summary, Patient__c patient) {
        populateProfile(summary, patient);
        Id patientId = patient.Id;

        try { populateAppointments(summary, patientId); } catch (Exception e) { System.debug('Appointments skipped: ' + e.getMessage()); }
        try { populateReports(summary, patientId); } catch (Exception e) { System.debug('Reports skipped: ' + e.getMessage()); }
        try { populatePrescriptions(summary, patientId); } catch (Exception e) { System.debug('Prescriptions skipped: ' + e.getMessage()); }
        try { populateInvoices(summary, patientId); } catch (Exception e) { System.debug('Invoices skipped: ' + e.getMessage()); }
        try { populatePayments(summary, patientId); } catch (Exception e) { System.debug('Payments skipped: ' + e.getMessage()); }
        try { populateInsurance(summary, patientId); } catch (Exception e) { System.debug('Insurance skipped: ' + e.getMessage()); }
    }

    public static Map<String, Object> baseSummary() {
        return new Map<String, Object>{
            'linked' => false,
            'patientName' => 'Patient',
            'patientId' => '',
            'category' => '',
            'status' => '',
            'gender' => '',
            'bloodGroup' => '',
            'age' => null,
            'dateOfBirth' => null,
            'phone' => '',
            'email' => '',
            'address' => '',
            'approvalStatus' => '',
            'appointmentCount' => 0,
            'upcomingAppointmentCount' => 0,
            'reportCount' => 0,
            'prescriptionCount' => 0,
            'invoiceCount' => 0,
            'paymentCount' => 0,
            'pendingAmount' => 0,
            'appointments' => new List<Map<String, Object>>(),
            'reports' => new List<Map<String, Object>>(),
            'prescriptions' => new List<Map<String, Object>>(),
            'invoices' => new List<Map<String, Object>>(),
            'payments' => new List<Map<String, Object>>(),
            'insurancePolicies' => new List<Map<String, Object>>()
        };
    }

    private static void populateProfile(Map<String, Object> summary, Patient__c patient) {
        summary.put('patientName', patient.Name);
        summary.put('patientSfId', patient.Id);
        summary.put('patientId', patient.Patient_ID__c);
        summary.put('category', patient.Patient_Category__c);
        summary.put('status', patient.Status__c);
        summary.put('gender', patient.Gender__c);
        summary.put('bloodGroup', patient.Blood_Group__c);
        summary.put('age', calculateAge(patient.Date_of_Birth__c));
        summary.put('dateOfBirth', patient.Date_of_Birth__c);
        summary.put('phone', patient.Phone__c);
        summary.put('email', patient.Email__c);
        summary.put('address', patient.Address__c);
        summary.put('approvalStatus', patient.Patient_Approval_Status__c);
    }

    private static void populateAppointments(Map<String, Object> summary, Id patientId) {
        List<Map<String, Object>> appointments = new List<Map<String, Object>>();
        Integer upcoming = 0;
        Datetime now = Datetime.now();
        Date today = Date.today();
        for (Appointment__c appointment : [
            SELECT Id, Name, Appointment_Date_Time__c, Appointment_Date__c, Status__c,
                   Priority__c, Appointment_Type__c, Symptoms__c, Source__c,
                   Doctor__r.Name, Department__r.Name,
                   (SELECT Join_URL__c FROM Meeting_Logs__r ORDER BY CreatedDate DESC LIMIT 1)
            FROM Appointment__c
            WHERE Patient__c = :patientId
            WITH SYSTEM_MODE
            ORDER BY Appointment_Date_Time__c DESC NULLS LAST, CreatedDate DESC
        ]) {
            Boolean isUpcoming = isUpcomingAppointment(appointment, now, today);
            if (isUpcoming) {
                upcoming++;
            }
            String joinUrlVal = null;
            if (appointment.Meeting_Logs__r != null && !appointment.Meeting_Logs__r.isEmpty()) {
                joinUrlVal = appointment.Meeting_Logs__r[0].Join_URL__c;
            }
            appointments.add(new Map<String, Object>{
                'recordId' => appointment.Id,
                'numberValue' => appointment.Name,
                'doctorName' => appointment.Doctor__r != null ? appointment.Doctor__r.Name : 'To be assigned',
                'departmentName' => appointment.Department__r != null ? appointment.Department__r.Name : 'Hospital Care',
                'appointmentType' => appointment.Appointment_Type__c,
                'appointmentDateTime' => appointment.Appointment_Date_Time__c,
                'appointmentDate' => appointment.Appointment_Date__c,
                'status' => appointment.Status__c,
                'priority' => appointment.Priority__c,
                'symptoms' => appointment.Symptoms__c,
                'source' => appointment.Source__c,
                'upcoming' => isUpcoming,
                'joinUrl' => joinUrlVal
            });
        }
        summary.put('appointments', appointments);
        summary.put('appointmentCount', appointments.size());
        summary.put('upcomingAppointmentCount', upcoming);
    }

    private static Boolean isUpcomingAppointment(Appointment__c appointment, Datetime now, Date today) {
        if (appointment.Status__c == 'Cancelled' || appointment.Status__c == 'Completed') {
            return false;
        }
        if (appointment.Appointment_Date_Time__c != null) {
            return appointment.Appointment_Date_Time__c >= now;
        }
        if (appointment.Appointment_Date__c != null) {
            return appointment.Appointment_Date__c >= today;
        }
        return false;
    }

    private static void populateReports(Map<String, Object> summary, Id patientId) {
        List<Final_Report__c> finalReports = [
            SELECT Id, Name, Status__c, Summary__c, Discharge_Advice__c, CreatedDate,
                   Doctor__r.Name, Admission__r.Name
            FROM Final_Report__c
            WHERE Patient__c = :patientId
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        List<Map<String, Object>> reports = new List<Map<String, Object>>();
        if (!finalReports.isEmpty()) {
            Final_Report__c finalReport = finalReports[0];
            Map<String, Object> reportRow = new Map<String, Object>{
                'recordId' => finalReport.Id,
                'reportType' => 'Final Report',
                'icon' => 'utility:summarydetail',
                'numberValue' => finalReport.Name,
                'status' => finalReport.Status__c,
                'summary' => finalReport.Summary__c,
                'dischargeAdvice' => finalReport.Discharge_Advice__c,
                'doctorName' => finalReport.Doctor__r != null ? finalReport.Doctor__r.Name : null,
                'admissionName' => finalReport.Admission__r != null ? finalReport.Admission__r.Name : null,
                'sortDate' => finalReport.CreatedDate
            };
            reports.add(reportRow);
            summary.put('finalReport', reportRow);
            summary.put('hasFinalReport', true);
        } else {
            summary.put('finalReport', null);
            summary.put('hasFinalReport', false);
        }

        summary.put('reports', reports);
        summary.put('reportCount', reports.size());
    }

    private static void populatePrescriptions(Map<String, Object> summary, Id patientId) {
        List<Map<String, Object>> prescriptions = new List<Map<String, Object>>();
        for (Prescription__c rx : [
            SELECT Name, Prescription_Date__c, Status__c, Instructions__c,
                   Total_Medicine_Bill__c, Doctor__r.Name
            FROM Prescription__c
            WHERE Patient__c = :patientId
            WITH SYSTEM_MODE
            ORDER BY Prescription_Date__c DESC NULLS LAST, CreatedDate DESC
        ]) {
            prescriptions.add(new Map<String, Object>{
                'numberValue' => rx.Name,
                'prescriptionDate' => rx.Prescription_Date__c,
                'status' => rx.Status__c,
                'instructions' => rx.Instructions__c,
                'totalBill' => rx.Total_Medicine_Bill__c,
                'doctorName' => rx.Doctor__r != null ? rx.Doctor__r.Name : ''
            });
        }
        summary.put('prescriptions', prescriptions);
        summary.put('prescriptionCount', prescriptions.size());
    }

    private static void populateInvoices(Map<String, Object> summary, Id patientId) {
        Decimal pendingAmount = 0;
        List<Map<String, Object>> invoices = new List<Map<String, Object>>();
        for (Invoice__c invoice : [
            SELECT Id, Name, Payment_Status__c, Net_Payable__c, Insurance_Covered_Amount__c, Invoice_Date__c
            FROM Invoice__c
            WHERE Patient__c = :patientId
            WITH SYSTEM_MODE
            ORDER BY Invoice_Date__c DESC NULLS LAST, CreatedDate DESC
        ]) {
            Decimal netPayable = invoice.Net_Payable__c == null ? 0 : invoice.Net_Payable__c;
            invoices.add(new Map<String, Object>{
                'invoiceSfId' => invoice.Id,
                'numberValue' => invoice.Name,
                'paymentStatus' => invoice.Payment_Status__c,
                'netPayable' => netPayable,
                'insuranceCoveredAmount' => invoice.Insurance_Covered_Amount__c,
                'invoiceDate' => invoice.Invoice_Date__c
            });
            if (invoice.Payment_Status__c != 'Paid') {
                pendingAmount = pendingAmount + netPayable;
            }
        }
        summary.put('invoices', invoices);
        summary.put('invoiceCount', invoices.size());
        summary.put('pendingAmount', pendingAmount);
    }

    private static void populatePayments(Map<String, Object> summary, Id patientId) {
        List<Map<String, Object>> payments = new List<Map<String, Object>>();
        for (Payment__c payment : [
            SELECT Name, Amount__c, Payment_Date__c, Payment_Mode__c, Status__c,
                   Transaction_Reference__c, Invoice__c, Invoice__r.Name
            FROM Payment__c
            WHERE Invoice__r.Patient__c = :patientId
            WITH SYSTEM_MODE
            ORDER BY Payment_Date__c DESC NULLS LAST, CreatedDate DESC
        ]) {
            payments.add(new Map<String, Object>{
                'numberValue' => payment.Name,
                'amount' => payment.Amount__c,
                'paymentDate' => payment.Payment_Date__c,
                'paymentMode' => payment.Payment_Mode__c,
                'status' => payment.Status__c,
                'transactionReference' => payment.Transaction_Reference__c,
                'invoiceNumber' => payment.Invoice__r != null ? payment.Invoice__r.Name : '',
                'invoiceSfId' => payment.Invoice__c
            });
        }
        summary.put('payments', payments);
        summary.put('paymentCount', payments.size());
    }

    private static void populateInsurance(Map<String, Object> summary, Id patientId) {
        List<Map<String, Object>> policies = new List<Map<String, Object>>();
        for (Insurance_Policy__c policy : [
            SELECT Name, Plan_Type__c, Coverage_Limit__c, Valid_From__c, Valid_To__c,
                   Verification_Status__c, Insurance_Company__r.Name
            FROM Insurance_Policy__c
            WHERE Patient__c = :patientId
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
        ]) {
            policies.add(new Map<String, Object>{
                'policyNumber' => policy.Name,
                'companyName' => policy.Insurance_Company__r != null
                    ? policy.Insurance_Company__r.Name : 'Insurance Provider',
                'planType' => policy.Plan_Type__c,
                'coverageLimit' => policy.Coverage_Limit__c,
                'validFrom' => policy.Valid_From__c,
                'validTo' => policy.Valid_To__c,
                'verificationStatus' => policy.Verification_Status__c
            });
        }
        summary.put('insurancePolicies', policies);
        summary.put('insuranceCount', policies.size());
    }

    public static List<Map<String, Object>> getPatientFaqs() {
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (FAQ__c faq : [
            SELECT Id, Name, Question__c, Answer__c, Category__c
            FROM FAQ__c
            WHERE Is_Active__c = true
            WITH SYSTEM_MODE
            ORDER BY Category__c ASC NULLS LAST, Name ASC
            LIMIT 200
        ]) {
            result.add(new Map<String, Object>{
                'id' => faq.Id,
                'question' => String.isNotBlank(faq.Question__c) ? faq.Question__c : faq.Name,
                'answer' => faq.Answer__c != null ? faq.Answer__c : '',
                'category' => faq.Category__c != null ? faq.Category__c : 'General'
            });
        }
        return result;
    }

    private static Integer calculateAge(Date dob) {
        if (dob == null) {
            return null;
        }
        Date today = Date.today();
        Integer years = today.year() - dob.year();
        if (dob.addYears(years) > today) {
            years--;
        }
        return years < 0 ? null : years;
    }
}