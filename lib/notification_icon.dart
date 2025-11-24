import 'package:flutter/material.dart';
import 'notification_service.dart';
import 'package:provider/provider.dart';

/// Reusable notification icon widget to be added to headers
class NotificationIcon extends StatelessWidget {
  const NotificationIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<NotificationService>(
      builder: (context, notificationService, child) {
        final unreadCount = notificationService.unreadCount;
        
        return GestureDetector(
          onTap: () => _showNotificationDialog(context, notificationService),
          child: Stack(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.notifications_outlined,
                  color: unreadCount > 0 
                      ? const Color(0xFF728D5A) 
                      : Colors.grey.shade600,
                  size: 24,
                ),
              ),
              if (unreadCount > 0)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Text(
                      unreadCount > 99 ? '99+' : unreadCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showNotificationDialog(
    BuildContext context,
    NotificationService notificationService,
  ) {
    // Get notifications sorted by timestamp (newest first)
    final unreadNotifications = notificationService.notifications; // Already sorted newest first
    final readNotifications = notificationService.readNotifications; // Already sorted newest first
    final hasUnread = unreadNotifications.isNotEmpty;
    final hasHistory = readNotifications.isNotEmpty;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Notifications',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            if (hasUnread)
              TextButton(
                onPressed: () {
                  notificationService.markAllAsRead();
                },
                child: const Text('Mark all as read'),
              ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: (!hasUnread && !hasHistory)
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Text('No notifications'),
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Unread notifications section
                      if (hasUnread) ...[
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8.0),
                          child: Text(
                            'New',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xFF728D5A),
                            ),
                          ),
                        ),
                        ...unreadNotifications.map((notification) => _buildNotificationItem(
                              context,
                              notification,
                              notificationService,
                              isRead: false,
                            )),
                        if (hasHistory) const SizedBox(height: 16),
                      ],
                      // History section
                      if (hasHistory) ...[
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8.0, top: 8.0),
                          child: Text(
                            'History',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        ...readNotifications.map((notification) => _buildNotificationItem(
                              context,
                              notification,
                              notificationService,
                              isRead: true,
                            )),
                      ],
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationItem(
    BuildContext context,
    NotificationItem notification,
    NotificationService notificationService, {
    bool isRead = false,
  }) {
    IconData icon;
    Color iconColor;
    
    switch (notification.type) {
      case 'appointment':
        icon = Icons.event;
        iconColor = Colors.blue;
        break;
      case 'reschedule':
        icon = Icons.schedule;
        iconColor = Colors.orange;
        break;
      case 'cancelled':
        icon = Icons.cancel;
        iconColor = Colors.red;
        break;
      case 'feedback':
        icon = Icons.feedback;
        iconColor = Colors.green;
        break;
      default:
        icon = Icons.notifications;
        iconColor = Colors.grey;
    }

    return InkWell(
      onTap: () {
        // Only mark as read if it's not already read
        if (!isRead) {
          notificationService.markAsRead(notification.id);
        }
        Navigator.of(context).pop();
        // Navigate to relevant screen based on notification type
        if (notification.type == 'appointment' || 
            notification.type == 'reschedule' || 
            notification.type == 'cancelled') {
          // Navigate to appointments screen
          // You can customize this navigation based on your app structure
        } else if (notification.type == 'feedback') {
          // Navigate to feedback screen
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isRead 
              ? Colors.grey.shade100 
              : const Color(0xFFBDD9A4).withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isRead 
                ? Colors.grey.shade300 
                : const Color(0xFF728D5A).withOpacity(0.3),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: TextStyle(
                            fontWeight: isRead 
                                ? FontWeight.w500 
                                : FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (!isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.message,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTimestamp(notification.timestamp),
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 7) {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
    }
  }
}

