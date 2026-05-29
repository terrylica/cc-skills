import { Client } from 'node-pushover';

const client = new Client({
  token: process.env.PUSHOVER_APP_TOKEN!,
  user: process.env.PUSHOVER_USER_KEY!,
});

const notification = {
  title: 'System Alert',
  message: 'Health check failed: response timeout after 30s',
  priority: 2,
  sound: 'alarm',
  device: process.env.PUSHOVER_DEVICE || 'all',
};

client.send(notification).then(() => {
  console.log('Notification sent successfully');
}).catch((err) => {
  console.error('Failed to send:', err);
});
