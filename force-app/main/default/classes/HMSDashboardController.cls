public with sharing class HMSDashboardController {

    // ─── KPI Stats ────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static Map<String, Integer> getDashboardStats() {
        Map<String, Integer> stats = new Map<String, Integer>();

        stats.put('totalPatients',     [SELECT COUNT() FROM Patient__c]);
        stats.put('availableBeds',     [SELECT COUNT() FROM Bed__c WHERE Status__c = 'Available']);
        stats.put('admissionsToday',   [
            SELECT COUNT() FROM Admission__c
            WHERE DAY_ONLY(Admission_Date_Time__c) = TODAY
        ]);
        stats.put('appointmentsToday', [
            SELECT COUNT() FROM Appointment__c
            WHERE DAY_ONLY(Appointment_Date_Time__c) = TODAY
        ]);

        return stats;
    }

    // ─── Today's Appointments ─────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<AppointmentWrapper> getTodayAppointments() {
        List<AppointmentWrapper> result = new List<AppointmentWrapper>();
        for (Appointment__c a : [
            SELECT Id, Name,
                   Patient__r.Name,
                   Doctor__r.Name,
                   Department__r.Name,
                   Appointment_Date_Time__c,
                   Status__c,
                   Priority__c
            FROM Appointment__c
            WHERE DAY_ONLY(Appointment_Date_Time__c) = TODAY
            ORDER BY Appointment_Date_Time__c ASC
            LIMIT 50
        ]) {
            result.add(new AppointmentWrapper(a));
        }
        return result;
    }

    public class AppointmentWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String patientName;
        @AuraEnabled public String doctorName;
        @AuraEnabled public String department;
        @AuraEnabled public DateTime appointmentDateTime;
        @AuraEnabled public String status;
        @AuraEnabled public String priority;

        public AppointmentWrapper(Appointment__c a) {
            this.id                  = a.Id;
            this.name                = a.Name;
            this.patientName         = a.Patient__r != null   ? a.Patient__r.Name   : '—';
            this.doctorName          = a.Doctor__r  != null   ? a.Doctor__r.Name    : '—';
            this.department          = a.Department__r != null ? a.Department__r.Name : '—';
            this.appointmentDateTime = a.Appointment_Date_Time__c;
            this.status              = a.Status__c;
            this.priority            = a.Priority__c;
        }
    }

    // ─── Recent Patients ──────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<PatientWrapper> getRecentPatients() {
        List<PatientWrapper> result = new List<PatientWrapper>();
        for (Patient__c p : [
            SELECT Id, Name, Status__c, Blood_Group__c, Phone__c, Gender__c, CreatedDate
            FROM Patient__c
            ORDER BY CreatedDate DESC
            LIMIT 10
        ]) {
            result.add(new PatientWrapper(p));
        }
        return result;
    }

    public class PatientWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String bloodGroup;
        @AuraEnabled public String phone;
        @AuraEnabled public String gender;

        public PatientWrapper(Patient__c p) {
            this.id         = p.Id;
            this.name       = p.Name;
            this.status     = p.Status__c;
            this.bloodGroup = p.Blood_Group__c;
            this.phone      = p.Phone__c;
            this.gender     = p.Gender__c;
        }
    }

    // ─── Bed Occupancy ────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<WardOccupancyWrapper> getBedOccupancy() {
        List<WardOccupancyWrapper> result = new List<WardOccupancyWrapper>();

        // Total beds per ward (from Bed__c via Room__c -> Ward__c)
        Map<Id, Integer> totalByWard    = new Map<Id, Integer>();
        Map<Id, Integer> occupiedByWard = new Map<Id, Integer>();

        for (AggregateResult ar : [
            SELECT Room__r.Ward__c wardId, COUNT(Id) total
            FROM Bed__c
            WHERE Room__r.Ward__c != null
            GROUP BY Room__r.Ward__c
        ]) {
            totalByWard.put((Id)ar.get('wardId'), (Integer)ar.get('total'));
        }

        for (AggregateResult ar : [
            SELECT Room__r.Ward__c wardId, COUNT(Id) occupied
            FROM Bed__c
            WHERE Status__c = 'Occupied' AND Room__r.Ward__c != null
            GROUP BY Room__r.Ward__c
        ]) {
            occupiedByWard.put((Id)ar.get('wardId'), (Integer)ar.get('occupied'));
        }

        for (Ward__c w : [
            SELECT Id, Name, Capacity__c
            FROM Ward__c
            ORDER BY Name ASC
        ]) {
            Integer total    = totalByWard.containsKey(w.Id)    ? totalByWard.get(w.Id)    : 0;
            Integer occupied = occupiedByWard.containsKey(w.Id) ? occupiedByWard.get(w.Id) : 0;
            result.add(new WardOccupancyWrapper(w, total, occupied));
        }
        return result;
    }

    public class WardOccupancyWrapper {
        @AuraEnabled public String  id;
        @AuraEnabled public String  wardName;
        @AuraEnabled public Integer totalBeds;
        @AuraEnabled public Integer occupiedBeds;
        @AuraEnabled public Integer availableBeds;
        @AuraEnabled public Decimal occupancyPercent;

        public WardOccupancyWrapper(Ward__c w, Integer total, Integer occupied) {
            this.id              = w.Id;
            this.wardName        = w.Name;
            this.totalBeds       = total;
            this.occupiedBeds    = occupied;
            this.availableBeds   = total - occupied;
            this.occupancyPercent = total > 0 ? ((Decimal)occupied / total * 100).setScale(0) : 0;
        }
    }

    // ─── Invoice Preview (for Generate Invoice flow) ──────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<InvoiceLineWrapper> getInvoiceLines(Id admissionId) {
        List<InvoiceLineWrapper> result = new List<InvoiceLineWrapper>();
        for (Invoice_Line_Item__c li : [
            SELECT Id, Name, Charge_Type__c, Quantity__c, Unit_Rate__c, Line_Amount__c,
                   Invoice__r.Net_Payable__c, Invoice__r.Payment_Status__c
            FROM Invoice_Line_Item__c
            WHERE Invoice__r.Admission__c = :admissionId
            ORDER BY CreatedDate ASC
        ]) {
            result.add(new InvoiceLineWrapper(li));
        }
        return result;
    }

    public class InvoiceLineWrapper {
        @AuraEnabled public String  id;
        @AuraEnabled public String  description;
        @AuraEnabled public String  chargeType;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal unitRate;
        @AuraEnabled public Decimal lineAmount;
        @AuraEnabled public Decimal invoiceTotal;
        @AuraEnabled public String  invoiceStatus;

        public InvoiceLineWrapper(Invoice_Line_Item__c li) {
            this.id            = li.Id;
            this.description   = li.Name;
            this.chargeType    = li.Charge_Type__c;
            this.quantity      = li.Quantity__c;
            this.unitRate      = li.Unit_Rate__c;
            this.lineAmount    = li.Line_Amount__c;
            this.invoiceTotal  = li.Invoice__r != null ? li.Invoice__r.Net_Payable__c   : 0;
            this.invoiceStatus = li.Invoice__r != null ? li.Invoice__r.Payment_Status__c : '';
        }
    }
}