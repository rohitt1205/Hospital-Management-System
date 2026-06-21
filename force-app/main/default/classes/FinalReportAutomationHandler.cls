public without sharing class FinalReportAutomationHandler {

    public static void handleAppointmentInsert(List<Appointment__c> newAppointments) {
        List<Final_Report__c> reportsToCreate = new List<Final_Report__c>();
        for (Appointment__c appt : newAppointments) {
            reportsToCreate.add(new Final_Report__c(
                Appointment__c = appt.Id,
                Patient__c = appt.Patient__c,
                Doctor__c = appt.Doctor__c,
                Status__c = 'Draft'
            ));
        }
        if (!reportsToCreate.isEmpty()) {
            Database.insert(reportsToCreate, AccessLevel.SYSTEM_MODE);
        }
    }

    public static void handleAdmissionInsert(List<Admission__c> newAdmissions) {
        Set<Id> apptIds = new Set<Id>();
        List<Admission__c> admissionsWithAppt = new List<Admission__c>();
        List<Admission__c> admissionsWithoutAppt = new List<Admission__c>();

        for (Admission__c adm : newAdmissions) {
            if (adm.Appointment__c != null) {
                apptIds.add(adm.Appointment__c);
                admissionsWithAppt.add(adm);
            } else {
                admissionsWithoutAppt.add(adm);
            }
        }

        List<Final_Report__c> finalReportsToUpdate = new List<Final_Report__c>();
        List<Final_Report__c> finalReportsToCreate = new List<Final_Report__c>();

        Set<Id> admissionIds = new Set<Id>();
        for (Admission__c adm : newAdmissions) {
            admissionIds.add(adm.Id);
        }
        Map<Id, Final_Report__c> existingByAdmission = new Map<Id, Final_Report__c>();
        if (!admissionIds.isEmpty()) {
            for (Final_Report__c fr : [
                SELECT Id, Appointment__c, Admission__c, Patient__c, Doctor__c
                FROM Final_Report__c
                WHERE Admission__c IN :admissionIds
                WITH SYSTEM_MODE
            ]) {
                existingByAdmission.put(fr.Admission__c, fr);
            }
        }

        Map<Id, Final_Report__c> apptToReportMap = new Map<Id, Final_Report__c>();
        if (!apptIds.isEmpty()) {
            for (Final_Report__c fr : [
                SELECT Id, Appointment__c, Admission__c, Patient__c, Doctor__c
                FROM Final_Report__c
                WHERE Appointment__c IN :apptIds
                WITH SYSTEM_MODE
            ]) {
                apptToReportMap.put(fr.Appointment__c, fr);
            }
        }

        for (Admission__c adm : admissionsWithAppt) {
            if (apptToReportMap.containsKey(adm.Appointment__c)) {
                Final_Report__c fr = apptToReportMap.get(adm.Appointment__c);
                fr.Admission__c = adm.Id;
                if (fr.Patient__c == null) {
                    fr.Patient__c = adm.Patient__c;
                }
                if (fr.Doctor__c == null) {
                    fr.Doctor__c = adm.Doctor__c;
                }
                finalReportsToUpdate.add(fr);
            } else {
                finalReportsToCreate.add(new Final_Report__c(
                    Appointment__c = adm.Appointment__c,
                    Admission__c = adm.Id,
                    Patient__c = adm.Patient__c,
                    Doctor__c = adm.Doctor__c,
                    Status__c = 'Draft'
                ));
            }
        }

        for (Admission__c adm : admissionsWithoutAppt) {
            if (existingByAdmission.containsKey(adm.Id)) {
                continue;
            }
            finalReportsToCreate.add(new Final_Report__c(
                Admission__c = adm.Id,
                Patient__c = adm.Patient__c,
                Doctor__c = adm.Doctor__c,
                Status__c = 'Draft'
            ));
        }

        if (!finalReportsToUpdate.isEmpty()) {
            Database.update(finalReportsToUpdate, AccessLevel.SYSTEM_MODE);
        }
        if (!finalReportsToCreate.isEmpty()) {
            Database.insert(finalReportsToCreate, AccessLevel.SYSTEM_MODE);
        }
    }

    public static void handleFinalReportBeforeSave(List<Final_Report__c> newReports) {
        Set<Id> admissionIds = new Set<Id>();
        Set<Id> appointmentIds = new Set<Id>();

        for (Final_Report__c fr : newReports) {
            if (fr.Admission__c != null
                && (fr.Patient__c == null || fr.Doctor__c == null || fr.Appointment__c == null)) {
                admissionIds.add(fr.Admission__c);
            } else if (fr.Appointment__c != null && (fr.Patient__c == null || fr.Doctor__c == null)) {
                appointmentIds.add(fr.Appointment__c);
            }
        }

        Map<Id, Admission__c> admissionMap = admissionIds.isEmpty()
            ? new Map<Id, Admission__c>()
            : new Map<Id, Admission__c>([
                SELECT Id, Patient__c, Doctor__c, Appointment__c
                FROM Admission__c
                WHERE Id IN :admissionIds
                WITH SYSTEM_MODE
            ]);

        Map<Id, Appointment__c> appointmentMap = appointmentIds.isEmpty()
            ? new Map<Id, Appointment__c>()
            : new Map<Id, Appointment__c>([
                SELECT Id, Patient__c, Doctor__c
                FROM Appointment__c
                WHERE Id IN :appointmentIds
                WITH SYSTEM_MODE
            ]);

        for (Final_Report__c fr : newReports) {
            if (fr.Admission__c != null) {
                Admission__c adm = admissionMap.get(fr.Admission__c);
                if (adm != null) {
                    if (fr.Patient__c == null) {
                        fr.Patient__c = adm.Patient__c;
                    }
                    if (fr.Doctor__c == null) {
                        fr.Doctor__c = adm.Doctor__c;
                    }
                    if (fr.Appointment__c == null) {
                        fr.Appointment__c = adm.Appointment__c;
                    }
                }
            } else if (fr.Appointment__c != null && (fr.Patient__c == null || fr.Doctor__c == null)) {
                Appointment__c appt = appointmentMap.get(fr.Appointment__c);
                if (appt != null) {
                    if (fr.Patient__c == null) {
                        fr.Patient__c = appt.Patient__c;
                    }
                    if (fr.Doctor__c == null) {
                        fr.Doctor__c = appt.Doctor__c;
                    }
                }
            }
        }
    }

    public static void validateUniqueAdmission(
        List<Final_Report__c> newReports,
        Map<Id, Final_Report__c> oldReports
    ) {
        Set<Id> admissionIds = new Set<Id>();
        Set<Id> currentReportIds = new Set<Id>();

        for (Final_Report__c report : newReports) {
            if (report.Id != null) {
                currentReportIds.add(report.Id);
            }
            if (report.Admission__c != null) {
                admissionIds.add(report.Admission__c);
            }
        }
        if (admissionIds.isEmpty()) {
            return;
        }

        List<Admission__c> lockedAdmissions = [
            SELECT Id
            FROM Admission__c
            WHERE Id IN :admissionIds
            FOR UPDATE
        ];

        Set<Id> admissionsWithExistingReport = new Set<Id>();
        for (Final_Report__c existingReport : [
            SELECT Id, Admission__c
            FROM Final_Report__c
            WHERE Admission__c IN :admissionIds
              AND Id NOT IN :currentReportIds
            WITH SYSTEM_MODE
        ]) {
            admissionsWithExistingReport.add(existingReport.Admission__c);
        }

        Map<Id, Final_Report__c> reportByAdmission = new Map<Id, Final_Report__c>();
        for (Final_Report__c report : newReports) {
            if (report.Admission__c == null) {
                continue;
            }

            if (admissionsWithExistingReport.contains(report.Admission__c)) {
                report.Admission__c.addError(
                    'A Final Report already exists for this Admission. Only one report is allowed per Admission.'
                );
                continue;
            }

            if (reportByAdmission.containsKey(report.Admission__c)) {
                String message = 'Only one Final Report can be created for the same Admission.';
                report.Admission__c.addError(message);
                reportByAdmission.get(report.Admission__c).Admission__c.addError(message);
            } else {
                reportByAdmission.put(report.Admission__c, report);
            }
        }
    }
}