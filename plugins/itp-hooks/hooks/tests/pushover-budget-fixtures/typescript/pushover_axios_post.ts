import axios from 'axios';

const notifyViaAxios = async (userKey: string, appToken: string, event: string) => {
  const payload = {
    token: appToken,
    user: userKey,
    title: `Event Notification`,
    message: `An important event occurred: ${event}`,
    priority: 0,
  };

  try {
    const result = await axios.post('https://api.pushover.net/1/messages.json', payload);
    console.log('Pushover response:', result.data);
  } catch (err) {
    console.error('Pushover send failed', err);
  }
};
