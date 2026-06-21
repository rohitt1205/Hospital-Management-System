/**
 * Loads clinical + billing data for the Final Report PDF.
 */
public without sharing class FinalReportPdfService {

    public class LabPdfRow {
        public String testName { get; set; }
        public String resultSummary { get; set; }
        public String status { get; set; }
    }

    public class MedicinePdfRow {
        public String medicineName { get; set; }
        public String dosage { get; set; }
        public String frequency { get; set; }
        public String duration { get; set; }
        public String quantity { get; set; }
        public String instructions { get; set; }
    }

    public class BillingPdfRow {
        public String chargeType { get; set; }
        public String description { get; set; }
        public Decimal unitPrice { get; set; }
        public Decimal quantity { get; set; }
        public Decimal lineTotal { get; set; }
    }

    public class PdfContext {
        public Final_Report__c report { get; set; }
        public Appointment__c appointment { get; set; }
        public List<LabPdfRow> labs { get; set; }
        public List<MedicinePdfRow> medicines { get; set; }
        public List<BillingPdfRow> billingLines { get; set; }
        public Invoice__c invoice { get; set; }
        public Boolean stillAdmitted { get; set; }
        public String dischargeDateText { get; set; }
        public String roomBedText { get; set; }
        public String appointmentDateText { get; set; }
        public String appointmentTimeText { get; set; }
        public String reportDateText { get; set; }
        public String signatureDoctorName { get; set; }
    }

    public static PdfContext buildContext(Final_Report__c report) {
        PdfContext ctx = new PdfContext();
        ctx.report = report;
        ctx.labs = new List<LabPdfRow>();
        ctx.medicines = new List<MedicinePdfRow>();
        ctx.billingLines = new List<BillingPdfRow>();

        Id patientId = report.Patient__c;
        Id admissionId = report.Admission__c;
        Id appointmentId = report.Appointment__c != null
            ? report.Appointment__c
            : (report.Admission__r != null ? report.Admission__r.Appointment__c : null);

        if (appointmentId != null) {
            ctx.appointment = queryAppointment(appointmentId);
        }

        ctx.labs = loadLabRows(patientId, admissionId);
        ctx.medicines = loadMedicineRows(patientId);
        ctx.invoice = loadInvoice(patientId, admissionId);
        if (ctx.invoice != null) {
            ctx.billingLines = loadBillingRows(ctx.invoice.Id);
        }

        ctx.stillAdmitted = computeStillAdmitted(report);
        ctx.dischargeDateText = formatDischargeDate(report, ctx.stillAdmitted);
        ctx.roomBedText = formatRoomBed(report);
        ctx.appointmentDateText = formatAppointmentDate(ctx.appointment, report);
        ctx.appointmentTimeText = formatAppointmentTime(ctx.appointment, report);
        ctx.reportDateText = formatDateTime(report.CreatedDate);
        ctx.signatureDoctorName = resolveDoctorName(report, ctx.appointment);
        return ctx;
    }

    public static Final_Report__c queryReport(Id reportId) {
        List<Final_Report__c> reports = [
            SELECT Id, Name, Status__c, Summary__c, Discharge_Advice__c, CreatedDate,
                   Patient__c,
                   Patient__r.Name, Patient__r.Patient_ID__c, Patient__r.Gender__c,
                   Patient__r.Blood_Group__c, Patient__r.Phone__c, Patient__r.Email__c,
                   Patient__r.Address__c,
                   Doctor__c, Doctor__r.Name,
                   Appointment__c,
                   Admission__c,
                   Admission__r.Name, Admission__r.Admission_Date_Time__c,
                   Admission__r.Actual_Discharge_Date_Time__c, Admission__r.Discharge_Date__c,
                   Admission__r.Status__c, Admission__r.Diagnosis__c,
                   Admission__r.Doctor__r.Name, Admission__r.Room__r.Name, Admission__r.Bed__r.Name,
                   Admission__r.Appointment__c
            FROM Final_Report__c
            WHERE Id = :reportId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return reports.isEmpty() ? null : reports[0];
    }

    private static Appointment__c queryAppointment(Id appointmentId) {
        List<Appointment__c> appointments = [
            SELECT Id, Name, Appointment_Date__c, Appointment_Time__c, Appointment_Date_Time__c,
                   Symptoms__c, Doctor__r.Name
            FROM Appointment__c
            WHERE Id = :appointmentId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return appointments.isEmpty() ? null : appointments[0];
    }

    private static List<LabPdfRow> loadLabRows(Id patientId, Id admissionId) {
        List<LabPdfRow> rows = new List<LabPdfRow>();
        List<Lab_Result__c> results;
        if (admissionId != null) {
            results = [
                SELECT Status__c, Result_Summary__c, Lab_Test__r.Name
                FROM Lab_Result__c
                WHERE Patient__c = :patientId AND Admission__c = :admissionId
                WITH SYSTEM_MODE
                ORDER BY CreatedDate
            ];
        } else {
            results = [
                SELECT Status__c, Result_Summary__c, Lab_Test__r.Name
                FROM Lab_Result__c
                WHERE Patient__c = :patientId
                WITH SYSTEM_MODE
                ORDER BY CreatedDate DESC
                LIMIT 20
            ];
        }

        for (Lab_Result__c result : results) {
            LabPdfRow row = new LabPdfRow();
            row.testName = result.Lab_Test__r != null ? result.Lab_Test__r.Name : 'Lab Test';
            row.resultSummary = String.isBlank(result.Result_Summary__c) ? '—' : result.Result_Summary__c;
            row.status = String.isBlank(result.Status__c) ? 'Pending' : result.Status__c;
            rows.add(row);
        }
        return rows;
    }

    private static List<MedicinePdfRow> loadMedicineRows(Id patientId) {
        List<MedicinePdfRow> rows = new List<MedicinePdfRow>();
        for (Prescription_Line_Item__c line : [
            SELECT Dosage__c, Frequency__c, Duration_Days__c, Quantity__c,
                   Morning__c, Afternoon__c, Night__c, Consumption__c,
                   Medicine__r.Name,
                   Prescription__r.Instructions__c
            FROM Prescription_Line_Item__c
            WHERE Prescription__r.Patient__c = :patientId
            WITH SYSTEM_MODE
            ORDER BY Prescription__r.Prescription_Date__c DESC, CreatedDate
            LIMIT 50
        ]) {
            MedicinePdfRow row = new MedicinePdfRow();
            row.medicineName = line.Medicine__r != null ? line.Medicine__r.Name : 'Medicine';
            row.dosage = String.isBlank(line.Dosage__c) ? 'As prescribed' : line.Dosage__c;
            row.frequency = String.isBlank(line.Frequency__c) ? 'As prescribed' : line.Frequency__c;
            row.duration = line.Duration_Days__c != null
                ? String.valueOf(line.Duration_Days__c.intValue()) + ' days'
                : 'N/A';
            row.quantity = line.Quantity__c != null ? String.valueOf(line.Quantity__c.intValue()) : '—';
            row.instructions = buildMedicineInstructions(line);
            rows.add(row);
        }
        return rows;
    }

    private static String buildMedicineInstructions(Prescription_Line_Item__c line) {
        List<String> parts = new List<String>();
        if (line.Morning__c == true) {
            parts.add('Morning');
        }
        if (line.Afternoon__c == true) {
            parts.add('Afternoon');
        }
        if (line.Night__c == true) {
            parts.add('Night');
        }
        if (String.isNotBlank(line.Consumption__c)) {
            parts.add(line.Consumption__c);
        }
        if (!parts.isEmpty()) {
            return String.join(parts, ', ');
        }
        if (line.Prescription__r != null && String.isNotBlank(line.Prescription__r.Instructions__c)) {
            return line.Prescription__r.Instructions__c;
        }
        return 'N/A';
    }

    private static Invoice__c loadInvoice(Id patientId, Id admissionId) {
        List<Invoice__c> invoices;
        if (admissionId != null) {
            invoices = [
                SELECT Id, Name, Gross_Amount__c, Insurance_Covered_Amount__c, Discount_Amount__c,
                       Non_Billable_Deduction__c, Net_Payable__c, Payment_Status__c, Total_Amount__c
                FROM Invoice__c
                WHERE Admission__c = :admissionId
                WITH SYSTEM_MODE
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
        }
        if (invoices == null || invoices.isEmpty()) {
            invoices = [
                SELECT Id, Name, Gross_Amount__c, Insurance_Covered_Amount__c, Discount_Amount__c,
                       Non_Billable_Deduction__c, Net_Payable__c, Payment_Status__c, Total_Amount__c
                FROM Invoice__c
                WHERE Patient__c = :patientId
                WITH SYSTEM_MODE
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
        }
        return invoices.isEmpty() ? null : invoices[0];
    }

    private static List<BillingPdfRow> loadBillingRows(Id invoiceId) {
        List<BillingPdfRow> rows = new List<BillingPdfRow>();
        for (Invoice_Line_Item__c item : [
            SELECT Charge_Type__c, Description__c, Unit_Price__c, Quantity__c,
                   Line_Total__c, Line_Amount__c
            FROM Invoice_Line_Item__c
            WHERE Invoice__c = :invoiceId
            WITH SYSTEM_MODE
            ORDER BY Charge_Type__c, Description__c
        ]) {
            BillingPdfRow row = new BillingPdfRow();
            row.chargeType = String.isBlank(item.Charge_Type__c) ? 'Service' : item.Charge_Type__c;
            row.description = String.isBlank(item.Description__c) ? item.Charge_Type__c : item.Description__c;
            row.unitPrice = item.Unit_Price__c != null ? item.Unit_Price__c : 0;
            row.quantity = item.Quantity__c != null ? item.Quantity__c : 0;
            row.lineTotal = item.Line_Total__c != null
                ? item.Line_Total__c
                : (item.Line_Amount__c != null ? item.Line_Amount__c : 0);
            rows.add(row);
        }
        return rows;
    }

    private static Boolean computeStillAdmitted(Final_Report__c report) {
        if (report.Admission__r == null) {
            return false;
        }
        if (report.Admission__r.Actual_Discharge_Date_Time__c != null) {
            return false;
        }
        if (report.Admission__r.Discharge_Date__c != null) {
            return false;
        }
        String status = report.Admission__r.Status__c;
        return status == 'Admitted' || status == 'Pending Discharge' || status == 'Draft';
    }

    private static String formatDischargeDate(Final_Report__c report, Boolean stillAdmitted) {
        if (stillAdmitted) {
            return 'Still Admitted';
        }
        if (report.Admission__r != null && report.Admission__r.Actual_Discharge_Date_Time__c != null) {
            return formatDateTime(report.Admission__r.Actual_Discharge_Date_Time__c);
        }
        if (report.Admission__r != null && report.Admission__r.Discharge_Date__c != null) {
            return formatDateTime(report.Admission__r.Discharge_Date__c);
        }
        return '—';
    }

    private static String formatRoomBed(Final_Report__c report) {
        if (report.Admission__r == null) {
            return '—';
        }
        String room = report.Admission__r.Room__r != null ? report.Admission__r.Room__r.Name : 'N/A';
        String bed = report.Admission__r.Bed__r != null ? report.Admission__r.Bed__r.Name : 'N/A';
        return room + ' / ' + bed;
    }

    private static String formatAppointmentDate(Appointment__c appointment, Final_Report__c report) {
        if (appointment != null && appointment.Appointment_Date__c != null) {
            return formatDate(appointment.Appointment_Date__c);
        }
        if (appointment != null && appointment.Appointment_Date_Time__c != null) {
            return formatDate(appointment.Appointment_Date_Time__c.date());
        }
        if (report.Admission__r != null && report.Admission__r.Admission_Date_Time__c != null) {
            return formatDate(report.Admission__r.Admission_Date_Time__c.date());
        }
        return '—';
    }

    private static String formatAppointmentTime(Appointment__c appointment, Final_Report__c report) {
        if (appointment != null && String.isNotBlank(appointment.Appointment_Time__c)) {
            return appointment.Appointment_Time__c;
        }
        if (appointment != null && appointment.Appointment_Date_Time__c != null) {
            return appointment.Appointment_Date_Time__c.format('HH:mm');
        }
        return '—';
    }

    private static String resolveDoctorName(Final_Report__c report, Appointment__c appointment) {
        if (report.Doctor__r != null && String.isNotBlank(report.Doctor__r.Name)) {
            return report.Doctor__r.Name;
        }
        if (report.Admission__r != null && report.Admission__r.Doctor__r != null
            && String.isNotBlank(report.Admission__r.Doctor__r.Name)) {
            return report.Admission__r.Doctor__r.Name;
        }
        if (appointment != null && appointment.Doctor__r != null
            && String.isNotBlank(appointment.Doctor__r.Name)) {
            return appointment.Doctor__r.Name;
        }
        return 'Authorized Physician';
    }

    private static String formatDate(Date value) {
        if (value == null) {
            return '—';
        }
        Datetime dt = Datetime.newInstance(value.year(), value.month(), value.day());
        return dt.format('dd MMM yyyy');
    }

    private static String formatDateTime(Datetime value) {
        if (value == null) {
            return '—';
        }
        return value.format('dd MMM yyyy, hh:mm a');
    }
}