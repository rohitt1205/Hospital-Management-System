Task taskRecord = [
    SELECT Id
    FROM Task
    WHERE WhatId IN (SELECT Id FROM Admission__c WHERE Name = 'ADM-00050')
    AND Subject LIKE 'Emergency admission pending doctor assignment%'
    ORDER BY CreatedDate DESC
    LIMIT 1
];
EmergencyTaskDoctorAssignmentController.AssignmentContext context =
    EmergencyTaskDoctorAssignmentController.getAssignmentContext(taskRecord.Id);
System.debug('Task Id: ' + context.taskId);
System.debug('Admission: ' + context.admissionName);
System.debug('Patient: ' + context.patientName);
System.debug('Phone: ' + context.patientPhone);
System.debug('Department: ' + context.departmentName);
System.debug('Doctor options: ' + context.doctors.size());
System.debug('Message: ' + context.message);
