# Notifications API

This document describes the notification endpoints for managing in-app notifications and their read status.

## Overview

SecureSharing provides two notification delivery mechanisms:

1. **Push Notifications** - Via OneSignal for background delivery
2. **WebSocket Channel** - Real-time in-app notifications via Phoenix Channels
3. **REST API** - For fetching/managing notification history and read status

All notifications are persisted in the `user_notifications` table for tracking read status.

---

## REST API Endpoints

### List Notifications

Retrieve a paginated list of notifications for the authenticated user.

**Endpoint:** `GET /api/notifications`

**Query Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `limit` | integer | 50 | Maximum notifications to return |
| `offset` | integer | 0 | Pagination offset |
| `unread_only` | boolean | false | Only return unread notifications |

**Response:**

```json
{
  "data": [
    {
      "id": "01234567-89ab-cdef-0123-456789abcdef",
      "type": "share_received",
      "title": "New Share",
      "body": "John Doe shared a file with you",
      "data": {
        "id": "share-uuid",
        "grantor_id": "user-uuid",
        "resource_type": "file",
        "resource_id": "file-uuid",
        "permission": "read"
      },
      "read_at": null,
      "created_at": "2026-01-18T12:00:00.000000Z"
    }
  ],
  "meta": {
    "unread_count": 5
  }
}
```

---

### Get Unread Count

Get the count of unread notifications.

**Endpoint:** `GET /api/notifications/unread_count`

**Response:**

```json
{
  "data": {
    "unread_count": 5
  }
}
```

---

### Mark Notification as Read

Mark a single notification as read.

**Endpoint:** `POST /api/notifications/:id/read`

**Response:**

```json
{
  "data": {
    "notification_id": "01234567-89ab-cdef-0123-456789abcdef",
    "unread_count": 4
  }
}
```

**Errors:**

| Status | Error | Description |
|--------|-------|-------------|
| 404 | Not Found | Notification not found or doesn't belong to user |

---

### Mark All Notifications as Read

Mark all notifications as read for the authenticated user.

**Endpoint:** `POST /api/notifications/read_all`

**Response:**

```json
{
  "data": {
    "marked_count": 5,
    "unread_count": 0
  }
}
```

---

### Dismiss Notification

Remove a notification from the user's list (without marking as read).

**Endpoint:** `DELETE /api/notifications/:id`

**Response:** `204 No Content`

**Errors:**

| Status | Error | Description |
|--------|-------|-------------|
| 404 | Not Found | Notification not found or doesn't belong to user |

---

## WebSocket Channel

Connect to the notification channel for real-time notifications.

### Joining

**Topic:** `notification:{user_id}`

```javascript
const channel = socket.channel(`notification:${userId}`, {})
channel.join()
  .receive("ok", (response) => {
    console.log("Joined", response.unread_count)
  })
```

**Join Response:**

```json
{
  "unread_count": 5
}
```

### Incoming Events

#### `share_received`

Sent when someone shares a file or folder with you.

```json
{
  "notification_id": "uuid",
  "title": "New Share",
  "body": "Someone shared a file with you",
  "id": "share-uuid",
  "grantor_id": "user-uuid",
  "resource_type": "file",
  "resource_id": "file-uuid",
  "permission": "read",
  "created_at": "2026-01-18T12:00:00.000000Z"
}
```

#### `share_revoked`

Sent when a share is revoked.

```json
{
  "notification_id": "uuid",
  "title": "Share Revoked",
  "body": "A shared file was revoked",
  "id": "share-uuid",
  "resource_type": "file",
  "resource_id": "file-uuid",
  "created_at": "2026-01-18T12:00:00.000000Z"
}
```

#### `recovery_request`

Sent to trustees when someone requests account recovery.

```json
{
  "notification_id": "uuid",
  "title": "Recovery Request",
  "body": "Someone needs your approval to recover their account",
  "id": "request-uuid",
  "user_id": "requester-uuid",
  "status": "pending",
  "created_at": "2026-01-18T12:00:00.000000Z",
  "expires_at": "2026-01-25T12:00:00.000000Z"
}
```

#### `recovery_approval`

Sent to the recovery requester when a trustee approves.

```json
{
  "notification_id": "uuid",
  "title": "Recovery Approved",
  "body": "A trustee approved your recovery request (2/3)",
  "request_id": "request-uuid",
  "trustee_id": "trustee-uuid",
  "current_approvals": 2,
  "threshold": 3,
  "status": "pending",
  "created_at": "2026-01-18T12:00:00.000000Z"
}
```

