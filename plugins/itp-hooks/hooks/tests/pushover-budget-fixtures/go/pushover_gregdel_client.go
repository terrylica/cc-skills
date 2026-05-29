package main

import (
	"github.com/gregdel/pushover"
)

func notifyDeployment(apiToken, userKey, buildID string) error {
	message := &pushover.Message{
		Title:   "Build Completed",
		Message: "Deployment for " + buildID + " finished successfully",
		URL:     "https://ci.example.com/builds/" + buildID,
		URLTitle: "View Build",
	}

	client := pushover.New(apiToken)
	response, err := client.SendMessage(message, &pushover.Recipient{Key: userKey})
	if err != nil {
		return err
	}
	// response.Status == 1 indicates success
	return nil
}