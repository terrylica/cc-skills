package main

import (
	"github.com/gregdel/pushover"
)

func sendLongStatusReport(apiToken, userKey string) error {
	messageBody := `Incident Report: 2026-05-29
` +
		`Status: RESOLVED
` +
		`Duration: 47 minutes
` +
		`Root Cause: BGP route leak on ISP-2
` +
		`Impact: Read-heavy workloads, 15% increase in latency
` +
		`Mitigation: Failover to ISP-1, restored at 14:25 UTC`

	client := pushover.New(apiToken)
	message := &pushover.Message{
		Title:   "Incident Resolved",
		Message: messageBody,
		Priority: pushover.PriorityHigh,
	}

	_, err := client.SendMessage(message, &pushover.Recipient{Key: userKey})
	return err
}