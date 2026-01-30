// Firebase Cloud Messaging (FCM) Push Notification Helper

import { getServiceClient } from "./auth.ts";

interface PushNotification {
  title: string;
  body: string;
  data?: Record<string, string>;
}

interface FCMMessage {
  to?: string;
  registration_ids?: string[];
  notification: {
    title: string;
    body: string;
    sound?: string;
    badge?: number;
  };
  data?: Record<string, string>;
  priority?: 'high' | 'normal';
  content_available?: boolean;
}

interface FCMResponse {
  multicast_id: number;
  success: number;
  failure: number;
  results?: Array<{
    message_id?: string;
    error?: string;
  }>;
}

// Send push notification to a single user
export async function sendPush(
  userId: string,
  notification: PushNotification
): Promise<boolean> {
  const supabase = getServiceClient();

  // Get user's push tokens
  const { data: tokens, error } = await supabase
    .from('push_tokens')
    .select('token')
    .eq('user_id', userId);

  if (error || !tokens || tokens.length === 0) {
    console.log(`No push tokens found for user ${userId}`);
    return false;
  }

  const tokenList = tokens.map(t => t.token);
  return sendToTokens(tokenList, notification);
}

// Send push notification to multiple users
export async function sendPushToUsers(
  userIds: string[],
  notification: PushNotification
): Promise<boolean> {
  const supabase = getServiceClient();

  // Get all push tokens for the users
  const { data: tokens, error } = await supabase
    .from('push_tokens')
    .select('token')
    .in('user_id', userIds);

  if (error || !tokens || tokens.length === 0) {
    console.log(`No push tokens found for users ${userIds.join(', ')}`);
    return false;
  }

  const tokenList = tokens.map(t => t.token);
  return sendToTokens(tokenList, notification);
}

// Send push notification to specific tokens
export async function sendToTokens(
  tokens: string[],
  notification: PushNotification
): Promise<boolean> {
  const serverKey = Deno.env.get('FCM_SERVER_KEY');

  if (!serverKey) {
    console.error('FCM_SERVER_KEY not configured');
    console.log(`[DEV] Push notification:`, notification);
    return true;
  }

  if (tokens.length === 0) {
    return false;
  }

  try {
    // FCM has a limit of 1000 tokens per request
    const batches: string[][] = [];
    for (let i = 0; i < tokens.length; i += 1000) {
      batches.push(tokens.slice(i, i + 1000));
    }

    let totalSuccess = 0;
    let totalFailure = 0;

    for (const batch of batches) {
      const message: FCMMessage = {
        notification: {
          title: notification.title,
          body: notification.body,
          sound: 'default',
        },
        data: notification.data,
        priority: 'high',
        content_available: true,
      };

      if (batch.length === 1) {
        message.to = batch[0];
      } else {
        message.registration_ids = batch;
      }

      const response = await fetch('https://fcm.googleapis.com/fcm/send', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `key=${serverKey}`,
        },
        body: JSON.stringify(message),
      });

      const result = await response.json() as FCMResponse;

      totalSuccess += result.success || 0;
      totalFailure += result.failure || 0;

      // Handle invalid tokens
      if (result.results) {
        const invalidTokens: string[] = [];
        result.results.forEach((r, i) => {
          if (r.error === 'NotRegistered' || r.error === 'InvalidRegistration') {
            invalidTokens.push(batch[i]);
          }
        });

        // Remove invalid tokens from database
        if (invalidTokens.length > 0) {
          await removeInvalidTokens(invalidTokens);
        }
      }
    }

    console.log(`Push notification sent: ${totalSuccess} success, ${totalFailure} failure`);
    return totalSuccess > 0;
  } catch (error) {
    console.error('Failed to send push notification:', error);
    return false;
  }
}

// Remove invalid tokens from database
async function removeInvalidTokens(tokens: string[]): Promise<void> {
  try {
    const supabase = getServiceClient();

    const { error } = await supabase
      .from('push_tokens')
      .delete()
      .in('token', tokens);

    if (error) {
      console.error('Failed to remove invalid tokens:', error);
    } else {
      console.log(`Removed ${tokens.length} invalid push tokens`);
    }
  } catch (error) {
    console.error('Error removing invalid tokens:', error);
  }
}

// Send order-related push notifications
export async function sendOrderPush(
  userId: string,
  orderNumber: string,
  status: string
): Promise<boolean> {
  let notification: PushNotification;

  switch (status) {
    case 'confirmed':
      notification = {
        title: 'Order Confirmed',
        body: `Your order ${orderNumber} has been confirmed!`,
        data: { type: 'order_update', order_number: orderNumber, status },
      };
      break;
    case 'out_for_delivery':
      notification = {
        title: 'Out for Delivery',
        body: `Your order ${orderNumber} is on its way!`,
        data: { type: 'order_update', order_number: orderNumber, status },
      };
      break;
    case 'delivered':
      notification = {
        title: 'Order Delivered',
        body: `Your order ${orderNumber} has been delivered. Enjoy!`,
        data: { type: 'order_update', order_number: orderNumber, status },
      };
      break;
    case 'cancelled':
      notification = {
        title: 'Order Cancelled',
        body: `Your order ${orderNumber} has been cancelled.`,
        data: { type: 'order_update', order_number: orderNumber, status },
      };
      break;
    case 'delivery_failed':
      notification = {
        title: 'Delivery Attempt Failed',
        body: `We couldn't deliver your order ${orderNumber}. We'll retry soon.`,
        data: { type: 'order_update', order_number: orderNumber, status },
      };
      break;
    default:
      notification = {
        title: 'Order Update',
        body: `Your order ${orderNumber} status: ${status}`,
        data: { type: 'order_update', order_number: orderNumber, status },
      };
  }

  return sendPush(userId, notification);
}

// Send push to delivery staff for new assignment
export async function sendDeliveryAssignmentPush(
  deliveryStaffId: string,
  orderNumber: string,
  address: string
): Promise<boolean> {
  return sendPush(deliveryStaffId, {
    title: 'New Delivery Assignment',
    body: `Order ${orderNumber} assigned to you. Deliver to: ${address}`,
    data: {
      type: 'delivery_assignment',
      order_number: orderNumber,
    },
  });
}

// Send push to admins for new order
export async function sendNewOrderPushToAdmins(
  orderNumber: string,
  totalAmount: string
): Promise<boolean> {
  const supabase = getServiceClient();

  // Get all admin user IDs
  const { data: admins, error } = await supabase
    .from('users')
    .select('id')
    .eq('role', 'admin')
    .eq('is_active', true);

  if (error || !admins || admins.length === 0) {
    console.log('No active admins found for push notification');
    return false;
  }

  const adminIds = admins.map(a => a.id);

  return sendPushToUsers(adminIds, {
    title: 'New Order Received',
    body: `Order ${orderNumber} - ${totalAmount}`,
    data: {
      type: 'new_order',
      order_number: orderNumber,
    },
  });
}
