import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const FLOW_LABELS = {
    HMS_New_Appointment : 'New Appointment',
    HMS_New_Admission   : 'New Admission',
    HMS_Bed_Allocation  : 'Bed Allocation',
    HMS_Generate_Invoice: 'View Invoice'
};

export default class HmsQuickActions extends LightningElement {
    @track isFlowOpen     = false;
    @track activeFlowName = '';

    get activeFlowLabel() {
        return FLOW_LABELS[this.activeFlowName] || '';
    }

    _openFlow(flowName) {
        this.activeFlowName = flowName;
        this.isFlowOpen     = true;
    }

    launchAppointmentFlow() { this._openFlow('HMS_New_Appointment'); }
    launchAdmissionFlow()   { this._openFlow('HMS_New_Admission'); }
    launchBedFlow()         { this._openFlow('HMS_Bed_Allocation'); }
    launchInvoiceFlow()     { this._openFlow('HMS_Generate_Invoice'); }

    handleKeyPress(evt) {
        if (evt.key === 'Enter' || evt.key === ' ') {
            const flowName = evt.currentTarget.dataset.flow;
            if (flowName) { this._openFlow(flowName); }
        }
    }

    closeFlow() {
        this.isFlowOpen     = false;
        this.activeFlowName = '';
    }

    handleBackdropClick() {
        this.closeFlow();
    }

    stopPropagation(evt) {
        evt.stopPropagation();
    }

    handleFlowStatusChange(evt) {
        const status = evt.detail.status;
        if (status === 'FINISHED' || status === 'FINISHED_SCREEN') {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: `${this.activeFlowLabel} completed successfully!`,
                variant: 'success'
            }));
            this.closeFlow();
        } else if (status === 'ERROR') {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Flow Error',
                message: 'An error occurred while running the flow. Please try again.',
                variant: 'error'
            }));
        }
    }
}