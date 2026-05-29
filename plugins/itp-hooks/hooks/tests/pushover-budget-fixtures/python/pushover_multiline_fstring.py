#!/usr/bin/env python3
import requests

def send_deployment_report(service, version, duration_secs, errors):
    token = "secret_token"
    user = "secret_user"
    
    # Build message body across multiple lines
    message = f"""Deploy {service}:{version} completed
Duration: {duration_secs}s
Errors: {errors}
Status: OK"""
    
    title = f"{service} Release"
    
    resp = requests.post(
        "https://api.pushover.net/1/messages.json",
        data={
            "token": token,
            "user": user,
            "title": title,
            "message": message
        }
    )
    return resp.json()
