package main

import (
	"net/http"
	"net/url"
)

func sendBriefNotification(token, user string) error {
	payload := url.Values{
		"token": []string{token},
		"user":  []string{user},
		"title": []string{"Deployment Complete"},
	}

	_, err := http.PostForm("https://api.pushover.net/1/messages.json", payload)
	return err
}