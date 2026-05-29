package main

import (
	"net/http"
	"net/url"
)

func sendPushoverBudgetOk(token, user, message string) error {
	payload := url.Values{
		"token":   []string{token},
		"user":    []string{user},
		"message": []string{message},
		"title":   []string{"Status: PUSHOVER-BUDGET-OK"},
	}

	_, err := http.PostForm("https://api.pushover.net/1/messages.json", payload)
	return err
}