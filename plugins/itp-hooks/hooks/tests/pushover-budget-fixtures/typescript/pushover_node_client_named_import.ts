import Pushover from 'pushover-notifications';

const p = new Pushover({
  user: process.env.PUSHOVER_USER_KEY,
  token: process.env.PUSHOVER_APP_TOKEN,
});

const msg = {
  title: 'Deployment Complete',
  message: 'Service v1.2.3 deployed successfully with 0 errors',
  priority: 1,
  sound: 'shipbell',
  device: 'iphone',
};

p.send(msg, (err: any, result: any) => {
  if (err) throw err;
  console.log(result);
});
