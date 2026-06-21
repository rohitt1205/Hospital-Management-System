public with sharing class PayslipTriggerHandler {
    public static void validatePayslips(List<Payslip__c> payslips) {
        Set<Id> payrollIds = new Set<Id>();
        for (Payslip__c p : payslips) {
            if (p.Payroll__c != null) {
                payrollIds.add(p.Payroll__c);
            }
        }
        
        if (payrollIds.isEmpty()) return;
        
        Map<Id, Payroll__c> payrolls = new Map<Id, Payroll__c>([
            SELECT Id, Status__c FROM Payroll__c WHERE Id IN :payrollIds
        ]);
        
        for (Payslip__c p : payslips) {
            Payroll__c payroll = payrolls.get(p.Payroll__c);
            if (payroll != null && payroll.Status__c != 'Approved' && payroll.Status__c != 'Paid') {
                p.addError('Cannot create or update a payslip for a payroll that is not Approved or Paid.');
            }
        }
    }
}