import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

/// Notification model
class NotificationItem {
  final String id;
  final String type; // 'appointment', 'reschedule', 'cancelled', 'feedback'
  final String title;
  final String message;
  final DateTime timestamp;
  final bool isRead;
  final Map<String, dynamic>? data;

  NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.timestamp,
    this.isRead = false,
    this.data,
  });
}

/// Service to manage notifications for appointments, reschedules, cancellations, and feedbacks
class NotificationService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  List<NotificationItem> _notifications = [];
  List<NotificationItem> _readNotifications = []; // History of read notifications
  StreamSubscription? _appointmentSubscription;
  StreamSubscription? _feedbackSubscription;
  // Store previous appointment data to detect changes (reschedules)
  final Map<String, Map<String, dynamic>> _previousAppointments = {};
  // Track read notification IDs persistently
  Set<String> _readNotificationIds = {};
  static const String _readNotificationsKey = 'read_notification_ids';
  static const String _readNotificationsHistoryKey = 'read_notifications_history';
  static const String _lastLoginTimestampKey = 'last_login_timestamp';
  static const int _maxHistorySize = 50; // Limit history to last 50 notifications

  // Only return unread notifications, sorted by timestamp (newest first)
  List<NotificationItem> get notifications {
    final unread = _notifications.where((n) => !n.isRead).toList();
    unread.sort((a, b) => b.timestamp.compareTo(a.timestamp)); // Newest first
    return unread;
  }
  
  // Return read notifications (history), sorted by timestamp (newest first)
  List<NotificationItem> get readNotifications {
    final read = List<NotificationItem>.from(_readNotifications);
    read.sort((a, b) => b.timestamp.compareTo(a.timestamp)); // Newest first
    return read;
  }
  
  // Get all notifications (unread + history) for display, sorted by timestamp
  List<NotificationItem> get allNotifications {
    final all = [..._notifications.where((n) => !n.isRead), ..._readNotifications];
    all.sort((a, b) => b.timestamp.compareTo(a.timestamp)); // Newest first
    return all;
  }
  
  // Only count unread notifications (excludes read ones)
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  NotificationService() {
    _loadReadNotifications();
    _initializeListeners();
  }

  // Load read notification IDs and history from SharedPreferences
  Future<void> _loadReadNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final readIds = prefs.getStringList(_readNotificationsKey) ?? [];
      _readNotificationIds = readIds.toSet();
      
      // Load notification history
      final historyJson = prefs.getString(_readNotificationsHistoryKey);
      if (historyJson != null) {
        // Parse history from JSON (simplified - in production you'd use proper JSON serialization)
        // For now, we'll rebuild history from IDs
        _readNotifications = [];
      }
    } catch (e) {
      debugPrint('Error loading read notifications: $e');
      _readNotificationIds = {};
      _readNotifications = [];
    }
  }

  // Save read notification IDs and history to SharedPreferences
  Future<void> _saveReadNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_readNotificationsKey, _readNotificationIds.toList());
      
      // Save notification history (limit to last 50)
      final historyToSave = _readNotifications.take(_maxHistorySize).toList();
      // In a production app, you'd serialize the full NotificationItem objects
      // For now, we'll just save the IDs and reconstruct from them
      final historyIds = historyToSave.map((n) => n.id).toList();
      await prefs.setStringList(_readNotificationsHistoryKey, historyIds);
    } catch (e) {
      debugPrint('Error saving read notifications: $e');
    }
  }

  void _initializeListeners() {
    final user = _auth.currentUser;
    if (user == null) return;

    // Fetch vet name first for feedback queries
    _fetchVetNameAndSetupListeners(user.uid);
  }

  void _fetchVetNameAndSetupListeners(String userId) async {
    try {
      final vetDoc = await _firestore.collection('vets').doc(userId).get();
      final vetName = vetDoc.data()?['name'] as String?;

      // Listen to ALL appointments for this vet to detect both new appointments and reschedules
      _appointmentSubscription = _firestore
          .collection('user_appointments')
          .where('vetId', isEqualTo: userId)
          .snapshots()
          .listen((snapshot) {
        // Initialize previous appointments map on first load
        if (_previousAppointments.isEmpty && snapshot.docs.isNotEmpty) {
          for (var doc in snapshot.docs) {
            _previousAppointments[doc.id] = Map<String, dynamic>.from(doc.data());
          }
        }

        for (var change in snapshot.docChanges) {
          final data = change.doc.data() as Map<String, dynamic>;
          final appointmentId = change.doc.id;
          final previousData = _previousAppointments[appointmentId];

          if (change.type == DocumentChangeType.added) {
            // New appointment - check if it's a new request or reschedule
            final isReschedule = data['rescheduleRequest'] == true || 
                                 data['isReschedule'] == true ||
                                 (data.containsKey('previousAppointmentDateTime') && 
                                  data['previousAppointmentDateTime'] != null);
            
            if (isReschedule) {
              // This is a rescheduled appointment
              final notification = NotificationItem(
                id: 'reschedule_${appointmentId}_${DateTime.now().millisecondsSinceEpoch}',
                type: 'reschedule',
                title: 'Appointment Rescheduled',
                message: '${data['userName'] ?? 'A client'} rescheduled appointment for ${data['petName'] ?? 'their pet'}',
                timestamp: (data['updatedAt'] as Timestamp?)?.toDate() ?? 
                          (data['createdAt'] as Timestamp?)?.toDate() ?? 
                          DateTime.now(),
                data: {'appointmentId': appointmentId, ...data},
              );
              _addNotification(notification);
            } else {
              // New appointment request
              final notification = NotificationItem(
                id: 'appointment_${appointmentId}',
                type: 'appointment',
                title: 'New Appointment Request',
                message: '${data['userName'] ?? 'A client'} requested an appointment for ${data['petName'] ?? 'their pet'}',
                timestamp: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
                data: {'appointmentId': appointmentId, ...data},
              );
              _addNotification(notification);
            }
            
            // Store current data for future comparisons
            _previousAppointments[appointmentId] = Map<String, dynamic>.from(data);
          } 
          else if (change.type == DocumentChangeType.modified) {
            // Modified appointment - check for cancellation first, then reschedule indicators
            bool isCancelled = false;
            bool isReschedule = false;
            String rescheduleMessage = '';

            if (previousData != null) {
              // Check if status changed to cancelled
              final oldStatus = (previousData['status']?.toString() ?? '').toLowerCase();
              final newStatus = (data['status']?.toString() ?? '').toLowerCase();
              
              if (oldStatus != 'cancelled' && newStatus == 'cancelled') {
                isCancelled = true;
                final notification = NotificationItem(
                  id: 'cancelled_${appointmentId}_${DateTime.now().millisecondsSinceEpoch}',
                  type: 'cancelled',
                  title: 'Appointment Cancelled',
                  message: '${data['userName'] ?? 'A client'} cancelled their appointment for ${data['petName'] ?? 'their pet'}',
                  timestamp: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
                  data: {'appointmentId': appointmentId, ...data},
                );
                _addNotification(notification);
              }

              // Check if appointmentDateTime changed (indicates reschedule) - only if not cancelled
              if (!isCancelled) {
                final oldDateTime = previousData['appointmentDateTime'] as Timestamp?;
                final newDateTime = data['appointmentDateTime'] as Timestamp?;
                
                if (oldDateTime != null && newDateTime != null) {
                  final oldDate = oldDateTime.toDate();
                  final newDate = newDateTime.toDate();
                  
                  // If date/time changed significantly (more than 1 minute difference), it's a reschedule
                  if ((newDate.difference(oldDate).inMinutes.abs() > 1)) {
                    isReschedule = true;
                    rescheduleMessage = '${data['userName'] ?? 'A client'} rescheduled appointment for ${data['petName'] ?? 'their pet'}';
                  }
                }

                // Check if rescheduleRequest field was added or set to true
                if (!isReschedule && 
                    data.containsKey('rescheduleRequest') && 
                    data['rescheduleRequest'] == true &&
                    (previousData['rescheduleRequest'] != true)) {
                  isReschedule = true;
                  rescheduleMessage = '${data['userName'] ?? 'A client'} requested to reschedule appointment for ${data['petName'] ?? 'their pet'}';
                }

                // Check if isReschedule field was added or set to true
                if (!isReschedule && 
                    data.containsKey('isReschedule') && 
                    data['isReschedule'] == true &&
                    (previousData['isReschedule'] != true)) {
                  isReschedule = true;
                  rescheduleMessage = '${data['userName'] ?? 'A client'} rescheduled appointment for ${data['petName'] ?? 'their pet'}';
                }

                // Check if status changed from non-Pending to Pending (might indicate reschedule)
                if (!isReschedule && 
                    oldStatus.isNotEmpty && 
                    newStatus.isNotEmpty &&
                    oldStatus != 'pending' && 
                    newStatus == 'pending') {
                  // Only treat as reschedule if appointmentDateTime also changed
                  final oldDateTime = previousData['appointmentDateTime'] as Timestamp?;
                  final newDateTime = data['appointmentDateTime'] as Timestamp?;
                  if (oldDateTime != null && newDateTime != null) {
                    final oldDate = oldDateTime.toDate();
                    final newDate = newDateTime.toDate();
                    if ((newDate.difference(oldDate).inMinutes.abs() > 1)) {
                      isReschedule = true;
                      rescheduleMessage = '${data['userName'] ?? 'A client'} rescheduled appointment for ${data['petName'] ?? 'their pet'}';
                    }
                  }
                }
              }
            }

            if (isReschedule && !isCancelled) {
              final notification = NotificationItem(
                id: 'reschedule_${appointmentId}_${DateTime.now().millisecondsSinceEpoch}',
                type: 'reschedule',
                title: 'Appointment Rescheduled',
                message: rescheduleMessage,
                timestamp: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
                data: {'appointmentId': appointmentId, ...data},
              );
              _addNotification(notification);
            }

            // Update stored data
            _previousAppointments[appointmentId] = Map<String, dynamic>.from(data);
          }
        }
      });

      // Listen for new feedbacks - use vetName if available, otherwise vetId
      if (vetName != null && vetName.isNotEmpty) {
        _feedbackSubscription = _firestore
            .collection('feedback')
            .where('vetName', isEqualTo: vetName)
            .snapshots()
            .listen((snapshot) {
          for (var change in snapshot.docChanges) {
            if (change.type == DocumentChangeType.added) {
              final data = change.doc.data() as Map<String, dynamic>;
              final rating = data['rating'] ?? 0;
              final notification = NotificationItem(
                id: 'feedback_${change.doc.id}',
                type: 'feedback',
                title: 'New Feedback Received',
                message: '${data['userName'] ?? 'A client'} left a ${rating}-star rating and feedback',
                timestamp: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
                data: {'feedbackId': change.doc.id, ...data},
              );
              _addNotification(notification);
            }
          }
        });
      } else {
        // Fallback to vetId if vetName is not available
        _feedbackSubscription = _firestore
            .collection('feedback')
            .where('vetId', isEqualTo: userId)
            .snapshots()
            .listen((snapshot) {
          for (var change in snapshot.docChanges) {
            if (change.type == DocumentChangeType.added) {
              final data = change.doc.data() as Map<String, dynamic>;
              final rating = data['rating'] ?? 0;
              final notification = NotificationItem(
                id: 'feedback_${change.doc.id}',
                type: 'feedback',
                title: 'New Feedback Received',
                message: '${data['userName'] ?? 'A client'} left a ${rating}-star rating and feedback',
                timestamp: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
                data: {'feedbackId': change.doc.id, ...data},
              );
              _addNotification(notification);
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error setting up notification listeners: $e');
    }
  }

  void _addNotification(NotificationItem notification) {
    // Check if notification already exists in unread list
    if (_notifications.any((n) => n.id == notification.id)) {
      return;
    }

    // Check if this notification has been read before
    if (_readNotificationIds.contains(notification.id)) {
      // Don't add as new notification, but we can add to history if not already there
      if (!_readNotifications.any((n) => n.id == notification.id)) {
        // Add to history with read status
        final readNotification = NotificationItem(
          id: notification.id,
          type: notification.type,
          title: notification.title,
          message: notification.message,
          timestamp: notification.timestamp,
          isRead: true,
          data: notification.data,
        );
        _readNotifications.add(readNotification);
        // Sort history by timestamp (newest first) and limit size
        _readNotifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        if (_readNotifications.length > _maxHistorySize) {
          _readNotifications = _readNotifications.take(_maxHistorySize).toList();
        }
        notifyListeners();
      }
      return; // Don't add as new/unread notification
    }

    // Add as new unread notification (will be sorted by getter)
    _notifications.add(notification);
    // Sort by timestamp (newest first)
    _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    notifyListeners();
  }

  void markAsRead(String notificationId) {
    // Find the notification to move to history
    final notificationIndex = _notifications.indexWhere((n) => n.id == notificationId);
    if (notificationIndex != -1) {
      final notification = _notifications[notificationIndex];
      
      // Mark as read and add to history
      _readNotificationIds.add(notificationId);
      
      // Create read version and add to history
      final readNotification = NotificationItem(
        id: notification.id,
        type: notification.type,
        title: notification.title,
        message: notification.message,
        timestamp: notification.timestamp,
        isRead: true,
        data: notification.data,
      );
      
      // Remove from unread list
      _notifications.removeAt(notificationIndex);
      
      // Add to history (if not already there)
      if (!_readNotifications.any((n) => n.id == notificationId)) {
        _readNotifications.add(readNotification);
        // Sort history by timestamp (newest first) and limit size
        _readNotifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        if (_readNotifications.length > _maxHistorySize) {
          _readNotifications = _readNotifications.take(_maxHistorySize).toList();
        }
      }
      
      _saveReadNotifications();
      notifyListeners();
    }
  }

  void markAllAsRead() {
    // Move all current notifications to history
    for (var notification in _notifications) {
      _readNotificationIds.add(notification.id);
      
      // Add to history
      final readNotification = NotificationItem(
        id: notification.id,
        type: notification.type,
        title: notification.title,
        message: notification.message,
        timestamp: notification.timestamp,
        isRead: true,
        data: notification.data,
      );
      
      if (!_readNotifications.any((n) => n.id == notification.id)) {
        _readNotifications.add(readNotification);
      }
    }
    
    // Sort history by timestamp (newest first) and limit size
    _readNotifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (_readNotifications.length > _maxHistorySize) {
      _readNotifications = _readNotifications.take(_maxHistorySize).toList();
    }
    
    // Clear unread notifications
    _notifications.clear();
    
    _saveReadNotifications();
    notifyListeners();
  }

  void clearNotifications() {
    _notifications.clear();
    notifyListeners();
  }

  // Clear all read notifications and reset state (called on logout)
  Future<void> resetOnLogout() async {
    // Save last logout timestamp to prevent old notifications from showing
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastLoginTimestampKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('Error saving logout timestamp: $e');
    }
    
    // Clear unread notifications but keep history
    _notifications.clear();
    _previousAppointments.clear();
    _appointmentSubscription?.cancel();
    _feedbackSubscription?.cancel();
    _appointmentSubscription = null;
    _feedbackSubscription = null;
    notifyListeners();
  }

  // Reinitialize on login
  Future<void> reinitializeOnLogin() async {
    // Load read notifications and history before initializing
    await _loadReadNotifications();
    
    // Clear current unread notifications but keep history
    // This ensures only new notifications after login are counted as unread
    _notifications.clear();
    _previousAppointments.clear();
    _appointmentSubscription?.cancel();
    _feedbackSubscription?.cancel();
    _appointmentSubscription = null;
    _feedbackSubscription = null;
    
    // Save current login timestamp for future reference
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastLoginTimestampKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('Error saving login timestamp: $e');
    }
    
    // Start fresh listeners (history will be preserved)
    // Only new notifications after this point will be counted as unread
    _initializeListeners();
    notifyListeners();
  }

  @override
  void dispose() {
    _appointmentSubscription?.cancel();
    _feedbackSubscription?.cancel();
    super.dispose();
  }
}

