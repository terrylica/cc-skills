const buildAlert = (service: string, version: string, status: string) => {
  const message = `
Service: ${service}
Version: ${version}
Status: ${status}
Timestamp: ${new Date().toISOString()}
Action: Review deployment logs
  `.trim();

  const body = new URLSearchParams({
    token: process.env.PUSHOVER_APP_TOKEN!,
    user: process.env.PUSHOVER_USER_KEY!,
    title: `${service} Deployment Alert`,
    message: message,
    priority: '1',
    url: `https://dashboard.example.com/services/${service}`,
    url_title: 'View Service',
  });

  return fetch('https://api.pushover.net/1/messages.json', {
    method: 'POST',
    body: body,
  });
};
