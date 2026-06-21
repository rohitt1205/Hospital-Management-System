/**
 * Queueable wrapper for HMSNotificationService email dispatch.
 */
public without sharing class HMSNotificationQueueable implements Queueable {

    public enum NotificationType {
        DOCTOR_APPOINTMENT,
        DOCTOR_ADMISSION,
        WARD_BED_ALLOCATION,
        WARD_ADMISSION_BED
    }

    private final NotificationType notificationType;
    private final List<Id> recordIds;

    public HMSNotificationQueueable(NotificationType notificationType, List<Id> recordIds) {
        this.notificationType = notificationType;
        this.recordIds = recordIds == null ? new List<Id>() : new List<Id>(recordIds);
    }

    public void execute(QueueableContext context) {
        HMSNotificationService.dispatch(notificationType, new Set<Id>(recordIds));
    }
}