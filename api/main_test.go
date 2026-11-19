package main

import (
	"testing"
	"time"
)

func TestGetTime(t *testing.T) {
	ts := time.Date(2026, 11, 16, 12, 0, 0, 0, time.UTC)

	cases := []struct {
		name string
		data map[string]interface{}
		want time.Time
	}{
		{"timestamp", map[string]interface{}{"k": ts}, ts},
		{"missing", map[string]interface{}{}, time.Time{}},
		{"null (seeded empty seat)", map[string]interface{}{"k": nil}, time.Time{}},
		{"wrong type", map[string]interface{}{"k": "2026-11-16"}, time.Time{}},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := getTime(c.data, "k"); !got.Equal(c.want) {
				t.Errorf("getTime() = %v, want %v", got, c.want)
			}
		})
	}
}
