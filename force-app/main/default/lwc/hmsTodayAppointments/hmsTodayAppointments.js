import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getTodayAppointments from '@salesforce/apex/HMSDashboardController.getTodayAppointments';

const STATUS_CLASS = {
    'Scheduled' : 'badge-scheduled',
    'Confirmed' : 'badge-confirmed',
    'Completed' : 'badge-completed',
    'Cancelled'  : 'badge-cancelled',
    'No Show'    : 'badge-noshow'
};

export default class HmsTodayAppointments extends NavigationMixin(LightningElement) {
    @track appointments = [];
    @track isLoading    = true;
    @track activeFilter = 'All';

    connectedCallback() {
        this.loadData();
    }

    loadData() {
        this.isLoading = true;
        getTodayAppointments()
            .then(data => {
                this.appointments = data.map(a => this._enrichApt(a));
                this.isLoading    = false;
            })
            .catch(() => { this.isLoading = false; });
    }

    _enrichApt(a) {
        const dt = a.appointmentDateTime ? new Date(a.appointmentDateTime) : null;
        let timeHour = '', timeAmPm = '';
        if (dt) {
            let h = dt.getHours();
            const m = String(dt.getMinutes()).padStart(2, '0');
            timeAmPm = h >= 12 ? 'PM' : 'AM';
            h = h % 12 || 12;
            timeHour = `${h}:${m}`;
        }
        return {
            ...a,
            timeHour,
            timeAmPm,
            statusClass : STATUS_CLASS[a.status] || 'badge-scheduled',
            isUrgent    : a.priority === 'High' || a.priority === 'Emergency'
        };
    }

    get filteredAppointments() {
        if (this.activeFilter === 'All')       { return this.appointments; }
        if (this.activeFilter === 'Scheduled') { return this.appointments.filter(a => a.status === 'Scheduled' || a.status === 'Confirmed'); }
        if (this.activeFilter === 'Completed') { return this.appointments.filter(a => a.status === 'Completed'); }
        return this.appointments;
    }

    get isEmpty()               { return this.filteredAppointments.length === 0; }
    get appointmentCountLabel() { return `${this.appointments.length} appointment${this.appointments.length !== 1 ? 's' : ''} today`; }

    get filterAllClass()   { return this.activeFilter === 'All'       ? 'filter-pill active' : 'filter-pill'; }
    get filterSchedClass() { return this.activeFilter === 'Scheduled' ? 'filter-pill active' : 'filter-pill'; }
    get filterDoneClass()  { return this.activeFilter === 'Completed' ? 'filter-pill active' : 'filter-pill'; }

    filterAll()       { this.activeFilter = 'All'; }
    filterScheduled() { this.activeFilter = 'Scheduled'; }
    filterCompleted() { this.activeFilter = 'Completed'; }

    navigateToRecord(evt) {
        const recordId = evt.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, objectApiName: 'Appointment__c', actionName: 'view' }
        });
    }
}