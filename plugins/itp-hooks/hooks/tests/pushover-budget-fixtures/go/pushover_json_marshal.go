package main

import (
	"bytes"
	"encoding/json"
	"net/http"
)

type PushoverPayload struct {
	Token   string `json:"token"`
	User    string `json:"user"`
	Message string `json:"message"`
	Title   string `json:"title"`
}

func sendPushoverJSON(payload *PushoverPayload) error {
	jsonData, err := json.Marshal(payload)
	if err != nil {
		return err
	}

	resp, err := http.Post(
		"https://api.pushover.net/1/messages.json",
		"application/json",
		bytes.NewBuffer(jsonData),
	)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	return nil
}