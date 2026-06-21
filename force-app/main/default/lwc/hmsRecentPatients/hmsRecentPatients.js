import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getRecentPatients from '@salesforce/apex/HMSDashboardController.getRecentPatients';

// Rotates through avatar gradient colours
const AVATAR_GRADIENTS = [
    'avatar-blue', 'avatar-teal', 'avatar-purple', 'avatar-orange',
    'avatar-cyan', 'avatar-rose', 'avatar-indigo', 'avatar-green'
];

const STATUS_CLASS = {
    'Active'     : 'badge-active',
    'Admitted'   : 'badge-admitted',
    'Discharged' : 'badge-discharged',
    'Deceased'   : 'badge-deceased'
};

export default class HmsRecentPatients extends NavigationMixin(LightningElement) {
    @track patients  = [];
    @track isLoading = true;

    get isEmpty()       { return this.patients.length === 0; }
    get skeletonRows()  { return [1, 2, 3, 4, 5]; }

    connectedCallback() {
        this.loadData();
    }

    loadData() {
        this.isLoading = true;
        getRecentPatients()
            .then(data => {
                this.patients  = data.map((p, i) => this._enrich(p, i));
                this.isLoading = false;
            })
            .catch(() => { this.isLoading = false; });
    }

    _enrich(p, idx) {
        const initial = p.name ? p.name.charAt(0).toUpperCase() : '?';
        return {
            ...p,
            initial,
            avatarClass  : `rp-avatar ${AVATAR_GRADIENTS[idx % AVATAR_GRADIENTS.length]}`,
            statusClass  : STATUS_CLASS[p.status] || 'badge-active'
        };
    }

    navigateToRecord(evt) {
        const recordId = evt.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, objectApiName: 'Patient__c', actionName: 'view' }
        });
    }
}