// Expo Push Notification Helper
// PERFORMANCE OPTIMIZED: Item 20 from performance audit

import { getServiceClient } from "./auth.ts";

interface PushNotification {
  title: string;
  body: string;
  data?: Record<string, string>;
  channelId?: string;
}

interface ExpoPushMessage {
  to: string;
  title: string;
  body: string;
  data?: Record<string, string>;
  channelId?: string;
  sound: 'default';
  priority: 'high';
}

interface ExpoPushTicket {
  status: 'ok' | 'error';
  id?: string;
  message?: string;
  details?: {
    error?: 'DeviceNotRegistered' | 'InvalidCredentials' | 'MessageTooBig' | 'MessageRateExceeded';
  };
}

// Set to true to skip actual sending and just log (for dev without real tokens)
const DEV_MODE = false;

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

// Send push notification to specific tokens via Expo Push API
// ITEM 20: Batch Invalid Push Token Removal
export async function sendToTokens(
  tokens: string[],
  notification: PushNotification
): Promise<boolean> {
  if (DEV_MODE) {
    console.log(`[DEV] Push notification to ${tokens.length} token(s):`, notification);
    return true;
  }

  if (tokens.length === 0) {
    return false;
  }

  try {
    // Expo has a limit of 100 messages per request
    const batches: string[][] = [];
    for (let i = 0; i < tokens.length; i += 100) {
      batches.push(tokens.slice(i, i + 100));
    }

    let totalSuccess = 0;
    let totalFailure = 0;

    // OPTIMIZED: Collect all invalid tokens across batches
    const allInvalidTokens: string[] = [];

    for (const batch of batches) {
      const messages: ExpoPushMessage[] = batch.map(token => ({
        to: token,
        title: notification.title,
        body: notification.body,
        data: notification.data,
        channelId: notification.channelId,
        sound: 'default' as const,
        priority: 'high' as const,
      }));

      const response = await fetch('https://exp.host/--/api/v2/push/send', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(messages),
      });

      const result = await response.json();
      const tickets: ExpoPushTicket[] = result.data || [];

      // Process tickets and collect invalid tokens
      for (let i = 0; i < tickets.length; i++) {
        if (tickets[i].status === 'ok') {
          totalSuccess++;
        } else {
          totalFailure++;
          if (tickets[i].details?.error === 'DeviceNotRegistered') {
            allInvalidTokens.push(batch[i]);
          }
        }
      }
    }

    // OPTIMIZED: Single DELETE for all invalid tokens instead of per-batch
    if (allInvalidTokens.length > 0) {
      await removeInvalidTokensBatch(allInvalidTokens);
    }

    console.log(`Push notification sent: ${totalSuccess} success, ${totalFailure} failure`);
    return totalSuccess > 0;
  } catch (error) {
    console.error('Failed to send push notification:', error);
    return false;
  }
}

// ITEM 20: Batch remove invalid tokens in single query
async function removeInvalidTokensBatch(tokens: string[]): Promise<void> {
  if (tokens.length === 0) return;

  try {
    const supabase = getServiceClient();

    // Single DELETE for all tokens
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
  status: string,
  orderId?: string
): Promise<boolean> {
  const data: Record<string, string> = { type: 'order_update', order_number: orderNumber, status };
  if (orderId) data.order_id = orderId;

  let notification: PushNotification;

  switch (status) {
    case 'confirmed':
      notification = {
        title: 'Order Confirmed',
        body: `Your order ${orderNumber} has been confirmed!`,
        data,
        channelId: 'orders',
      };
      break;
    case 'out_for_delivery':
      notification = {
        title: 'Out for Delivery',
        body: `Your order ${orderNumber} is on its way!`,
        data,
        channelId: 'orders',
      };
      break;
    case 'delivered':
      notification = {
        title: 'Order Delivered',
        body: `Your order ${orderNumber} has been delivered. Enjoy!`,
        data,
        channelId: 'orders',
      };
      break;
    case 'cancelled':
      notification = {
        title: 'Order Cancelled',
        body: `Your order ${orderNumber} has been cancelled.`,
        data,
        channelId: 'orders',
      };
      break;
    case 'delivery_failed':
      notification = {
        title: 'Delivery Attempt Failed',
        body: `We couldn't deliver your order ${orderNumber}. We'll retry soon.`,
        data,
        channelId: 'orders',
      };
      break;
    default:
      notification = {
        title: 'Order Update',
        body: `Your order ${orderNumber} status: ${status}`,
        data,
        channelId: 'orders',
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
    channelId: 'orders',
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
    channelId: 'orders',
  });
}
