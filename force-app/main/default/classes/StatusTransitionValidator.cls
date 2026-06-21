public with sharing class StatusTransitionValidator {
    
    // Defines the strict linear status sequence for validated fields.
    // Structure: ObjectApiName.FieldApiName -> List of status values in order.
    private static final Map<String, List<String>> FIELD_TRANSITIONS = new Map<String, List<String>>{
        'Admission__c.Approval_Status__c' => new List<String>{'Not Required', 'Pending Approval', 'Approved', 'Rejected'},
        'Admission__c.Emergency_SLA_Status__c' => new List<String>{'On Time', 'At Risk', 'Breached', 'Escalated'},
        'Admission__c.Status__c' => new List<String>{'Draft', 'Admitted', 'Pending Discharge', 'Discharged', 'Cancelled'},
        'Appointment__c.Status__c' => new List<String>{'Requested', 'Confirmed', 'Completed', 'Cancelled', 'No Show', 'Rejected'},
        'Bed_Allocation__c.Allocation_Status__c' => new List<String>{'Pending', 'Approved', 'Rejected'},
        'Bed_Allocation__c.Status__c' => new List<String>{'Reserved', 'Occupied', 'Released', 'Cancelled'},
        'Discharge__c.Status__c' => new List<String>{'Pending Approval', 'Approved', 'Blocked - Unpaid Bill', 'Completed'},
        'Donation__c.Status__c' => new List<String>{'Pledged', 'Received', 'Cancelled'},
        'Final_Report__c.Status__c' => new List<String>{'Draft', 'Final', 'Shared With Patient'},
        'Helpdesk_Ticket__c.Status__c' => new List<String>{'New', 'In Progress', 'Resolved', 'Closed'},
        'Insurance_Policy__c.Verification_Status__c' => new List<String>{'Pending', 'Verified', 'Rejected', 'Expired'},
        'Invoice__c.Payment_Status__c' => new List<String>{'Draft', 'Unpaid', 'Partially Paid', 'Paid', 'Cancelled'},
        'Invoice__c.Status__c' => new List<String>{'Draft', 'Unpaid', 'Partially Paid', 'Paid', 'Cancelled'},
        'Lab_Result__c.Status__c' => new List<String>{'Ordered', 'Sample Collected', 'Completed', 'Cancelled'},
        'Medical_Record__c.Record_Status__c' => new List<String>{'Draft', 'Pending Approval', 'Final', 'Archived'},
        'Notification_Log__c.Status__c' => new List<String>{'Queued', 'Sent', 'Failed'},
        'Patient__c.Patient_Approval_Status__c' => new List<String>{'Draft', 'Pending Approval', 'Approved', 'Rejected'},
        'Payment__c.Status__c' => new List<String>{'Unpaid', 'Received', 'Failed', 'Refunded'},
        'Payroll__c.Status__c' => new List<String>{'Draft', 'Approved', 'Paid'},
        'Payslip__c.Status__c' => new List<String>{'Generated', 'Shared', 'Cancelled'},
        'Prescription__c.Status__c' => new List<String>{'Draft', 'Issued', 'Dispensed', 'Cancelled'}
    };

    /**
     * Validates that the status field on the target records is not being changed back to a lower status in the sequence.
     * Call this in the before update trigger.
     */
    public static void validateTransitions(List<SObject> newRecords, Map<Id, SObject> oldMap, String objectName, String fieldName) {
        String key = objectName + '.' + fieldName;
        if (!FIELD_TRANSITIONS.containsKey(key)) {
            return; // No validation defined for this field
        }

        List<String> orderedStatuses = FIELD_TRANSITIONS.get(key);
        // Create a map of status value to its index for fast lookup
        Map<String, Integer> statusIndexMap = new Map<String, Integer>();
        for (Integer i = 0; i < orderedStatuses.size(); i++) {
            statusIndexMap.put(orderedStatuses[i], i);
        }

        for (SObject newRecord : newRecords) {
            SObject oldRecord = oldMap.get(newRecord.Id);
            String oldVal = (String)oldRecord.get(fieldName);
            String newVal = (String)newRecord.get(fieldName);

            // If value didn't change, or either value is blank, no validation needed
            if (oldVal == newVal || String.isBlank(oldVal) || String.isBlank(newVal)) {
                continue;
            }

            Integer oldIndex = statusIndexMap.containsKey(oldVal) ? statusIndexMap.get(oldVal) : -1;
            Integer newIndex = statusIndexMap.containsKey(newVal) ? statusIndexMap.get(newVal) : -1;

            // If both statuses are valid elements in the hierarchy, check order
            if (oldIndex != -1 && newIndex != -1) {
                if (newIndex < oldIndex) {
                    newRecord.addError(fieldName, 'Status cannot be reverted from "' + oldVal + '" back to "' + newVal + '". The allowed sequence is: ' + String.join(orderedStatuses, ' -> '));
                }
            }
        }
    }
}