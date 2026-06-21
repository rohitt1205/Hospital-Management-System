/**
 * User-friendly business-rule exception for appointment booking flows.
 * Never surface raw DML or query exceptions to Agentforce callers.
 */
public class AppointmentBookingException extends Exception {
}