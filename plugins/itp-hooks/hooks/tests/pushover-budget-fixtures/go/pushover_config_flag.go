package main

import (
	"flag"
)

var (
	pushoverEnabled = flag.Bool("pushover-enabled", false, "Enable Pushover notifications")
	pushoverToken   = flag.String("pushover-token", "", "Pushover app token")
)

func init() {
	flag.Parse()

	if *pushoverEnabled {
		// initialize pushover client
	}
}