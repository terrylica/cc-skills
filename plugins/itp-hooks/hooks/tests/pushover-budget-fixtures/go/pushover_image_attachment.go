package main

import (
	"bytes"
	"encoding/base64"
	"io/ioutil"
	"mime/multipart"
	"net/http"
)

func sendPushoverWithImage(token, user, imagePath string) error {
	data, err := ioutil.ReadFile(imagePath)
	if err != nil {
		return err
	}

	buf := &bytes.Buffer{}
	writer := multipart.NewWriter(buf)

	writer.WriteField("token", token)
	writer.WriteField("user", user)
	writer.WriteField("message", "Screenshot attached")
	writer.WriteField("title", "Error Screenshot")

	imagePart, _ := writer.CreateFormFile("attachment", "screenshot.png")
	imagePart.Write(data)
	writer.Close()

	req, _ := http.NewRequest("POST", "https://api.pushover.net/1/messages.json", buf)
	req.Header.Set("Content-Type", writer.FormDataContentType())

	client := &http.Client{}
	_, err = client.Do(req)
	return err
}