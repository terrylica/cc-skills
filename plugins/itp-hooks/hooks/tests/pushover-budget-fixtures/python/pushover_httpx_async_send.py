#!/usr/bin/env python3
import asyncio
import httpx

async def send_alert():
    token = "app_token_secret"
    user_key = "user_key_secret"
    
    msg_body = "Database backup completed. Size: 125GB, Checksum: verified, Time: 45 minutes."
    msg_title = "Backup Complete"
    
    async with httpx.AsyncClient() as client:
        response = await client.post(
            "https://api.pushover.net/1/messages.json",
            data={
                "token": token,
                "user": user_key,
                "title": msg_title,
                "message": msg_body,
                "priority": 0
            }
        )
        return response.json()

asyncio.run(send_alert())
