package main

import (
	"net/http"
	"net/url"
)

func submitMetrics(endpoint string) error {
	data := url.Values{
		"timestamp": []string{"2026-05-29T14:30:00Z"},
		"cpu_usage": []string{"45.2"},
		"memory_mb": []string{"2048"},
	}

	resp, err := http.PostForm("https://metrics.example.com/api/submit", data)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	return nil
}