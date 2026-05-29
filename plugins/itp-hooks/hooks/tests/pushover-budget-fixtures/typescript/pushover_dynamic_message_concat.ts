async function alertOnError(code: number, details: string) {
  const title = `Alert: Error ${code}`;
  const msgBody = `Status: CRITICAL\nDetails: ${details}\nTime: ${new Date().toISOString()}`;
  
  const params = new URLSearchParams();
  params.set('token', process.env.PUSHOVER_APP_TOKEN!);
  params.set('user', process.env.PUSHOVER_USER_KEY!);
  params.set('title', title);
  params.set('message', msgBody);
  params.set('priority', code > 500 ? '2' : '1');

  await fetch('https://api.pushover.net/1/messages.json', {
    method: 'POST',
    body: params,
  });
}
