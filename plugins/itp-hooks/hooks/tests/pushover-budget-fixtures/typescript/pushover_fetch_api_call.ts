// Send notification via fetch to Pushover API
const sendNotification = async (title: string, message: string) => {
  const body = new URLSearchParams({
    token: process.env.PUSHOVER_APP_TOKEN!,
    user: process.env.PUSHOVER_USER_KEY!,
    title: title,
    message: message,
    priority: '1',
    sound: 'pushover',
  });

  const response = await fetch('https://api.pushover.net/1/messages.json', {
    method: 'POST',
    body: body,
  });

  return response.json();
};
