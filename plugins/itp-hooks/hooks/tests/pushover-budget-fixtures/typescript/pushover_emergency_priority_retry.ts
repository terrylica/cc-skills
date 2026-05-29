async function sendEmergencyAlert(details: string) {
  const body = new URLSearchParams();
  body.set('token', process.env.PUSHOVER_APP_TOKEN!);
  body.set('user', process.env.PUSHOVER_USER_KEY!);
  body.set('title', 'EMERGENCY');
  body.set('message', details);
  body.set('priority', '2');
  body.set('retry', '60');
  body.set('expire', '600');
  body.set('sound', 'siren');

  const response = await fetch('https://api.pushover.net/1/messages.json', {
    method: 'POST',
    body: body,
  });

  if (!response.ok) {
    throw new Error(`Pushover API error: ${response.status}`);
  }

  return response.json();
}
