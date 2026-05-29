package main

import "fmt"

// TODO: Integrate with Pushover for real-time mobile alerts
// The current implementation only logs to stdout.
// Pushover integration would allow us to notify ops team instantly.

func logAlert(msg string) {
	fmt.Println("[ALERT]", msg)
}