async function sendProvenance(summary: string, details: string) {
  // PUSHOVER-BUDGET-OK: This message already uses structured format with URL codes
  const msg = {
    token: process.env.PUSHOVER_APP_TOKEN,
    user: process.env.PUSHOVER_USER_KEY,
    title: 'Deployment',
    message: `${summary}\nDEPLOY_ID=abc123\nBUILD_URL=https://ci.example.com/builds/456`,
    priority: 0,
  };

  const params = new URLSearchParams(msg as Record<string, string>);
  return fetch('https://api.pushover.net/1/messages.json', {
    method: 'POST',
    body: params,
  });
}
