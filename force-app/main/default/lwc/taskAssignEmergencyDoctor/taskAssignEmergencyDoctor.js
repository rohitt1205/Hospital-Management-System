import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getAssignmentContext from '@salesforce/apex/EmergencyTaskDoctorAssignmentController.getAssignmentContext';
import assignDoctor from '@salesforce/apex/EmergencyTaskDoctorAssignmentController.assignDoctor';

export default class TaskAssignEmergencyDoctor extends NavigationMixin(LightningElement) {
    @api recordId;

    context;
    selectedDoctorId;
    loading = true;
    saving = false;
    errorMessage;

    connectedCallback() {
        this.loadContext();
    }

    async loadContext() {
        this.loading = true;
        this.errorMessage = undefined;
        try {
            this.context = await getAssignmentContext({ taskId: this.recordId });
        } catch (error) {
            this.errorMessage = this.normalizeError(error);
            this.context = undefined;
        } finally {
            this.loading = false;
        }
    }

    get showPanel() {
        return this.context?.isAdmissionTask && this.context?.isEmergencyAdmission;
    }

    get notApplicableMessage() {
        return this.errorMessage || this.context?.message || 'This action is only for emergency admission assignment tasks.';
    }

    get patientDisplay() {
        return this.context?.patientName || '-';
    }

    get phoneDisplay() {
        return this.context?.patientPhone || '-';
    }

    get departmentDisplay() {
        return this.context?.departmentName || '-';
    }

    get slaDisplay() {
        return this.context?.slaStatus || '-';
    }

    get doctorOptions() {
        return this.context?.doctors || [];
    }

    get hasAssignedDoctor() {
        return Boolean(this.context?.currentDoctorId);
    }

    get disableDoctorSelection() {
        return this.saving || this.doctorOptions.length === 0;
    }

    get assignDisabled() {
        return this.disableDoctorSelection || !this.selectedDoctorId;
    }

    handleDoctorChange(event) {
        this.selectedDoctorId = event.detail.value;
    }

    handleAddDoctor() {
        const defaultValues = this.context?.departmentId
            ? encodeDefaultFieldValues({
                  Department__c: this.context.departmentId
              })
            : undefined;

        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Doctor__c',
                actionName: 'new'
            },
            state: defaultValues
                ? {
                      defaultFieldValues: defaultValues
                  }
                : {}
        });
    }

    async handleAssign() {
        this.saving = true;
        try {
            const result = await assignDoctor({
                taskId: this.recordId,
                doctorId: this.selectedDoctorId
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Doctor assigned',
                    message: `${result.doctorName} assigned and task completed.`,
                    variant: 'success'
                })
            );
            await notifyRecordUpdateAvailable([
                { recordId: this.recordId },
                { recordId: result.admissionId }
            ]);
            await this.loadContext();
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Could not assign doctor',
                    message: this.normalizeError(error),
                    variant: 'error'
                })
            );
        } finally {
            this.saving = false;
        }
    }

    normalizeError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.body?.message || error?.message || 'Unexpected error';
    }
}