#### `recovery_complete`

Sent when account recovery is complete.

```json
{
  "notification_id": "uuid",
  "title": "Recovery Complete",
  "body": "Your account recovery is complete",
  "request_id": "request-uuid",
  "created_at": "2026-01-18T12:00:00.000000Z"
}
```

#### `tenant_invitation`

Sent when invited to join a tenant/organization.

```json
{
  "notification_id": "uuid",
  "title": "Organization Invitation",
  "body": "John Doe invited you to join Acme Corp",
  "tenant_id": "tenant-uuid",
  "tenant_name": "Acme Corp",
  "inviter_id": "inviter-uuid",
  "inviter_name": "John Doe",
  "created_at": "2026-01-18T12:00:00.000000Z"
}
```

### Outgoing Messages

#### `mark_read`

Mark a notification as read.

```javascript
channel.push("mark_read", { notification_id: "uuid" })
  .receive("ok", (response) => {
    console.log("Marked read", response.notification_id, response.unread_count)
  })
  .receive("error", (error) => {
    console.error("Error", error.reason)
  })
```

**Response:**

```json
{
  "notification_id": "uuid",
  "unread_count": 4
}
```

#### `mark_all_read`

Mark all notifications as read.

```javascript
channel.push("mark_all_read", {})
  .receive("ok", (response) => {
    console.log("Marked all read", response.marked_count)
  })
```

**Response:**

```json
{
  "marked_count": 5,
  "unread_count": 0
}
```

#### `dismiss`

Dismiss a notification.

```javascript
channel.push("dismiss", { notification_id: "uuid" })
  .receive("ok", (response) => {
    console.log("Dismissed", response.notification_id)
  })
```

#### `get_notifications`

Fetch notifications.

```javascript
channel.push("get_notifications", { limit: 20, offset: 0, unread_only: false })
  .receive("ok", (response) => {
    console.log("Notifications", response.notifications)
  })
```

#### `get_unread_count`

Get unread count.

```javascript
channel.push("get_unread_count", {})
  .receive("ok", (response) => {
    console.log("Unread:", response.unread_count)
  })
```

---

## Notification Types

| Type | Description | Triggered By |
|------|-------------|--------------|
| `share_received` | New share invitation | Creating a share |
| `share_revoked` | Share access removed | Revoking a share |
| `recovery_request` | Recovery needs approval | Starting recovery |
| `recovery_approval` | Trustee approved recovery | Approving recovery |
| `recovery_complete` | Recovery finished | Completing recovery |
| `tenant_invitation` | Invited to organization | Inviting member |

---

## Email Notifications

In addition to in-app notifications, certain events also trigger email notifications:

| Event | Email Template |
|-------|----------------|
| Tenant invitation | `invitation_email` |
| Share received | `share_notification_email` |
| Recovery request (to trustees) | `recovery_request_email` |

Email notifications are delivered via Swoosh and can be configured with various adapters (SMTP, SendGrid, Mailgun, etc.).

---

## Push Notifications

Push notifications are delivered via OneSignal for cross-platform support.

### Configuration

Set environment variables:

```bash
ONESIGNAL_APP_ID=your-app-id
ONESIGNAL_API_KEY=your-api-key
```

### Device Registration

Register device push token:

**Endpoint:** `POST /api/devices/:id/push`

```json
{
  "player_id": "onesignal-player-id"
}
```

Unregister:

**Endpoint:** `DELETE /api/devices/:id/push`

---

## Database Schema

```sql
CREATE TABLE user_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type VARCHAR(255) NOT NULL,
  title VARCHAR(200) NOT NULL,
  body TEXT NOT NULL,
  data JSONB DEFAULT '{}',
  read_at TIMESTAMP WITH TIME ZONE,
  dismissed_at TIMESTAMP WITH TIME ZONE,
  inserted_at TIMESTAMP WITH TIME ZONE NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE INDEX user_notifications_user_id_idx ON user_notifications(user_id);
CREATE INDEX user_notifications_user_read_idx ON user_notifications(user_id, read_at);
CREATE INDEX user_notifications_user_inserted_idx ON user_notifications(user_id, inserted_at);
CREATE INDEX user_notifications_type_idx ON user_notifications(type);
```
