import fs from 'fs';
import fetch from 'node-fetch';

const sendWithImage = async (title: string, message: string, imagePath: string) => {
  const imageData = fs.readFileSync(imagePath);
  const base64Image = imageData.toString('base64');

  const body = new FormData();
  body.append('token', process.env.PUSHOVER_APP_TOKEN!);
  body.append('user', process.env.PUSHOVER_USER_KEY!);
  body.append('title', title);
  body.append('message', message);
  body.append('image', Buffer.from(base64Image, 'base64'));

  const response = await fetch('https://api.pushover.net/1/messages.json', {
    method: 'POST',
    body: body,
  });

  return response.json();
};
