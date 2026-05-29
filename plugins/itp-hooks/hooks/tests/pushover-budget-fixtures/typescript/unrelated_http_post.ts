async function sendDataToAnalytics(event: string, payload: object) {
  const response = await fetch('https://analytics.example.com/api/v1/events', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      event_name: event,
      data: payload,
      timestamp: Date.now(),
    }),
  });

  return response.json();
}
