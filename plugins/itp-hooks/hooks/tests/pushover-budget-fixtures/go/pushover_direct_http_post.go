package main

import (
	"net/http"
	"net/url"
	"strings"
)

func sendPushoverAlert(token, user, message string) error {
	data := url.Values{}
	data.Set("token", token)
	data.Set("user", user)
	data.Set("message", message)
	data.Set("title", "Deployment Alert")

	resp, err := http.PostForm("https://api.pushover.net/1/messages.json",
		data)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	return nil
}