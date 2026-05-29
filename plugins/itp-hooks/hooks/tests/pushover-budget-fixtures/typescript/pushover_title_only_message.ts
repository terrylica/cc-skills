async function sendQuickAlert(priority: number = 1) {
  const minimal = {
    token: process.env.PUSHOVER_APP_TOKEN,
    user: process.env.PUSHOVER_USER_KEY,
    title: 'Critical Alert',
    priority: priority,
  };

  const params = new URLSearchParams(minimal as Record<string, string>);
  const res = await fetch('https://api.pushover.net/1/messages.json', {
    method: 'POST',
    body: params,
  });

  return res.json();
}
