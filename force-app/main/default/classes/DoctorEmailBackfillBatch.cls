/**
 * One-time batch to populate Doctor__c.Email__c on existing records with blank email.
 */
public without sharing class DoctorEmailBackfillBatch implements Database.Batchable<SObject> {

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator([
            SELECT Id, Email__c, Department__c, Specialization__c
            FROM Doctor__c
            WHERE Email__c = null
        ]);
    }

    public void execute(Database.BatchableContext context, List<Doctor__c> scope) {
        Set<Id> departmentIds = new Set<Id>();
        for (Doctor__c doctor : scope) {
            if (doctor.Department__c != null) {
                departmentIds.add(doctor.Department__c);
            }
        }

        Map<Id, Department__c> departmentsById = departmentIds.isEmpty()
            ? new Map<Id, Department__c>()
            : new Map<Id, Department__c>([
                SELECT Id, Is_Medical_Department__c
                FROM Department__c
                WHERE Id IN :departmentIds
            ]);

        for (Doctor__c doctor : scope) {
            DoctorEmailAssignmentService.assignRandomEmail(doctor);
            if (doctor.Department__c != null) {
                Department__c department = departmentsById.get(doctor.Department__c);
                if (department == null || department.Is_Medical_Department__c != true) {
                    doctor.Department__c = null;
                }
            }
        }

        Database.update(scope, false);
    }

    public void finish(Database.BatchableContext context) {
    }
}