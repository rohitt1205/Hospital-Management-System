public with sharing class InvoiceBillingService {
    public static void populateRoomDailyCharge(List<Room__c> rooms, Map<Id, Room__c> oldMap) {
        for (Room__c room : rooms) {
            if (room.Room_Type__c == null) continue;
            if (oldMap != null && oldMap.containsKey(room.Id) && oldMap.get(room.Id).Room_Type__c == room.Room_Type__c) continue;
            room.Daily_Charge__c = getRoomDailyCharge(room.Room_Type__c);
        }
    }

    private static Decimal getRoomDailyCharge(String roomType) {
        switch on roomType {
            when 'General' { return 1000; }
            when 'Semi Private' { return 2500; }
            when 'Private' { return 5000; }
            when 'Deluxe' { return 8000; }
            when 'ICU Room' { return 12000; }
            when else { return 0; }
        }
    }

    public static void handleAdmissionAfterInsert(List<Admission__c> admissions) {
        Map<Id, Invoice__c> invoiceMap = getOrCreateInvoicesForAdmissions(admissions);
        List<Invoice_Line_Item__c> lineItems = new List<Invoice_Line_Item__c>();

        for (Admission__c admission : admissions) {
            Invoice__c inv = invoiceMap.get(admission.Id);
            if (inv == null) continue;
            lineItems.add(createInvoiceLineItem(inv.Id,
                'Admission',
                'Admission Fee',
                1,
                admission.Admission_Fee__c != null ? admission.Admission_Fee__c : 500,
                String.valueOf(admission.Id)));
        }

        upsertInvoiceLineItems(lineItems);
        calculateInvoiceTotals(getInvoiceIdsFromMap(invoiceMap));
    }

    public static void createAdmissionCharges(Set<Id> admissionIds) {
        if (admissionIds == null || admissionIds.isEmpty()) return;
        List<Admission__c> admissions = [
            SELECT Id, Patient__c, Admission_Fee__c
            FROM Admission__c
            WHERE Id IN :admissionIds
        ];
        handleAdmissionAfterInsert(admissions);
    }

    public static void createDischargeCharges(Set<Id> admissionIds) {
        if (admissionIds == null || admissionIds.isEmpty()) return;
        List<Admission__c> admissions = [
            SELECT Id, Patient__c, Room__c, Admission_Date_Time__c, Actual_Discharge_Date_Time__c
            FROM Admission__c
            WHERE Id IN :admissionIds
        ];
        createDischargeCharges(admissions);
    }

    public static void handleAdmissionAfterUpdate(Map<Id, Admission__c> oldMap, Map<Id, Admission__c> newMap) {
        List<Admission__c> discharges = new List<Admission__c>();
        List<Admission__c> toUpdate = new List<Admission__c>();

        for (Id admissionId : newMap.keySet()) {
            Admission__c oldAdmission = oldMap.get(admissionId);
            Admission__c newAdmission = newMap.get(admissionId);
            if (oldAdmission == null || newAdmission == null) continue;
            if (oldAdmission.Status__c != 'Discharged' && newAdmission.Status__c == 'Discharged') {
                if (newAdmission.Actual_Discharge_Date_Time__c == null) {
                    newAdmission.Actual_Discharge_Date_Time__c = Datetime.now();
                    toUpdate.add(new Admission__c(Id = admissionId, Actual_Discharge_Date_Time__c = newAdmission.Actual_Discharge_Date_Time__c));
                }
                discharges.add(newAdmission);
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }

        if (!discharges.isEmpty()) {
            createDischargeCharges(discharges);
        }
    }

    public static void handleAppointmentAfterUpdate(Map<Id, Appointment__c> oldMap, Map<Id, Appointment__c> newMap) {
        List<Appointment__c> completedAppointments = new List<Appointment__c>();
        for (Id appointmentId : newMap.keySet()) {
            Appointment__c oldAppt = oldMap.get(appointmentId);
            Appointment__c newAppt = newMap.get(appointmentId);
            if (oldAppt == null || newAppt == null) continue;
            if (oldAppt.Status__c != 'Completed' && newAppt.Status__c == 'Completed') {
                completedAppointments.add(newAppt);
            }
        }
        if (!completedAppointments.isEmpty()) {
            createConsultationCharges(completedAppointments);
        }
    }

    public static void handleLabResultAfterInsert(List<Lab_Result__c> newLabResults) {
        List<Lab_Result__c> completedResults = new List<Lab_Result__c>();
        for (Lab_Result__c labResult : newLabResults) {
            if (labResult != null && labResult.Status__c == 'Completed') {
                completedResults.add(labResult);
            }
        }
        if (!completedResults.isEmpty()) {
            createLabTestCharges(completedResults);
        }
    }

    public static void handleLabResultAfterUpdate(Map<Id, Lab_Result__c> oldMap, Map<Id, Lab_Result__c> newMap) {
        List<Lab_Result__c> completedResults = new List<Lab_Result__c>();
        for (Id labResultId : newMap.keySet()) {
            Lab_Result__c oldResult = oldMap.get(labResultId);
            Lab_Result__c newResult = newMap.get(labResultId);
            if (oldResult == null || newResult == null) continue;
            if (oldResult.Status__c != 'Completed' && newResult.Status__c == 'Completed') {
                completedResults.add(newResult);
            }
        }
        if (!completedResults.isEmpty()) {
            createLabTestCharges(completedResults);
        }
    }

    /**
     * Called from LabResultTrigger before insert/update in org.
     * Stamps Patient__c from the linked admission when missing.
     */
    public static void populateLabResultPatient(List<Lab_Result__c> labResults) {
        if (labResults == null || labResults.isEmpty()) {
            return;
        }

        Set<Id> admissionIds = new Set<Id>();
        for (Lab_Result__c labResult : labResults) {
            if (labResult != null && labResult.Patient__c == null && labResult.Admission__c != null) {
                admissionIds.add(labResult.Admission__c);
            }
        }
        if (admissionIds.isEmpty()) {
            return;
        }

        Map<Id, Admission__c> admissionsById = new Map<Id, Admission__c>([
            SELECT Id, Patient__c
            FROM Admission__c
            WHERE Id IN :admissionIds
        ]);

        for (Lab_Result__c labResult : labResults) {
            if (labResult == null || labResult.Patient__c != null || labResult.Admission__c == null) {
                continue;
            }
            Admission__c admission = admissionsById.get(labResult.Admission__c);
            if (admission != null) {
                labResult.Patient__c = admission.Patient__c;
            }
        }
    }

    /**
     * Called from PrescriptionTrigger before insert/update in org.
     * Pricing is calculated from line items; this hook exists for trigger compatibility.
     */
    public static void populatePrescriptionPricing(List<Prescription__c> prescriptions) {
    }

    public static void handlePrescriptionsAfterInsert(List<Prescription__c> prescriptions) {
    }

    public static void handlePrescriptionsAfterUpdate(
        Map<Id, Prescription__c> oldMap,
        Map<Id, Prescription__c> newMap
    ) {
    }

    public static void handlePrescriptionLineItemsAfterInsert(List<Prescription_Line_Item__c> newLineItems) {
        createMedicineCharges(newLineItems);
    }

    public static void handlePrescriptionLineItemsAfterUpdate(Map<Id, Prescription_Line_Item__c> oldMap, Map<Id, Prescription_Line_Item__c> newMap) {
        List<Prescription_Line_Item__c> updatedLineItems = new List<Prescription_Line_Item__c>();
        for (Id lineItemId : newMap.keySet()) {
            Prescription_Line_Item__c oldLine = oldMap.get(lineItemId);
            Prescription_Line_Item__c newLine = newMap.get(lineItemId);
            if (oldLine == null || newLine == null) continue;
            if (oldLine.Quantity__c != newLine.Quantity__c || oldLine.Medicine__c != newLine.Medicine__c) {
                updatedLineItems.add(newLine);
            }
        }
        if (!updatedLineItems.isEmpty()) {
            createMedicineCharges(updatedLineItems);
        }
    }

    private static void createDischargeCharges(List<Admission__c> discharges) {
        Map<Id, Invoice__c> invoiceMap = getOrCreateInvoicesForAdmissions(discharges);
        Set<Id> admissionIds = new Set<Id>();
        Map<Id, Admission__c> admissionMap = new Map<Id, Admission__c>();
        for (Admission__c admission : discharges) {
            admissionIds.add(admission.Id);
            admissionMap.put(admission.Id, admission);
        }

        // Query all Bed Allocations for these admissions
        List<Bed_Allocation__c> allocations = [
            SELECT Id, Start_Date_Time__c, End_Date_Time__c, Daily_Rate__c, Status__c, Admission__c, Bed__c, Bed__r.Name
            FROM Bed_Allocation__c
            WHERE Admission__c IN :admissionIds
        ];

        List<Bed_Allocation__c> allocationsToUpdate = new List<Bed_Allocation__c>();
        List<Invoice_Line_Item__c> lineItems = new List<Invoice_Line_Item__c>();

        for (Bed_Allocation__c alloc : allocations) {
            Admission__c adm = admissionMap.get(alloc.Admission__c);
            if (adm == null) continue;
            Invoice__c inv = invoiceMap.get(alloc.Admission__c);
            if (inv == null) continue;

            Datetime startDt = alloc.Start_Date_Time__c != null ? alloc.Start_Date_Time__c : adm.Admission_Date_Time__c;
            Datetime endDt = alloc.End_Date_Time__c;

            // If not released, set status to Released and end date to discharge date
            Boolean needsUpdate = false;
            if (alloc.Status__c != 'Released') {
                alloc.Status__c = 'Released';
                endDt = adm.Actual_Discharge_Date_Time__c != null ? adm.Actual_Discharge_Date_Time__c : Datetime.now();
                alloc.End_Date_Time__c = endDt;
                needsUpdate = true;
            }

            if (startDt == null) {
                startDt = Datetime.now();
            }
            if (endDt == null) {
                endDt = Datetime.now();
            }

            Integer stayDays = BillingUtil.lengthOfStayDays(startDt, endDt);
            Decimal rate = alloc.Daily_Rate__c != null ? alloc.Daily_Rate__c : 0;
            String bedName = alloc.Bed__r != null ? alloc.Bed__r.Name : 'Bed';

            Invoice_Line_Item__c ili = createInvoiceLineItem(
                inv.Id,
                'Bed',
                'Bed Allocation - ' + bedName,
                stayDays,
                rate,
                String.valueOf(alloc.Id)
            );
            lineItems.add(ili);

            if (needsUpdate) {
                allocationsToUpdate.add(alloc);
            }
        }

        if (!allocationsToUpdate.isEmpty()) {
            update allocationsToUpdate;
        }

        upsertInvoiceLineItems(lineItems);
        calculateInvoiceTotals(getInvoiceIdsFromMap(invoiceMap));
    }

    private static void createConsultationCharges(List<Appointment__c> appointments) {
        Set<Id> doctorIds = new Set<Id>();
        Set<Id> patientIds = new Set<Id>();
        for (Appointment__c appointment : appointments) {
            if (appointment.Doctor__c != null) doctorIds.add(appointment.Doctor__c);
            if (appointment.Patient__c != null) patientIds.add(appointment.Patient__c);
        }
        Map<Id, Doctor__c> doctors = new Map<Id, Doctor__c>([SELECT Id, Name, Consultation_Fee__c FROM Doctor__c WHERE Id IN :doctorIds]);
        Map<Id, Invoice__c> invoiceMap = getOrCreateInvoicesForPatientAppointments(appointments);
        List<Invoice_Line_Item__c> lineItems = new List<Invoice_Line_Item__c>();

        for (Appointment__c appointment : appointments) {
            if (appointment.Patient__c == null || appointment.Doctor__c == null) continue;
            Invoice__c inv = invoiceMap.get(appointment.Id);
            if (inv == null) continue;
            Doctor__c doctor = doctors.get(appointment.Doctor__c);
            if (doctor == null || doctor.Consultation_Fee__c == null) continue;
            lineItems.add(createInvoiceLineItem(inv.Id,
                'Consultation',
                doctor.Name,
                1,
                doctor.Consultation_Fee__c,
                String.valueOf(appointment.Id)));
        }

        upsertInvoiceLineItems(lineItems);
        calculateInvoiceTotals(getInvoiceIdsFromMap(invoiceMap));
    }

    private static void createLabTestCharges(List<Lab_Result__c> labResults) {
        Set<Id> labTestIds = new Set<Id>();
        Set<Id> admissionIds = new Set<Id>();
        Set<Id> patientIds = new Set<Id>();
        for (Lab_Result__c labResult : labResults) {
            if (labResult.Lab_Test__c != null) labTestIds.add(labResult.Lab_Test__c);
            if (labResult.Admission__c != null) admissionIds.add(labResult.Admission__c);
            if (labResult.Patient__c != null) patientIds.add(labResult.Patient__c);
        }
        Map<Id, Lab_Test__c> labTests = new Map<Id, Lab_Test__c>([SELECT Id, Name, Standard_Rate__c FROM Lab_Test__c WHERE Id IN :labTestIds]);
        Map<Id, Invoice__c> invoiceMap = getOrCreateInvoicesForLabResults(labResults);
        List<Invoice_Line_Item__c> lineItems = new List<Invoice_Line_Item__c>();

        for (Lab_Result__c labResult : labResults) {
            Invoice__c inv = invoiceMap.get(labResult.Id);
            if (inv == null || labResult.Lab_Test__c == null) continue;
            Lab_Test__c labTest = labTests.get(labResult.Lab_Test__c);
            if (labTest == null || labTest.Standard_Rate__c == null) continue;
            lineItems.add(createInvoiceLineItem(inv.Id,
                'Lab',
                labTest.Name,
                1,
                labTest.Standard_Rate__c,
                String.valueOf(labResult.Id)));
        }

        upsertInvoiceLineItems(lineItems);
        calculateInvoiceTotals(getInvoiceIdsFromMap(invoiceMap));
    }

    private static void createMedicineCharges(List<Prescription_Line_Item__c> lineItemsToProcess) {
        Set<Id> medicineIds = new Set<Id>();
        Set<Id> prescriptionIds = new Set<Id>();
        for (Prescription_Line_Item__c lineItem : lineItemsToProcess) {
            if (lineItem.Medicine__c != null) medicineIds.add(lineItem.Medicine__c);
            if (lineItem.Prescription__c != null) prescriptionIds.add(lineItem.Prescription__c);
        }
        Map<Id, Medicine__c> medicines = new Map<Id, Medicine__c>([SELECT Id, Name, Unit_Price__c FROM Medicine__c WHERE Id IN :medicineIds]);
        Map<Id, Prescription__c> prescriptions = new Map<Id, Prescription__c>([
            SELECT Id, Patient__c, Total_Medicine_Bill__c 
            FROM Prescription__c 
            WHERE Id IN :prescriptionIds
        ]);
        Map<Id, Invoice__c> invoiceMap = getOrCreateInvoicesForPrescriptionLineItems(lineItemsToProcess, prescriptions);
        List<Invoice_Line_Item__c> invoiceItems = new List<Invoice_Line_Item__c>();
        List<Prescription_Line_Item__c> prescriptionUpdates = new List<Prescription_Line_Item__c>();

        for (Prescription_Line_Item__c lineItem : lineItemsToProcess) {
            Prescription__c prescription = prescriptions.get(lineItem.Prescription__c);
            if (prescription == null || prescription.Patient__c == null || lineItem.Medicine__c == null) continue;
            Invoice__c inv = invoiceMap.get(lineItem.Id);
            if (inv == null) continue;
            Medicine__c medicine = medicines.get(lineItem.Medicine__c);
            if (medicine == null) continue;

            Decimal quantity = lineItem.Quantity__c != null ? lineItem.Quantity__c : 1;
            Decimal rate = medicine.Unit_Price__c != null ? medicine.Unit_Price__c : 0;
            if (prescription.Total_Medicine_Bill__c != null && prescription.Total_Medicine_Bill__c > 0) {
                rate = prescription.Total_Medicine_Bill__c;
                quantity = 1;
            }

            Invoice_Line_Item__c ili = createInvoiceLineItem(inv.Id,
                'Medicine',
                medicine.Name,
                quantity,
                rate,
                String.valueOf(lineItem.Id));
            invoiceItems.add(ili);
        }

        if (!prescriptionUpdates.isEmpty()) {
            update prescriptionUpdates;
        }
        upsertInvoiceLineItems(invoiceItems);
        Set<Id> invoiceIds = new Set<Id>();
        for (Invoice__c invoice : invoiceMap.values()) {
            if (invoice != null && invoice.Id != null) invoiceIds.add(invoice.Id);
        }
        calculateInvoiceTotals(invoiceIds);
    }

    private static Decimal getLengthOfStayDays(Datetime admissionDate, Datetime dischargeDate) {
        if (admissionDate == null || dischargeDate == null) {
            return 0;
        }
        Decimal milliseconds = (dischargeDate.getTime() - admissionDate.getTime());
        Decimal days = milliseconds / 86400000;
        return days <= 0 ? 1 : days.setScale(2, RoundingMode.HALF_UP);
    }

    private static Invoice_Line_Item__c createInvoiceLineItem(Id invoiceId, String chargeType, String description, Decimal quantity, Decimal unitPrice, String sourceRecordId) {
        Decimal lineTotal = (quantity != null ? quantity : 0) * (unitPrice != null ? unitPrice : 0);
        Invoice_Line_Item__c lineItem = new Invoice_Line_Item__c(
            Invoice__c = invoiceId,
            Charge_Type__c = chargeType,
            Description__c = description,
            Service__c = description,
            Quantity__c = quantity,
            Unit_Price__c = unitPrice,
            Line_Total__c = lineTotal,
            Line_Amount__c = lineTotal,
            Unit_Rate__c = unitPrice,
            Source_Record_Id__c = sourceRecordId
        );
        return lineItem;
    }

    private static void upsertInvoiceLineItems(List<Invoice_Line_Item__c> requestedLineItems) {
        if (requestedLineItems.isEmpty()) {
            return;
        }

        Set<Id> invoiceIds = new Set<Id>();
        for (Invoice_Line_Item__c item : requestedLineItems) {
            if (item.Invoice__c != null) {
                invoiceIds.add(item.Invoice__c);
            }
        }

        Map<String, Invoice_Line_Item__c> existingLineItems = new Map<String, Invoice_Line_Item__c>();
        if (!invoiceIds.isEmpty()) {
            List<Invoice_Line_Item__c> queryResults = [SELECT Id, Invoice__c, Charge_Type__c, Source_Record_Id__c, Description__c, Quantity__c, Unit_Price__c, Line_Total__c, Line_Amount__c, Unit_Rate__c
                                                        FROM Invoice_Line_Item__c
                                                        WHERE Invoice__c IN :invoiceIds];
            for (Invoice_Line_Item__c existing : queryResults) {
                String key = getLineItemKey(existing.Invoice__c, existing.Charge_Type__c, existing.Source_Record_Id__c);
                existingLineItems.put(key, existing);
            }
        }

        List<Invoice_Line_Item__c> inserts = new List<Invoice_Line_Item__c>();
        List<Invoice_Line_Item__c> updates = new List<Invoice_Line_Item__c>();

        for (Invoice_Line_Item__c requested : requestedLineItems) {
            String key = getLineItemKey(requested.Invoice__c, requested.Charge_Type__c, requested.Source_Record_Id__c);
            if (existingLineItems.containsKey(key)) {
                Invoice_Line_Item__c existing = existingLineItems.get(key);
                updates.add(new Invoice_Line_Item__c(
                    Id = existing.Id,
                    Description__c = requested.Description__c,
                    Quantity__c = requested.Quantity__c,
                    Unit_Price__c = requested.Unit_Price__c,
                    Line_Total__c = requested.Line_Total__c,
                    Line_Amount__c = requested.Line_Total__c,
                    Unit_Rate__c = requested.Unit_Price__c
                ));
            } else {
                inserts.add(requested);
            }
        }

        if (!inserts.isEmpty()) {
            insert inserts;
        }
        if (!updates.isEmpty()) {
            update updates;
        }
    }

    private static Set<Id> getInvoiceIdsFromMap(Map<Id, Invoice__c> invoiceMap) {
        Set<Id> invoiceIds = new Set<Id>();
        for (Invoice__c invoice : invoiceMap.values()) {
            if (invoice != null && invoice.Id != null) {
                invoiceIds.add(invoice.Id);
            }
        }
        return invoiceIds;
    }

    private static String getLineItemKey(Id invoiceId, String chargeType, String sourceRecordId) {
        return String.valueOf(invoiceId) + '|' + String.valueOf(chargeType) + '|' + String.valueOf(sourceRecordId);
    }

    public static void calculateInvoiceTotals(Set<Id> invoiceIds) {
        if (invoiceIds.isEmpty()) {
            return;
        }

        Map<Id, Invoice__c> invoices = new Map<Id, Invoice__c>([SELECT Id, Discount_Amount__c, Insurance_Deduction__c, Non_Billable_Deduction__c, Gross_Amount__c, Net_Amount__c, Net_Payable__c, Insurance_Covered_Amount__c, Total_Amount__c
                                                                  FROM Invoice__c
                                                                  WHERE Id IN :invoiceIds]);

        Map<Id, Decimal> invoiceTotals = new Map<Id, Decimal>();
        Map<Id, Decimal> nonBillableTotals = new Map<Id, Decimal>();
        for (Invoice_Line_Item__c lineItem : [SELECT Invoice__c, Line_Total__c, Line_Amount__c, Non_Billable__c FROM Invoice_Line_Item__c WHERE Invoice__c IN :invoiceIds]) {
            Decimal amount = lineItem.Line_Total__c != null ? lineItem.Line_Total__c : lineItem.Line_Amount__c;
            if (amount == null) amount = 0;
            invoiceTotals.put(lineItem.Invoice__c, (invoiceTotals.containsKey(lineItem.Invoice__c) ? invoiceTotals.get(lineItem.Invoice__c) : 0) + amount);
            if (lineItem.Non_Billable__c == true) {
                nonBillableTotals.put(lineItem.Invoice__c, (nonBillableTotals.containsKey(lineItem.Invoice__c) ? nonBillableTotals.get(lineItem.Invoice__c) : 0) + amount);
            }
        }

        List<Invoice__c> updates = new List<Invoice__c>();
        for (Invoice__c invoice : invoices.values()) {
            Decimal gross = invoiceTotals.containsKey(invoice.Id) ? invoiceTotals.get(invoice.Id) : 0;
            Decimal insurance = invoice.Insurance_Covered_Amount__c != null ? invoice.Insurance_Covered_Amount__c : (invoice.Insurance_Deduction__c == null ? 0 : invoice.Insurance_Deduction__c);
            Decimal discount = invoice.Discount_Amount__c == null ? 0 : invoice.Discount_Amount__c;
            Decimal nonBillable = nonBillableTotals.containsKey(invoice.Id) ? nonBillableTotals.get(invoice.Id) : 0;
            Decimal net = gross - insurance - discount - nonBillable;
            if (net < 0) {
                net = 0;
            }
            invoice.Gross_Amount__c = gross;
            invoice.Non_Billable_Deduction__c = nonBillable;
            invoice.Net_Amount__c = net;
            invoice.Net_Payable__c = net;
            invoice.Total_Amount__c = net;
            updates.add(invoice);
        }

        if (!updates.isEmpty()) {
            update updates;
        }
    }

    private static Map<Id, Invoice__c> getOrCreateInvoicesForAdmissions(List<Admission__c> admissions) {
        Map<Id, Invoice__c> invoiceByAdmission = new Map<Id, Invoice__c>();
        Set<Id> admissionIds = new Set<Id>();
        for (Admission__c admission : admissions) {
            if (admission.Id != null) {
                admissionIds.add(admission.Id);
            }
        }

        Map<Id, Invoice__c> existingInvoices = new Map<Id, Invoice__c>();
        for (Invoice__c invoice : [SELECT Id, Admission__c FROM Invoice__c WHERE Admission__c IN :admissionIds]) {
            existingInvoices.put(invoice.Admission__c, invoice);
        }

        List<Invoice__c> invoicesToInsert = new List<Invoice__c>();
        for (Admission__c admission : admissions) {
            if (existingInvoices.containsKey(admission.Id)) {
                invoiceByAdmission.put(admission.Id, existingInvoices.get(admission.Id));
            } else if (admission.Patient__c != null) {
                Invoice__c invoice = new Invoice__c(
                    Admission__c = admission.Id,
                    Patient__c = admission.Patient__c,
                    Invoice_Date__c = Date.today()
                );
                invoicesToInsert.add(invoice);
                invoiceByAdmission.put(admission.Id, invoice);
            }
        }

        if (!invoicesToInsert.isEmpty()) {
            insert invoicesToInsert;
            for (Invoice__c invoice : invoicesToInsert) {
                invoiceByAdmission.put(invoice.Admission__c, invoice);
            }
        }
        return invoiceByAdmission;
    }

    private static Map<Id, Invoice__c> getOrCreateInvoicesForPatientAppointments(List<Appointment__c> appointments) {
        Map<Id, Invoice__c> invoiceByAppointment = new Map<Id, Invoice__c>();
        Set<Id> patientIds = new Set<Id>();
        for (Appointment__c appointment : appointments) {
            if (appointment.Patient__c != null) {
                patientIds.add(appointment.Patient__c);
            }
        }

        Map<Id, Invoice__c> invoiceByPatient = new Map<Id, Invoice__c>();
        for (Invoice__c invoice : [SELECT Id, Patient__c FROM Invoice__c WHERE Patient__c IN :patientIds AND Invoice_Date__c = :Date.today()]) {
            invoiceByPatient.put(invoice.Patient__c, invoice);
        }

        List<Invoice__c> invoicesToInsert = new List<Invoice__c>();
        for (Appointment__c appointment : appointments) {
            if (appointment.Patient__c == null) continue;
            if (!invoiceByPatient.containsKey(appointment.Patient__c)) {
                Invoice__c invoice = new Invoice__c(
                    Patient__c = appointment.Patient__c,
                    Invoice_Date__c = Date.today()
                );
                invoicesToInsert.add(invoice);
                invoiceByPatient.put(appointment.Patient__c, invoice);
            }
            invoiceByAppointment.put(appointment.Id, invoiceByPatient.get(appointment.Patient__c));
        }

        if (!invoicesToInsert.isEmpty()) {
            insert invoicesToInsert;
        }
        return invoiceByAppointment;
    }

    private static Map<Id, Invoice__c> getOrCreateInvoicesForLabResults(List<Lab_Result__c> labResults) {
        Map<Id, Invoice__c> invoiceByLabResult = new Map<Id, Invoice__c>();
        Set<Id> admissionIds = new Set<Id>();
        Set<Id> patientIds = new Set<Id>();
        for (Lab_Result__c labResult : labResults) {
            if (labResult.Admission__c != null) admissionIds.add(labResult.Admission__c);
            else if (labResult.Patient__c != null) patientIds.add(labResult.Patient__c);
        }

        Map<Id, Invoice__c> invoiceByAdmission = new Map<Id, Invoice__c>();
        if (!admissionIds.isEmpty()) {
            for (Invoice__c invoice : [SELECT Id, Admission__c FROM Invoice__c WHERE Admission__c IN :admissionIds]) {
                invoiceByAdmission.put(invoice.Admission__c, invoice);
            }
        }

        Map<Id, Invoice__c> invoiceByPatient = new Map<Id, Invoice__c>();
        if (!patientIds.isEmpty()) {
            for (Invoice__c invoice : [SELECT Id, Patient__c FROM Invoice__c WHERE Patient__c IN :patientIds AND Invoice_Date__c = :Date.today()]) {
                invoiceByPatient.put(invoice.Patient__c, invoice);
            }
        }

        List<Invoice__c> invoicesToInsert = new List<Invoice__c>();
        for (Lab_Result__c labResult : labResults) {
            if (labResult.Admission__c != null) {
                if (!invoiceByAdmission.containsKey(labResult.Admission__c)) {
                    Invoice__c invoice = new Invoice__c(
                        Admission__c = labResult.Admission__c,
                        Patient__c = labResult.Patient__c,
                        Invoice_Date__c = Date.today()
                    );
                    invoicesToInsert.add(invoice);
                    invoiceByAdmission.put(labResult.Admission__c, invoice);
                }
                invoiceByLabResult.put(labResult.Id, invoiceByAdmission.get(labResult.Admission__c));
            } else if (labResult.Patient__c != null) {
                if (!invoiceByPatient.containsKey(labResult.Patient__c)) {
                    Invoice__c invoice = new Invoice__c(
                        Patient__c = labResult.Patient__c,
                        Invoice_Date__c = Date.today()
                    );
                    invoicesToInsert.add(invoice);
                    invoiceByPatient.put(labResult.Patient__c, invoice);
                }
                invoiceByLabResult.put(labResult.Id, invoiceByPatient.get(labResult.Patient__c));
            }
        }

        if (!invoicesToInsert.isEmpty()) {
            insert invoicesToInsert;
        }
        return invoiceByLabResult;
    }

    private static Map<Id, Invoice__c> getOrCreateInvoicesForPrescriptionLineItems(List<Prescription_Line_Item__c> lineItems, Map<Id, Prescription__c> prescriptions) {
        Map<Id, Invoice__c> invoiceByLineItem = new Map<Id, Invoice__c>();
        Set<Id> patientIds = new Set<Id>();
        for (Prescription_Line_Item__c lineItem : lineItems) {
            Prescription__c prescription = prescriptions.get(lineItem.Prescription__c);
            if (prescription != null && prescription.Patient__c != null) {
                patientIds.add(prescription.Patient__c);
            }
        }

        Map<Id, Invoice__c> invoiceByPatient = new Map<Id, Invoice__c>();
        if (!patientIds.isEmpty()) {
            for (Invoice__c invoice : [SELECT Id, Patient__c FROM Invoice__c WHERE Patient__c IN :patientIds AND Invoice_Date__c = :Date.today()]) {
                invoiceByPatient.put(invoice.Patient__c, invoice);
            }
        }

        List<Invoice__c> invoicesToInsert = new List<Invoice__c>();
        for (Prescription_Line_Item__c lineItem : lineItems) {
            Prescription__c prescription = prescriptions.get(lineItem.Prescription__c);
            if (prescription == null || prescription.Patient__c == null) continue;
            if (!invoiceByPatient.containsKey(prescription.Patient__c)) {
                Invoice__c invoice = new Invoice__c(
                    Patient__c = prescription.Patient__c,
                    Invoice_Date__c = Date.today()
                );
                invoicesToInsert.add(invoice);
                invoiceByPatient.put(prescription.Patient__c, invoice);
            }
            invoiceByLineItem.put(lineItem.Id, invoiceByPatient.get(prescription.Patient__c));
        }

        if (!invoicesToInsert.isEmpty()) {
            insert invoicesToInsert;
        }
        return invoiceByLineItem;
    }

    public static void handlePatientServicesAfterInsert(List<Patient_Service__c> newServices) {
        createPatientServiceCharges(newServices);
    }

    public static void handlePatientServicesAfterUpdate(Map<Id, Patient_Service__c> oldMap, Map<Id, Patient_Service__c> newMap) {
        List<Patient_Service__c> updatedServices = new List<Patient_Service__c>();
        for (Id serviceId : newMap.keySet()) {
            Patient_Service__c oldService = oldMap.get(serviceId);
            Patient_Service__c newService = newMap.get(serviceId);
            if (oldService == null || newService == null) continue;
            if (oldService.Clinical_Service__c != newService.Clinical_Service__c || oldService.Patient__c != newService.Patient__c) {
                updatedServices.add(newService);
            }
        }
        if (!updatedServices.isEmpty()) {
            createPatientServiceCharges(updatedServices);
        }
    }

    private static void createPatientServiceCharges(List<Patient_Service__c> services) {
        Set<Id> clinicalServiceIds = new Set<Id>();
        for (Patient_Service__c ps : services) {
            if (ps.Clinical_Service__c != null) {
                clinicalServiceIds.add(ps.Clinical_Service__c);
            }
        }
        
        Map<Id, Clinical_Service__c> clinicalServices = new Map<Id, Clinical_Service__c>([
            SELECT Id, Name, Standard_Rate__c, Non_Billable__c
            FROM Clinical_Service__c 
            WHERE Id IN :clinicalServiceIds
        ]);
        
        Map<Id, Invoice__c> invoiceMap = getOrCreateInvoicesForPatientServices(services);
        List<Invoice_Line_Item__c> lineItems = new List<Invoice_Line_Item__c>();

        for (Patient_Service__c ps : services) {
            Invoice__c inv = invoiceMap.get(ps.Id);
            if (inv == null || ps.Clinical_Service__c == null) continue;
            
            Clinical_Service__c cs = clinicalServices.get(ps.Clinical_Service__c);
            if (cs == null || cs.Standard_Rate__c == null) continue;
            
            Invoice_Line_Item__c ili = createInvoiceLineItem(inv.Id,
                'Service',
                cs.Name,
                1,
                cs.Standard_Rate__c,
                String.valueOf(ps.Id));
            ili.Non_Billable__c = cs.Non_Billable__c == true;
            lineItems.add(ili);
        }

        upsertInvoiceLineItems(lineItems);
        calculateInvoiceTotals(getInvoiceIdsFromMap(invoiceMap));
    }

    private static Map<Id, Invoice__c> getOrCreateInvoicesForPatientServices(List<Patient_Service__c> services) {
        Map<Id, Invoice__c> invoiceByService = new Map<Id, Invoice__c>();
        Set<Id> admissionIds = new Set<Id>();
        Set<Id> patientIds = new Set<Id>();
        for (Patient_Service__c ps : services) {
            if (ps.Admission__c != null) admissionIds.add(ps.Admission__c);
            else if (ps.Patient__c != null) patientIds.add(ps.Patient__c);
        }

        Map<Id, Invoice__c> invoiceByAdmission = new Map<Id, Invoice__c>();
        if (!admissionIds.isEmpty()) {
            for (Invoice__c invoice : [SELECT Id, Admission__c FROM Invoice__c WHERE Admission__c IN :admissionIds]) {
                invoiceByAdmission.put(invoice.Admission__c, invoice);
            }
        }

        Map<Id, Invoice__c> invoiceByPatient = new Map<Id, Invoice__c>();
        if (!patientIds.isEmpty()) {
            for (Invoice__c invoice : [SELECT Id, Patient__c FROM Invoice__c WHERE Patient__c IN :patientIds AND Invoice_Date__c = :Date.today()]) {
                invoiceByPatient.put(invoice.Patient__c, invoice);
            }
        }

        List<Invoice__c> invoicesToInsert = new List<Invoice__c>();
        for (Patient_Service__c ps : services) {
            if (ps.Admission__c != null) {
                if (!invoiceByAdmission.containsKey(ps.Admission__c)) {
                    Invoice__c invoice = new Invoice__c(
                        Admission__c = ps.Admission__c,
                        Patient__c = ps.Patient__c,
                        Invoice_Date__c = Date.today()
                    );
                    invoicesToInsert.add(invoice);
                    invoiceByAdmission.put(ps.Admission__c, invoice);
                }
                invoiceByService.put(ps.Id, invoiceByAdmission.get(ps.Admission__c));
            } else if (ps.Patient__c != null) {
                if (!invoiceByPatient.containsKey(ps.Patient__c)) {
                    Invoice__c invoice = new Invoice__c(
                        Patient__c = ps.Patient__c,
                        Invoice_Date__c = Date.today()
                    );
                    invoicesToInsert.add(invoice);
                    invoiceByPatient.put(ps.Patient__c, invoice);
                }
                invoiceByService.put(ps.Id, invoiceByPatient.get(ps.Patient__c));
            }
        }

        if (!invoicesToInsert.isEmpty()) {
            insert invoicesToInsert;
            for (Invoice__c invoice : invoicesToInsert) {
                if (invoice.Admission__c != null) {
                    invoiceByAdmission.put(invoice.Admission__c, invoice);
                }
                invoiceByPatient.put(invoice.Patient__c, invoice);
            }
        }
        
        // Final mapping pass to ensure all services reference correct inserted invoices
        for (Patient_Service__c ps : services) {
            if (ps.Admission__c != null) {
                invoiceByService.put(ps.Id, invoiceByAdmission.get(ps.Admission__c));
            } else if (ps.Patient__c != null) {
                invoiceByService.put(ps.Id, invoiceByPatient.get(ps.Patient__c));
            }
        }
        
        return invoiceByService;
    }
}