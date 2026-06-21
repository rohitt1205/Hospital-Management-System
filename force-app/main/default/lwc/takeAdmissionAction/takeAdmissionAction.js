import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { CloseActionScreenEvent } from 'lightning/actions';
import createAdmission from '@salesforce/apex/TakeAdmissionController.createAdmission';

export default class TakeAdmissionAction extends NavigationMixin(LightningElement) {
    @api recordId;
    isWorking = false;

    @api
    async invoke() {
        if (this.isWorking) {
            return;
        }
        this.isWorking = true;
        try {
            const admissionId = await createAdmission({ appointmentId: this.recordId });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Admission draft ready',
                message: 'Complete the remaining admission details and save.',
                variant: 'success'
            }));
            this.dispatchEvent(new CloseActionScreenEvent());
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: admissionId,
                    objectApiName: 'Admission__c',
                    actionName: 'edit'
                }
            });
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Admission could not be created',
                message: error.body && error.body.message ? error.body.message : 'Please check the appointment details.',
                variant: 'error'
            }));
        } finally {
            this.isWorking = false;
        }
    }
}