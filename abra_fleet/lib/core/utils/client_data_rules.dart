// ============================================================================
// Shared definitions for the numbers the client portal shows, so that every
// screen (dashboard, shell badge, SOS screen, Reports) counts the same way.
// Pure functions only: no network calls, no state.
// ============================================================================

/// SOS statuses that mean the alert is finished.
const Set<String> _kSosResolved = {'resolved', 'closed', 'completed'};

/// True when an SOS alert is finished (any spelling / case).
bool isSosResolved(String? status) =>
    _kSosResolved.contains((status ?? '').trim().toLowerCase());

/// True when an SOS alert still needs attention: anything that is not
/// resolved (Active, Pending, In Progress, Escalated, unknown...).
/// Same rule the dashboard already used; now every screen uses it.
bool isSosActive(String? status) => !isSosResolved(status);

/// Employee / customer status buckets: 'active', 'inactive' or 'other'
/// (pending, suspended, blank...). Matching ignores case and spaces.
String employeeStatusBucket(String? status) {
  final s = (status ?? '').trim().toLowerCase();
  if (s == 'active') return 'active';
  if (s == 'inactive') return 'inactive';
  return 'other';
}

/// Trip statuses seen across the backend, grouped.
bool isTripOngoing(String? status) {
  final s = (status ?? '').trim().toLowerCase();
  return s == 'ongoing' || s == 'started' || s == 'in_progress' || s == 'in progress';
}

bool isTripCompleted(String? status) {
  final s = (status ?? '').trim().toLowerCase();
  return s == 'completed' || s == 'done' || s == 'finished';
}

bool isTripCancelled(String? status) =>
    (status ?? '').trim().toLowerCase() == 'cancelled';

/// Strict: only 'assigned' / 'scheduled' (a 'pending' trip is NOT assigned yet).
bool isTripAssigned(String? status) {
  final s = (status ?? '').trim().toLowerCase();
  return s == 'assigned' || s == 'scheduled';
}

bool isTripScheduled(String? status) {
  final s = (status ?? '').trim().toLowerCase();
  return s == 'assigned' || s == 'scheduled' || s == 'pending';
}
