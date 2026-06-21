import { LightningElement, track } from 'lwc';
import getBedOccupancy from '@salesforce/apex/HMSDashboardController.getBedOccupancy';

export default class HmsBedOccupancy extends LightningElement {
    @track wards     = [];
    @track isLoading = true;

    get isEmpty()       { return this.wards.length === 0; }
    get totalBeds()     { return this.wards.reduce((s, w) => s + (w.totalBeds    || 0), 0); }
    get totalOccupied() { return this.wards.reduce((s, w) => s + (w.occupiedBeds || 0), 0); }
    get totalAvailable(){ return this.wards.reduce((s, w) => s + (w.availableBeds || 0), 0); }

    connectedCallback() {
        this.loadData();
    }

    loadData() {
        this.isLoading = true;
        getBedOccupancy()
            .then(data => {
                this.wards     = data.map(w => this._enrich(w));
                this.isLoading = false;
            })
            .catch(() => { this.isLoading = false; });
    }

    _enrich(w) {
        const pct      = w.occupancyPercent || 0;
        const barColor = pct >= 90 ? '#f44336'
                       : pct >= 70 ? '#ff9800'
                       : pct >= 40 ? '#2196f3'
                       :             '#4caf50';
        const pctColor = pct >= 90 ? '#f44336'
                       : pct >= 70 ? '#ff9800'
                       :             '#4caf50';
        return {
            ...w,
            barStyle : `width:${pct}%; background:${barColor};`,
            pctStyle : `color:${pctColor};`
        };
    }
}