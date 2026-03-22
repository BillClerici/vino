import 'place.dart';
import 'user.dart';

class Trip {
  final String id;
  final String name;
  final String description;
  final String status;
  final String? scheduledDate;
  final String? endDate;
  final String? meetingLocation;
  final String? meetingTime;
  final String? meetingNotes;
  final String? transportation;
  final String? budgetNotes;
  final String? notes;
  final int memberCount;
  final int stopCount;
  final String? createdByName;
  final User? createdBy;
  final List<TripStop>? tripStops;
  final List<TripMember>? tripMembers;

  const Trip({
    required this.id,
    required this.name,
    this.description = '',
    this.status = 'draft',
    this.scheduledDate,
    this.endDate,
    this.meetingLocation,
    this.meetingTime,
    this.meetingNotes,
    this.transportation,
    this.budgetNotes,
    this.notes,
    this.memberCount = 0,
    this.stopCount = 0,
    this.createdByName,
    this.createdBy,
    this.tripStops,
    this.tripMembers,
  });

  factory Trip.fromJson(Map<String, dynamic> json) {
    return Trip(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      status: json['status'] as String? ?? 'draft',
      scheduledDate: json['scheduled_date'] as String?,
      endDate: json['end_date'] as String?,
      meetingLocation: json['meeting_location'] as String?,
      meetingTime: json['meeting_time'] as String?,
      meetingNotes: json['meeting_notes'] as String?,
      transportation: json['transportation'] as String?,
      budgetNotes: json['budget_notes'] as String?,
      notes: json['notes'] as String?,
      memberCount: json['member_count'] as int? ?? 0,
      stopCount: json['stop_count'] as int? ?? 0,
      createdByName: json['created_by_name'] as String?,
      createdBy: json['created_by'] != null
          ? User.fromJson(json['created_by'] as Map<String, dynamic>)
          : null,
      tripStops: (json['trip_stops'] as List<dynamic>?)
          ?.map((e) => TripStop.fromJson(e as Map<String, dynamic>))
          .toList(),
      tripMembers: (json['trip_members'] as List<dynamic>?)
          ?.map((e) => TripMember.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class TripStop {
  final String id;
  final Place? place;
  final int order;
  final String? arrivalTime;
  final int? durationMinutes;
  final int? travelMinutes;
  final double? travelMiles;
  final String description;
  final String notes;

  const TripStop({
    required this.id,
    this.place,
    this.order = 0,
    this.arrivalTime,
    this.durationMinutes,
    this.travelMinutes,
    this.travelMiles,
    this.description = '',
    this.notes = '',
  });

  factory TripStop.fromJson(Map<String, dynamic> json) {
    return TripStop(
      id: json['id'] as String,
      place: json['place'] != null
          ? Place.fromJson(json['place'] as Map<String, dynamic>)
          : null,
      order: json['order'] as int? ?? 0,
      arrivalTime: json['arrival_time'] as String?,
      durationMinutes: json['duration_minutes'] as int?,
      travelMinutes: json['travel_minutes'] as int?,
      travelMiles: _parseDouble(json['travel_miles']),
      description: json['description'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
    );
  }
}

class TripMember {
  final String id;
  final User? user;
  final String role;
  final String rsvpStatus;
  final String displayName;
  final String displayInitial;
  final String? inviteEmail;

  const TripMember({
    required this.id,
    this.user,
    this.role = 'member',
    this.rsvpStatus = 'pending',
    this.displayName = '',
    this.displayInitial = '',
    this.inviteEmail,
  });

  factory TripMember.fromJson(Map<String, dynamic> json) {
    return TripMember(
      id: json['id'] as String,
      user: json['user'] != null
          ? User.fromJson(json['user'] as Map<String, dynamic>)
          : null,
      role: json['role'] as String? ?? 'member',
      rsvpStatus: json['rsvp_status'] as String? ?? 'pending',
      displayName: json['display_name'] as String? ?? '',
      displayInitial: json['display_initial'] as String? ?? '',
      inviteEmail: json['invite_email'] as String?,
    );
  }
}

double? _parseDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
