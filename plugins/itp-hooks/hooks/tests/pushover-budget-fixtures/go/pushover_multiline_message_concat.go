package main

import (
	"fmt"
	"net/http"
	"net/url"
)

func sendDetailedAlert(token, user string) error {
	message := "Service degradation detected.\n" +
		"Timestamp: 2026-05-29T14:30:00Z\n" +
		"Component: api-gateway-v2\n" +
		"Error rate: 12.5%\n" +
		"Action: Check /var/log/svc.log on prod-02"

	payload := url.Values{
		"token":   []string{token},
		"user":    []string{user},
		"message": []string{message},
		"title":   []string{"ALERT: api-gateway-v2"},
	}

	_, err := http.PostForm("https://api.pushover.net/1/messages.json", payload)
	return err
}